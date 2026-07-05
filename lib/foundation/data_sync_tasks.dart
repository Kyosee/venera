import 'package:flutter/foundation.dart';
import 'package:venera/foundation/appdata.dart';

enum DataSyncTaskType { upload, download }

enum DataSyncTaskStatus { running, completed, failed, canceled }

/// A single WebDAV sync operation (upload or download), surfaced in the Tasks
/// page so users can monitor sync progress without opening settings.
class DataSyncTask {
  final String id;
  final DataSyncTaskType type;
  final DateTime createdAt;
  DateTime? finishedAt;
  DataSyncTaskStatus status;
  String? fileName;
  int? fileSize;
  double progress; // 0.0 to 1.0
  String? error;
  String? currentPhase; // e.g., "Preparing", "Uploading", "Downloading", "Applying"

  DataSyncTask({
    required this.id,
    required this.type,
    required this.createdAt,
    this.finishedAt,
    required this.status,
    this.fileName,
    this.fileSize,
    this.progress = 0.0,
    this.error,
    this.currentPhase,
  });

  bool get isRunning => status == DataSyncTaskStatus.running;
  bool get isCompleted => status == DataSyncTaskStatus.completed;
  bool get isFailed => status == DataSyncTaskStatus.failed;
  bool get isCanceled => status == DataSyncTaskStatus.canceled;
  bool get isActive => isRunning;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'createdAt': createdAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'status': status.name,
        'fileName': fileName,
        'fileSize': fileSize,
        'progress': progress,
        'error': error,
        'currentPhase': currentPhase,
      };

  factory DataSyncTask.fromJson(Map<String, dynamic> json) {
    return DataSyncTask(
      id: json['id'] ?? '',
      type: DataSyncTaskType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => DataSyncTaskType.upload,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      finishedAt: DateTime.tryParse(json['finishedAt'] ?? ''),
      status: DataSyncTaskStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DataSyncTaskStatus.completed,
      ),
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      progress: (json['progress'] ?? 0.0).toDouble(),
      error: json['error'],
      currentPhase: json['currentPhase'],
    );
  }
}

class DataSyncTaskManager with ChangeNotifier {
  DataSyncTaskManager._() {
    _loadHistory();
  }

  static final DataSyncTaskManager instance = DataSyncTaskManager._();

  static const _storageKey = 'data_sync_tasks';
  static const _maxHistory = 50;

  final List<DataSyncTask> _tasks = [];

  List<DataSyncTask> get currentTasks =>
      _tasks.where((t) => t.isRunning).toList();

  List<DataSyncTask> get historyTasks =>
      _tasks.where((t) => !t.isRunning).toList();

  void _loadHistory() {
    final raw = appdata.implicitData[_storageKey];
    if (raw is! List) return;
    try {
      _tasks.addAll(
        raw
            .cast<Map>()
            .map((e) => DataSyncTask.fromJson(Map<String, dynamic>.from(e)))
            .where((t) => !t.isRunning),
      );
    } catch (e) {
      // Corrupted data, ignore
    }
  }

  void _persist() {
    // Trim the in-memory list too — every finished sync used to append
    // forever, growing without bound over a long-lived session.
    final overflow = _tasks.where((t) => !t.isRunning).skip(_maxHistory).toList();
    for (final t in overflow) {
      _tasks.remove(t);
    }
    final history = _tasks
        .where((t) => !t.isRunning)
        .take(_maxHistory)
        .map((t) => t.toJson())
        .toList();
    appdata.implicitData[_storageKey] = history;
    appdata.writeImplicitData();
  }

  /// Create a new sync task and add it to the current tasks list.
  DataSyncTask createTask(DataSyncTaskType type) {
    final task = DataSyncTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      createdAt: DateTime.now(),
      status: DataSyncTaskStatus.running,
    );
    _tasks.insert(0, task);
    notifyListeners();
    return task;
  }

  /// Update an existing task's progress and phase.
  void updateTask(
    String id, {
    double? progress,
    String? currentPhase,
    String? fileName,
    int? fileSize,
  }) {
    try {
      final task = _tasks.firstWhere((t) => t.id == id);
      if (progress != null) task.progress = progress;
      if (currentPhase != null) task.currentPhase = currentPhase;
      if (fileName != null) task.fileName = fileName;
      if (fileSize != null) task.fileSize = fileSize;
      notifyListeners();
    } catch (e) {
      // Task not found, ignore
    }
  }

  /// Mark a task as completed.
  void completeTask(String id, {String? fileName}) {
    try {
      final task = _tasks.firstWhere((t) => t.id == id);
      task.status = DataSyncTaskStatus.completed;
      task.finishedAt = DateTime.now();
      task.progress = 1.0;
      if (fileName != null) task.fileName = fileName;
      _persist();
      notifyListeners();
    } catch (e) {
      // Task not found, ignore
    }
  }

  /// Mark a task as failed.
  void failTask(String id, String error) {
    try {
      final task = _tasks.firstWhere((t) => t.id == id);
      task.status = DataSyncTaskStatus.failed;
      task.finishedAt = DateTime.now();
      task.error = error;
      _persist();
      notifyListeners();
    } catch (e) {
      // Task not found, ignore
    }
  }

  /// Mark a task as canceled.
  void cancelTask(String id) {
    try {
      final task = _tasks.firstWhere((t) => t.id == id);
      task.status = DataSyncTaskStatus.canceled;
      task.finishedAt = DateTime.now();
      _persist();
      notifyListeners();
    } catch (e) {
      // Task not found, ignore
    }
  }

  /// Remove a task from history.
  void removeTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    _persist();
    notifyListeners();
  }

  /// Clear all history tasks (keep running tasks).
  void clearHistory() {
    _tasks.removeWhere((t) => !t.isRunning);
    _persist();
    notifyListeners();
  }
}
