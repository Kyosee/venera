import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_state_repository.dart';
import 'package:venera/foundation/favorites.dart';

enum RelatedSourceTaskStatus { running, paused, completed, canceled, failed }

class RelatedSourceProgress {
  RelatedSourceProgress({
    required this.sourceKey,
    required this.sourceName,
    this.total = 0,
    this.checked = 0,
    this.candidates = 0,
    this.failed = 0,
    List<String>? errors,
  }) : errors = errors ?? <String>[];

  final String sourceKey;
  final String sourceName;
  int total;
  int checked;
  int candidates;
  int failed;
  final List<String> errors;

  Map<String, dynamic> toJson() => {
    'sourceKey': sourceKey,
    'sourceName': sourceName,
    'total': total,
    'checked': checked,
    'candidates': candidates,
    'failed': failed,
    'errors': errors,
  };

  factory RelatedSourceProgress.fromJson(Map<String, dynamic> json) {
    return RelatedSourceProgress(
      sourceKey: json['sourceKey'] ?? '',
      sourceName: json['sourceName'] ?? '',
      total: json['total'] ?? 0,
      checked: json['checked'] ?? 0,
      candidates: json['candidates'] ?? 0,
      failed: json['failed'] ?? 0,
      errors: (json['errors'] as List?)?.whereType<String>().toList(),
    );
  }
}

class RelatedSourceTaskComic {
  RelatedSourceTaskComic(this.favorite);

  final FavoriteItem favorite;

  String get id => favorite.id;
  String get sourceKey => favorite.sourceKey;
  String get title => favorite.title;

  Map<String, dynamic> toJson() => favorite.toJson();

  factory RelatedSourceTaskComic.fromJson(Map<String, dynamic> json) {
    return RelatedSourceTaskComic(FavoriteItem.fromJson(json));
  }
}

class RelatedSourceTask {
  RelatedSourceTask({
    required this.id,
    required this.folder,
    required this.createdAt,
    required this.comics,
    required this.targetSourceKeys,
    required this.sources,
    this.status = RelatedSourceTaskStatus.running,
    this.total = 0,
    this.checked = 0,
    this.candidates = 0,
    this.failed = 0,
    this.currentComicIndex = 0,
    this.currentSourceIndex = 0,
    List<String>? errors,
    this.finishedAt,
  }) : errors = errors ?? <String>[];

  final String id;
  final String folder;
  final DateTime createdAt;
  final List<RelatedSourceTaskComic> comics;
  final List<String> targetSourceKeys;
  final Map<String, RelatedSourceProgress> sources;
  RelatedSourceTaskStatus status;
  int total;
  int checked;
  int candidates;
  int failed;
  int currentComicIndex;
  int currentSourceIndex;
  final List<String> errors;
  DateTime? finishedAt;

  bool get isRunning => status == RelatedSourceTaskStatus.running;
  bool get isPaused => status == RelatedSourceTaskStatus.paused;
  bool get isActive => isRunning || isPaused;

  double get progress => total == 0 ? 0 : checked / total;

  Map<String, dynamic> toJson() => {
    'id': id,
    'folder': folder,
    'createdAt': createdAt.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'status': status.name,
    'total': total,
    'checked': checked,
    'candidates': candidates,
    'failed': failed,
    'currentComicIndex': currentComicIndex,
    'currentSourceIndex': currentSourceIndex,
    'errors': errors,
    'targetSourceKeys': targetSourceKeys,
    'comics': comics.map((comic) => comic.toJson()).toList(),
    'sources': sources.map((key, value) => MapEntry(key, value.toJson())),
  };

  factory RelatedSourceTask.fromJson(Map<String, dynamic> json) {
    final sourceData = Map<String, dynamic>.from(json['sources'] ?? {});
    return RelatedSourceTask(
      id: json['id'] ?? '',
      folder: json['folder'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      finishedAt: DateTime.tryParse(json['finishedAt'] ?? ''),
      status: RelatedSourceTaskStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => RelatedSourceTaskStatus.completed,
      ),
      total: json['total'] ?? 0,
      checked: json['checked'] ?? 0,
      candidates: json['candidates'] ?? 0,
      failed: json['failed'] ?? 0,
      currentComicIndex: json['currentComicIndex'] ?? 0,
      currentSourceIndex: json['currentSourceIndex'] ?? 0,
      errors: (json['errors'] as List?)?.whereType<String>().toList(),
      targetSourceKeys:
          (json['targetSourceKeys'] as List?)?.whereType<String>().toList() ??
          const <String>[],
      comics:
          (json['comics'] as List?)?.whereType<Map>().map((item) {
            return RelatedSourceTaskComic.fromJson(
              Map<String, dynamic>.from(item),
            );
          }).toList() ??
          const <RelatedSourceTaskComic>[],
      sources: sourceData.map((key, value) {
        return MapEntry(
          key,
          RelatedSourceProgress.fromJson(Map<String, dynamic>.from(value)),
        );
      }),
    );
  }
}

class RelatedSourceTaskManager with ChangeNotifier {
  RelatedSourceTaskManager._() {
    _load();
    Future.microtask(_resumeRunningTasks);
  }

  static final RelatedSourceTaskManager instance = RelatedSourceTaskManager._();

  final currentTasks = <RelatedSourceTask>[];
  final historyTasks = <RelatedSourceTask>[];
  final _runningIds = <String>{};
  final _canceledIds = <String>{};
  final _repository = const ComicStateRepository();

  RelatedSourceTask? startAutoLink({
    required String folder,
    required List<FavoriteItem> favorites,
    required List<String> targetSourceKeys,
  }) {
    final existing = currentTasks
        .where((task) => task.folder == folder && task.isActive)
        .firstOrNull;
    if (existing != null) {
      return existing;
    }
    final comics = favorites.map(RelatedSourceTaskComic.new).toList();
    final sources = _buildSources(comics, targetSourceKeys);
    final total = sources.values.fold(0, (sum, source) => sum + source.total);
    final task = RelatedSourceTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      folder: folder,
      createdAt: DateTime.now(),
      comics: comics,
      targetSourceKeys: targetSourceKeys,
      sources: sources,
      total: total,
    );
    currentTasks.insert(0, task);
    _saveActive();
    notifyListeners();
    unawaited(_run(task));
    return task;
  }

  void pause(String id) {
    final task = _activeTask(id);
    if (task == null || !task.isRunning) {
      return;
    }
    task.status = RelatedSourceTaskStatus.paused;
    _saveActive();
    notifyListeners();
  }

  void resume(String id) {
    final task = _activeTask(id);
    if (task == null || !task.isPaused) {
      return;
    }
    task.status = RelatedSourceTaskStatus.running;
    _saveActive();
    notifyListeners();
    unawaited(_run(task));
  }

  void cancel(String id) {
    final task = _activeTask(id);
    if (task == null) {
      return;
    }
    if (task.isPaused) {
      task.status = RelatedSourceTaskStatus.canceled;
      _finish(task);
      return;
    }
    _canceledIds.add(id);
    notifyListeners();
  }

  Future<void> _run(RelatedSourceTask task) async {
    if (!_runningIds.add(task.id)) {
      return;
    }
    try {
      while (task.currentComicIndex < task.comics.length) {
        if (!_canContinue(task)) {
          break;
        }
        final comic = task.comics[task.currentComicIndex].favorite;
        _repository.mirrorComic(comic);
        while (task.currentSourceIndex < task.targetSourceKeys.length) {
          if (!_canContinue(task)) {
            break;
          }
          final sourceKey = task.targetSourceKeys[task.currentSourceIndex];
          task.currentSourceIndex++;
          if (sourceKey == comic.sourceKey) {
            _saveActive();
            continue;
          }
          await _searchOne(task, comic, sourceKey);
          task.checked++;
          _saveActive();
          notifyListeners();
          await Future.delayed(const Duration(milliseconds: 650));
        }
        if (!_canContinue(task)) {
          break;
        }
        task.currentComicIndex++;
        task.currentSourceIndex = 0;
        _saveActive();
      }
      if (_canceledIds.contains(task.id)) {
        task.status = RelatedSourceTaskStatus.canceled;
      }
      if (task.status == RelatedSourceTaskStatus.running) {
        task.status = RelatedSourceTaskStatus.completed;
      }
      if (!task.isPaused) {
        _finish(task);
      }
    } catch (e) {
      task.status = RelatedSourceTaskStatus.failed;
      task.errors.add(e.toString());
      _finish(task);
    } finally {
      _runningIds.remove(task.id);
      _canceledIds.remove(task.id);
      notifyListeners();
    }
  }

  Future<void> _searchOne(
    RelatedSourceTask task,
    FavoriteItem comic,
    String sourceKey,
  ) async {
    final source = ComicSource.find(sourceKey);
    final progress = task.sources[sourceKey];
    if (source == null || source.searchPageData == null || progress == null) {
      _recordFailure(task, progress, comic, 'Source unavailable');
      return;
    }
    final searchData = source.searchPageData!;
    final options =
        searchData.searchOptions
            ?.map((option) => option.defaultValue)
            .toList() ??
        const <String>[];
    try {
      final before = _candidateIds(comic);
      final res = searchData.loadPage != null
          ? await searchData.loadPage!(comic.title, 1, options)
          : await searchData.loadNext!(comic.title, null, options);
      final results = res.dataOrNull;
      if (results == null) {
        _recordFailure(
          task,
          progress,
          comic,
          res.errorMessage ?? 'Search failed',
        );
        return;
      }
      for (final result in results.take(8)) {
        _repository.mirrorComic(result);
      }
      final after = _candidateIds(comic);
      final newCandidates = after.difference(before).length;
      progress.candidates += newCandidates;
      task.candidates += newCandidates;
    } catch (e) {
      _recordFailure(task, progress, comic, e.toString());
    } finally {
      progress.checked++;
    }
  }

  void _recordFailure(
    RelatedSourceTask task,
    RelatedSourceProgress? progress,
    FavoriteItem comic,
    String error,
  ) {
    task.failed++;
    progress?.failed++;
    final detail = '${comic.title}: $error';
    progress?.errors.add(detail);
    task.errors.add(
      progress == null ? detail : '${progress.sourceName} / $detail',
    );
  }

  Set<String> _candidateIds(FavoriteItem comic) {
    return _repository
        .relatedSourcesFor(comic)
        .where((link) => link.status == 'candidate')
        .map((link) => link.comicId)
        .toSet();
  }

  bool _canContinue(RelatedSourceTask task) {
    return task.status == RelatedSourceTaskStatus.running &&
        !_canceledIds.contains(task.id);
  }

  RelatedSourceTask? _activeTask(String id) {
    return currentTasks.where((task) => task.id == id).firstOrNull;
  }

  void _finish(RelatedSourceTask task) {
    task.finishedAt = DateTime.now();
    currentTasks.remove(task);
    historyTasks.insert(0, task);
    if (historyTasks.length > 50) {
      historyTasks.removeRange(50, historyTasks.length);
    }
    _saveActive();
    _saveHistory();
  }

  Map<String, RelatedSourceProgress> _buildSources(
    List<RelatedSourceTaskComic> comics,
    List<String> sourceKeys,
  ) {
    final result = <String, RelatedSourceProgress>{};
    for (final sourceKey in sourceKeys) {
      final source = ComicSource.find(sourceKey);
      final progress = RelatedSourceProgress(
        sourceKey: sourceKey,
        sourceName: source?.name ?? sourceKey,
      );
      for (final comic in comics) {
        if (comic.sourceKey != sourceKey) {
          progress.total++;
        }
      }
      if (progress.total > 0) {
        result[sourceKey] = progress;
      }
    }
    return result;
  }

  void _resumeRunningTasks() {
    for (final task in currentTasks) {
      if (task.status == RelatedSourceTaskStatus.running) {
        unawaited(_run(task));
      }
    }
  }

  void _load() {
    final activeData = appdata.implicitData['related_source_active_tasks'];
    if (activeData is List) {
      currentTasks
        ..clear()
        ..addAll(
          activeData
              .whereType<Map>()
              .map((item) {
                return RelatedSourceTask.fromJson(
                  Map<String, dynamic>.from(item),
                );
              })
              .where((task) => task.isActive),
        );
    }
    final historyData = appdata.implicitData['related_source_task_history'];
    if (historyData is List) {
      historyTasks
        ..clear()
        ..addAll(
          historyData.whereType<Map>().map((item) {
            return RelatedSourceTask.fromJson(Map<String, dynamic>.from(item));
          }),
        );
    }
  }

  void _saveActive() {
    appdata.implicitData['related_source_active_tasks'] = currentTasks
        .map((task) => task.toJson())
        .toList();
    appdata.writeImplicitData();
  }

  void _saveHistory() {
    appdata.implicitData['related_source_task_history'] = historyTasks
        .map((task) => task.toJson())
        .toList();
    appdata.writeImplicitData();
  }
}
