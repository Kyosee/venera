import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/background_keepalive.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/image_translation/translation_service.dart';
import 'package:venera/foundation/image_translation/translation_types.dart';
import 'package:venera/foundation/local.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/network/images.dart';

enum PreTranslationTaskStatus { running, paused, completed, canceled, failed }

/// One chapter queued for background pre-translation.
class PreTranslationChapter {
  PreTranslationChapter({
    required this.eid,
    required this.title,
    this.total = 0,
    this.done = 0,
    this.failed = 0,
  });

  /// Source chapter id (the eid passed to loadComicPages / image keys). For a
  /// comic without chapters this is '0'.
  final String eid;
  final String title;

  /// Page count, resolved lazily when the chapter starts.
  int total;
  int done;
  int failed;

  Map<String, dynamic> toJson() => {
    'eid': eid,
    'title': title,
    'total': total,
    'done': done,
    'failed': failed,
  };

  factory PreTranslationChapter.fromJson(Map<String, dynamic> json) {
    return PreTranslationChapter(
      eid: json['eid']?.toString() ?? '0',
      title: json['title']?.toString() ?? '',
      total: json['total'] ?? 0,
      done: json['done'] ?? 0,
      failed: json['failed'] ?? 0,
    );
  }
}

/// A background job that pre-translates selected chapters of one comic so the
/// rendered pages are cached before the user opens the reader.
///
/// It reuses [ImageTranslationService.translateOne] and therefore writes to
/// the exact cache keys the reader reads from — a pre-translated page shows
/// instantly with no in-reader wait.
class PreTranslationTask {
  PreTranslationTask({
    required this.id,
    required this.cid,
    required this.sourceKey,
    required this.comicType,
    required this.title,
    required this.chapters,
    required this.createdAt,
    this.status = PreTranslationTaskStatus.running,
    this.finishedAt,
  });

  final String id;
  final String cid;
  final String sourceKey;
  final ComicType comicType;
  final String title;
  final List<PreTranslationChapter> chapters;
  final DateTime createdAt;
  PreTranslationTaskStatus status;
  DateTime? finishedAt;

  String get comicKey => '$cid@$sourceKey';

  bool get isRunning => status == PreTranslationTaskStatus.running;

  int get total => chapters.fold(0, (sum, c) => sum + c.total);
  int get done => chapters.fold(0, (sum, c) => sum + c.done);
  int get failed => chapters.fold(0, (sum, c) => sum + c.failed);

  /// Overall progress across the whole job, weighted by chapters rather than
  /// pages. Each chapter contributes an equal 1/N slice; a chapter whose page
  /// count is not resolved yet (total == 0) counts as 0% until it starts, and a
  /// fully processed chapter counts as 100%. This keeps the percentage
  /// representative of the entire comic (all selected chapters), and monotonic,
  /// instead of tracking only the page counts of chapters that have already
  /// begun — which made the earlier page-based ratio jump around as new
  /// chapters resolved their totals.
  double get progress {
    if (chapters.isEmpty) return 0;
    var sum = 0.0;
    for (var c in chapters) {
      if (c.total <= 0) continue;
      sum += ((c.done + c.failed) / c.total).clamp(0.0, 1.0);
    }
    return sum / chapters.length;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'cid': cid,
    'sourceKey': sourceKey,
    'comicType': comicType.value,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'status': status.name,
    'chapters': chapters.map((c) => c.toJson()).toList(),
  };

  factory PreTranslationTask.fromJson(Map<String, dynamic> json) {
    return PreTranslationTask(
      id: json['id']?.toString() ?? '',
      cid: json['cid']?.toString() ?? '',
      sourceKey: json['sourceKey']?.toString() ?? '',
      comicType: ComicType(json['comicType'] ?? 0),
      title: json['title']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      finishedAt: DateTime.tryParse(json['finishedAt'] ?? ''),
      status: PreTranslationTaskStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => PreTranslationTaskStatus.completed,
      ),
      chapters: (json['chapters'] as List? ?? [])
          .whereType<Map>()
          .map((e) => PreTranslationChapter.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// Manages background pre-translation jobs. Mirrors the structure of the
/// other task managers (currentTasks / historyTasks / persistence) so the
/// tasks page can render it the same way.
class PreTranslationTaskManager with ChangeNotifier {
  PreTranslationTaskManager._() {
    _load();
  }

  static final PreTranslationTaskManager instance =
      PreTranslationTaskManager._();

  final currentTasks = <PreTranslationTask>[];
  final historyTasks = <PreTranslationTask>[];
  final _canceledIds = <String>{};
  final _runningIds = <String>{};

  void Function(PreTranslationTask task)? onTaskFinished;

  /// Starts pre-translating [chapters] (source chapter ids) of a comic. Returns
  /// null when translation is not usable (models/endpoint not configured) or a
  /// job for the comic is already running.
  PreTranslationTask? start({
    required String cid,
    required String sourceKey,
    required ComicType comicType,
    required String title,
    required List<PreTranslationChapter> chapters,
  }) {
    if (!ImageTranslationService.isReady || chapters.isEmpty) {
      return null;
    }
    var existing = currentTasks
        .where((t) => t.comicKey == '$cid@$sourceKey' && t.isRunning)
        .firstOrNull;
    if (existing != null) {
      return existing;
    }
    var task = PreTranslationTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      cid: cid,
      sourceKey: sourceKey,
      comicType: comicType,
      title: title,
      chapters: chapters,
      createdAt: DateTime.now(),
    );
    currentTasks.insert(0, task);
    _saveActive();
    notifyListeners();
    unawaited(_run(task));
    return task;
  }

  /// Whether a running job exists for the comic (detail page badge).
  PreTranslationTask? runningTaskFor(String cid, String sourceKey) {
    return currentTasks
        .where((t) => t.comicKey == '$cid@$sourceKey' && t.isRunning)
        .firstOrNull;
  }

  /// Best-known progress of a chapter for a comic, looking first at a running
  /// job and then at the most recent finished job. Lets the chapter picker show
  /// a "translated" / progress marker even after the app restarts or the task
  /// moved to history, so already-done chapters are obvious and not re-queued
  /// blindly.
  PreTranslationChapter? chapterProgressFor(
    String cid,
    String sourceKey,
    String eid,
  ) {
    var comicKey = '$cid@$sourceKey';
    // A running/paused job owns the chapter: return it even before its page
    // count is known (total == 0) so the picker can show a "waiting" state for
    // queued-but-not-started chapters, not just active ones.
    for (var task in currentTasks) {
      if (task.comicKey != comicKey) continue;
      var chapter = task.chapters.where((c) => c.eid == eid).firstOrNull;
      if (chapter != null) return chapter;
    }
    // Otherwise only report a finished chapter (all pages accounted for) so a
    // canceled/failed run does not masquerade as in-progress after restart.
    for (var task in historyTasks) {
      if (task.comicKey != comicKey) continue;
      var chapter = task.chapters.where((c) => c.eid == eid).firstOrNull;
      if (chapter != null &&
          chapter.total > 0 &&
          chapter.done + chapter.failed >= chapter.total) {
        return chapter;
      }
    }
    return null;
  }

  /// Whether a chapter belongs to a currently running/paused job (so the picker
  /// can distinguish "queued/among this run" from a finished-in-history one).
  bool isChapterActive(String cid, String sourceKey, String eid) {
    var comicKey = '$cid@$sourceKey';
    for (var task in currentTasks) {
      if (task.comicKey != comicKey) continue;
      if (task.chapters.any((c) => c.eid == eid)) return true;
    }
    return false;
  }

  void cancel(String id) {
    _canceledIds.add(id);
    var task = currentTasks.where((t) => t.id == id).firstOrNull;
    if (task == null) {
      notifyListeners();
      return;
    }
    task.status = PreTranslationTaskStatus.canceled;
    _moveToHistory(task);
    if (!_runningIds.contains(id)) {
      _canceledIds.remove(id);
    }
    notifyListeners();
  }

  /// Pauses a running pre-translation job. The worker loop checks this state
  /// between pages and waits until [resume] is called or the job is canceled.
  void pause(String id) {
    var task = currentTasks.where((t) => t.id == id).firstOrNull;
    if (task == null || !task.isRunning) return;
    task.status = PreTranslationTaskStatus.paused;
    _saveActive();
    notifyListeners();
  }

  /// Resumes a paused pre-translation job.
  void resume(String id) {
    var task = currentTasks.where((t) => t.id == id).firstOrNull;
    if (task == null || task.status != PreTranslationTaskStatus.paused) return;
    task.status = PreTranslationTaskStatus.running;
    _saveActive();
    notifyListeners();
    if (!_runningIds.contains(id)) {
      unawaited(_run(task));
    }
  }

  void _refreshKeepAlive(PreTranslationTask task) {
    BackgroundKeepAlive.instance.update(
      BackgroundKeepAlive.tagPreTranslate,
      formatTaskStatus(
        title: task.title,
        detail: task.total == 0 ? null : '${task.done}/${task.total}',
      ),
    );
  }

  Future<void> _run(PreTranslationTask task) async {
    if (_runningIds.contains(task.id)) return;
    if (_canceledIds.contains(task.id) || !currentTasks.contains(task)) {
      return;
    }
    _runningIds.add(task.id);
    _refreshKeepAlive(task);
    try {
      for (var chapter in task.chapters) {
        if (_canceledIds.contains(task.id)) break;
        await _waitWhilePaused(task);
        if (_canceledIds.contains(task.id)) break;
        await _runChapter(task, chapter);
      }
      if (task.status == PreTranslationTaskStatus.running) {
        task.status = task.failed > 0 && task.done == 0
            ? PreTranslationTaskStatus.failed
            : PreTranslationTaskStatus.completed;
      }
    } catch (e, s) {
      Log.error('Pre-translation', '$e', s);
      task.status = PreTranslationTaskStatus.failed;
    } finally {
      _canceledIds.remove(task.id);
      _runningIds.remove(task.id);
      _moveToHistory(task);
      if (currentTasks.every((t) => !t.isRunning)) {
        BackgroundKeepAlive.instance.remove(
          BackgroundKeepAlive.tagPreTranslate,
        );
      }
      onTaskFinished?.call(task);
      notifyListeners();
    }
  }

  /// Suspends the loop while [task] is paused, returning as soon as it resumes
  /// or gets canceled. This keeps the running isolate alive without doing work.
  Future<void> _waitWhilePaused(PreTranslationTask task) async {
    while (task.status == PreTranslationTaskStatus.paused) {
      if (_canceledIds.contains(task.id)) return;
      // Poll every second. Resume() flips the status and the next iteration
      // exits immediately.
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> _runChapter(
    PreTranslationTask task,
    PreTranslationChapter chapter,
  ) async {
    List<String> pageKeys;
    try {
      pageKeys = await _resolvePageKeys(task, chapter);
    } catch (e, s) {
      Log.error('Pre-translation', 'Failed to list pages: $e', s);
      chapter.failed = chapter.total == 0 ? 1 : chapter.total - chapter.done;
      _saveActiveThrottled();
      notifyListeners();
      return;
    }
    chapter.total = pageKeys.length;
    notifyListeners();

    // Resume across restart: pages already cached are skipped without any
    // network fetch or inference.
    var startIndex = chapter.done + chapter.failed;
    var groupSize = _batchPages;
    for (var i = startIndex; i < pageKeys.length; i += groupSize) {
      if (_canceledIds.contains(task.id)) return;
      await _waitWhilePaused(task);
      if (_canceledIds.contains(task.id)) return;
      var end = (i + groupSize).clamp(0, pageKeys.length);
      await _runGroup(task, chapter, pageKeys, i, end);
      _refreshKeepAlive(task);
      _saveActiveThrottled();
      notifyListeners();
    }
  }

  /// How many pages' bubbles to merge into one LLM request. 1 (default) keeps
  /// the historic per-page path; larger gives the model cross-page context and
  /// cuts request count. Clamped to a sane range so a bad stored value can't
  /// break the loop or overflow the model's context.
  int get _batchPages {
    var raw = appdata.settings['imageTranslationPreBatchPages'];
    var n = raw is int ? raw : int.tryParse('$raw') ?? 1;
    return n.clamp(1, 20);
  }

  /// Translates pages [start, end) of a chapter. For a single page this is the
  /// original per-page path (one page = one request); for several it fetches
  /// each page's bytes then hands the group to [translatePageGroup] so their
  /// bubbles share one request. Pages already rendered are skipped up front.
  Future<void> _runGroup(
    PreTranslationTask task,
    PreTranslationChapter chapter,
    List<String> pageKeys,
    int start,
    int end,
  ) async {
    var service = ImageTranslationService.instance;
    var pending = <({String cacheKey, Uint8List imageBytes})>[];
    var cached = 0;
    var fetchFailed = 0;
    for (var i = start; i < end; i++) {
      // Cancel before the group is counted: leave the chapter counters at the
      // group's start boundary so a resume redoes the whole group. Every page
      // is idempotent (rendered ones skip via hasRenderedPage), so nothing is
      // double-counted or skipped.
      if (_canceledIds.contains(task.id)) return;
      var imageKey = pageKeys[i];
      var cacheKey = ImageTranslationService.cacheKeyFor(
        imageKey,
        task.sourceKey,
        task.cid,
        chapter.eid,
      );
      try {
        if (await service.hasRenderedPage(cacheKey)) {
          cached++;
          continue;
        }
        var bytes = await _fetchPageBytes(task, chapter.eid, imageKey);
        pending.add((cacheKey: cacheKey, imageBytes: bytes));
      } catch (e, s) {
        Log.warning('Pre-translation', 'Page failed: $e\n$s');
        fetchFailed++;
      }
    }
    var done = cached;
    var failed = fetchFailed;
    if (pending.isNotEmpty) {
      try {
        var results = await service.translatePageGroup(
          pending,
          task.comicKey,
          shouldCancel: () => _canceledIds.contains(task.id),
        );
        for (var ok in results) {
          ok ? done++ : failed++;
        }
      } on PipelineCanceled {
        // Canceled mid-request: abandon this group's counts entirely. Pages
        // rendered before the cancel are cached and get counted (once) when the
        // group is redone on resume.
        return;
      } catch (e, s) {
        Log.warning('Pre-translation', 'Group failed: $e\n$s');
        failed += pending.length;
      }
    }
    // Apply the whole contiguous group's counts at once, so done+failed always
    // marks a contiguous processed prefix — the invariant the resume cursor
    // (startIndex = done + failed) relies on.
    chapter.done += done;
    chapter.failed += failed;
  }

  /// Resolves the ordered image keys of a chapter, from the local library when
  /// downloaded or from the comic source otherwise.
  Future<List<String>> _resolvePageKeys(
    PreTranslationTask task,
    PreTranslationChapter chapter,
  ) async {
    var downloaded = LocalManager().isDownloaded(
      task.cid,
      task.comicType,
      chapter.eid == '0' ? 0 : null,
    );
    if (downloaded) {
      return await LocalManager().getImages(
        task.cid,
        task.comicType,
        chapter.eid == '0' ? 0 : chapter.eid,
      );
    }
    var source = ComicSource.find(task.sourceKey);
    if (source?.loadComicPages == null) {
      throw 'Comic source not found';
    }
    var res = await source!.loadComicPages!(
      task.cid,
      chapter.eid == '0' ? null : chapter.eid,
    );
    if (res.error) {
      throw res.errorMessage ?? 'Failed to load pages';
    }
    return res.data;
  }

  Future<Uint8List> _fetchPageBytes(
    PreTranslationTask task,
    String eid,
    String imageKey,
  ) async {
    if (imageKey.startsWith('file://')) {
      return await File(imageKey.substring(7)).readAsBytes();
    }
    Uint8List? bytes;
    await for (var event in ImageDownloader.loadComicImage(
      imageKey,
      task.sourceKey,
      task.cid,
      eid,
    )) {
      if (event.imageBytes != null) {
        bytes = event.imageBytes;
        break;
      }
    }
    if (bytes == null) {
      throw 'Empty image data';
    }
    return bytes;
  }

  void _moveToHistory(PreTranslationTask task) {
    if (!currentTasks.remove(task)) {
      return;
    }
    task.finishedAt ??= DateTime.now();
    historyTasks.insert(0, task);
    if (historyTasks.length > 50) {
      historyTasks.removeRange(50, historyTasks.length);
    }
    _saveActive();
    _saveHistory();
  }

  // -------------------------------------------------------------------------
  // Persistence
  // -------------------------------------------------------------------------

  static const _activeKey = 'pre_translation_active_tasks';
  static const _historyKey = 'pre_translation_task_history';

  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  void _saveActiveThrottled() {
    var now = DateTime.now();
    if (now.difference(_lastSave) < const Duration(seconds: 1)) {
      return;
    }
    _lastSave = now;
    _saveActive();
  }

  void _saveActive() {
    appdata.implicitData[_activeKey] = currentTasks
        .where((t) => t.isRunning)
        .map((t) => t.toJson())
        .toList();
    appdata.writeImplicitData();
  }

  void _saveHistory() {
    appdata.implicitData[_historyKey] =
        historyTasks.map((t) => t.toJson()).toList();
    appdata.writeImplicitData();
  }

  void _load() {
    var active = appdata.implicitData[_activeKey];
    if (active is List) {
      currentTasks
        ..clear()
        ..addAll(
          active.whereType<Map>().map((e) {
            var task =
                PreTranslationTask.fromJson(Map<String, dynamic>.from(e));
            // Anything persisted as active is coerced back to running so it can
            // be resumed after a restart.
            task.status = PreTranslationTaskStatus.running;
            task.finishedAt = null;
            return task;
          }),
        );
    }
    var history = appdata.implicitData[_historyKey];
    if (history is List) {
      historyTasks
        ..clear()
        ..addAll(
          history.whereType<Map>().map(
            (e) => PreTranslationTask.fromJson(Map<String, dynamic>.from(e)),
          ),
        );
    }
  }

  /// Resumes jobs interrupted by app termination. Called once at startup.
  void resumePendingTasks() {
    for (var task in currentTasks.toList()) {
      if (task.isRunning && !_runningIds.contains(task.id)) {
        unawaited(_run(task));
      }
    }
  }

  void clearHistory() {
    historyTasks.clear();
    _saveHistory();
    notifyListeners();
  }

  /// Resets the pre-translation status the chapter picker reads from, so that
  /// after the user clears all translation results the "translated" ticks and
  /// progress markers go away too. Finished/canceled/failed jobs (history) are
  /// dropped entirely; a still-running job keeps running but its counters are
  /// zeroed so its chapters re-count from scratch against the now-empty cache.
  void clearAllChapterStatus() {
    historyTasks.clear();
    for (var task in currentTasks) {
      for (var c in task.chapters) {
        c.done = 0;
        c.failed = 0;
        c.total = 0;
      }
    }
    _saveActive();
    _saveHistory();
    notifyListeners();
  }

  /// Resets the recorded pre-translation status of specific chapters of a comic
  /// (used by the picker's selection-based re-translate). Zeroes their counters
  /// in both history and any running job so the picker stops showing them as
  /// "translated" and a fresh run re-counts them from scratch against the now
  /// cleared cache.
  void resetChapterStatus(String cid, String sourceKey, Set<String> eids) {
    if (eids.isEmpty) return;
    var comicKey = '$cid@$sourceKey';
    for (var task in [...historyTasks, ...currentTasks]) {
      if (task.comicKey != comicKey) continue;
      for (var c in task.chapters) {
        if (eids.contains(c.eid)) {
          c.done = 0;
          c.failed = 0;
          c.total = 0;
        }
      }
    }
    _saveActive();
    _saveHistory();
    notifyListeners();
  }

  /// Resets the recorded pre-translation status of every chapter of one comic
  /// (used by the detail page's whole-comic re-translate). Drops that comic's
  /// finished history entries and zeroes any running job's counters so the
  /// picker's "translated" ticks for it clear, leaving other comics untouched.
  void resetComicStatus(String cid, String sourceKey) {
    var comicKey = '$cid@$sourceKey';
    historyTasks.removeWhere((t) => t.comicKey == comicKey);
    for (var task in currentTasks) {
      if (task.comicKey != comicKey) continue;
      for (var c in task.chapters) {
        c.done = 0;
        c.failed = 0;
        c.total = 0;
      }
    }
    _saveActive();
    _saveHistory();
    notifyListeners();
  }

  void removeTask(String id) {
    historyTasks.removeWhere((t) => t.id == id);
    _saveHistory();
    notifyListeners();
  }
}
