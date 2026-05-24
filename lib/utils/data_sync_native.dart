import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:venera/components/components.dart';
import 'package:venera/components/window_frame.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/foundation/res.dart';
import 'package:venera/network/app_dio_io.dart';
import 'package:venera/utils/data.dart';
import 'package:venera/utils/ext.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3_pkg;
import 'package:webdav_client/webdav_client.dart' hide File;
import 'package:venera/utils/translations.dart';

import 'io.dart';

class DataSync with ChangeNotifier {
  DataSync._() {
    if (isEnabled) {
      downloadData();
    }
    LocalFavoritesManager().addListener(onDataChanged);
    ComicSourceManager().addListener(onDataChanged);
    if (App.isDesktop) {
      Future.delayed(const Duration(seconds: 1), () {
        var controller = WindowFrame.of(App.rootContext);
        controller.addCloseListener(_handleWindowClose);
      });
    }
  }

  static String _platformTag() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'win';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static const _syncLogKey = 'sync_logs';
  static const _maxSyncLogs = 100;

  void _addSyncLog(String action, String? fileName, bool success, String? error) {
    var logs = (appdata.implicitData[_syncLogKey] as List?) ?? [];
    logs.insert(0, {
      'time': DateTime.now().millisecondsSinceEpoch,
      'action': action,
      'fileName': fileName,
      'success': success,
      'error': error,
    });
    if (logs.length > _maxSyncLogs) logs = logs.sublist(0, _maxSyncLogs);
    appdata.implicitData[_syncLogKey] = logs;
    appdata.writeImplicitData();
  }

  List<Map<String, dynamic>> get syncLogs {
    final raw = appdata.implicitData[_syncLogKey];
    if (raw is List) return raw.cast<Map<String, dynamic>>();
    return [];
  }

  void onDataChanged() {
    if (isEnabled) {
      _pendingAutoUpload?.cancel();
      _pendingAutoUpload = Timer(const Duration(seconds: 2), () {
        _pendingAutoUpload = null;
        uploadData();
      });
    }
  }

  bool _handleWindowClose() {
    if (_pendingAutoUpload?.isActive ?? false) {
      _pendingAutoUpload?.cancel();
      _pendingAutoUpload = null;
      uploadData();
    }
    if (_isUploading || _isDownloading || _haveWaitingTask) {
      _showWindowCloseDialog();
      return false;
    }
    return true;
  }

  void _showWindowCloseDialog() async {
    showLoadingDialog(
      App.rootContext,
      cancelButtonText: "Shut Down".tl,
      onCancel: () => exit(0),
      barrierDismissible: false,
      message: "Syncing Data".tl,
    );
    while (_isUploading || _isDownloading || _haveWaitingTask) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    exit(0);
  }

  static DataSync? instance;

  factory DataSync() => instance ?? (instance = DataSync._());

  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

  bool _isUploading = false;

  bool get isUploading => _isUploading;

  bool _haveWaitingTask = false;

  Timer? _pendingAutoUpload;

  String? _lastError;

  String? get lastError => _lastError;

  Future<Map<String, dynamic>?> loadWebDavConfig({bool force = false}) async {
    return null;
  }

  Future<void> saveWebDavConfig(
    List<String> config, {
    required bool autoSync,
    required String disableSyncFields,
  }) async {}

  Future<void> clearWebDavConfig() async {}

  bool get isEnabled {
    var config = appdata.settings['webdav'];
    var autoSync = appdata.implicitData['webdavAutoSync'] ?? false;
    return autoSync && config is List && config.isNotEmpty;
  }

  List<String>? _validateConfig() {
    var config = appdata.settings['webdav'];
    if (config is! List) {
      return null;
    }
    if (config.isEmpty) {
      return [];
    }
    if (config.length != 3 || config.whereType<String>().length != 3) {
      return null;
    }
    var values = config.cast<String>().map((e) => e.trim()).toList();
    if (values.any((e) => e.isEmpty)) {
      return null;
    }
    return values;
  }

  int _dataVersion() {
    final value = appdata.settings['dataVersion'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool _hasCompletedInitialSync() {
    return appdata.implicitData['hasCompletedInitialSync'] == true;
  }

  void _markInitialSyncCompleted() {
    appdata.implicitData['hasCompletedInitialSync'] = true;
    appdata.writeImplicitData();
  }

  bool _isFavoriteDbValid() {
    var favDbPath = FilePath.join(App.dataPath, 'local_favorite.db');
    var favDbFile = File(favDbPath);
    if (!favDbFile.existsSync() || favDbFile.lengthSync() == 0) {
      return false;
    }
    return true;
  }

  bool _isFollowFolderEmpty() {
    var followFolder = appdata.settings['followUpdatesFolder'];
    if (followFolder is! String || followFolder.isEmpty) {
      return false;
    }
    var favDbPath = FilePath.join(App.dataPath, 'local_favorite.db');
    if (!File(favDbPath).existsSync()) return true;
    try {
      var db = sqlite3_pkg.sqlite3.open(favDbPath);
      try {
        var tables = db
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => r['name'] as String)
            .toList();
        if (!tables.contains(followFolder)) return true;
        var escaped = followFolder.replaceAll('"', '""');
        var count = db.select(
          'SELECT COUNT(*) as c FROM "$escaped"',
        ).first['c'] as int;
        return count == 0;
      } finally {
        db.dispose();
      }
    } catch (e) {
      Log.warning("DataSync", "Follow folder check failed: $e");
      return false;
    }
  }

  Future<Res<bool>> uploadData() async {
    _pendingAutoUpload?.cancel();
    _pendingAutoUpload = null;
    if (_haveWaitingTask) return const Res(true);
    while (isDownloading || isUploading) {
      _haveWaitingTask = true;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _haveWaitingTask = false;
    _isUploading = true;
    _lastError = null;
    notifyListeners();
    try {
      if (!_hasCompletedInitialSync()) {
        _lastError = 'Please complete initial sync download first';
        _addSyncLog('upload', null, false, 'Blocked: initial sync not completed');
        return const Res.error('Initial sync not completed');
      }
      var config = _validateConfig();
      if (config == null) {
        _lastError = 'Invalid WebDAV configuration';
        return const Res.error('Invalid WebDAV configuration');
      }
      if (config.isEmpty) {
        return const Res(true);
      }
      String url = config[0];
      String user = config[1];
      String pass = config[2];

      if (!_isFavoriteDbValid()) {
        _lastError = 'Favorite database is empty, upload blocked';
        _addSyncLog('upload', null, false, 'Blocked: local_favorite.db empty');
        return const Res.error('Favorite database is empty');
      }
      if (_isFollowFolderEmpty()) {
        _lastError = 'Follow folder is empty, auto-upload blocked';
        _addSyncLog('upload', null, false, 'Blocked: follow folder empty');
        return const Res.error('Follow folder is empty');
      }

      var client = newClient(
        url,
        user: user,
        password: pass,
        adapter: RHttpAdapter(),
      );

      File? data;
      final previousVersion = _dataVersion();
      final nextVersion = previousVersion + 1;
      try {
        appdata.settings['dataVersion'] = nextVersion;
        await appdata.saveData(false);
        data = await exportAppData(
          appdata.settings['disableSyncFields'].toString().isNotEmpty,
        );
        var time = (DateTime.now().millisecondsSinceEpoch ~/ 86400000)
            .toString();
        var filename = time;
        filename += '-';
        filename += nextVersion.toString();
        filename += '.${_platformTag()}.venera';
        var files = await client.readDir('/');
        files = files.where((e) => e.name!.endsWith('.venera')).toList();
        var old = files.firstWhereOrNull((e) => e.name!.startsWith("$time-"));
        if (old != null) {
          await client.remove(old.name!);
        }
        if (files.length >= 10) {
          files.sort((a, b) => a.name!.compareTo(b.name!));
          await client.remove(files.first.name!);
        }
        await client.write(filename, await data.readAsBytes());
        data.deleteIgnoreError();
        Log.info("Upload Data", "Data uploaded successfully");
        _addSyncLog('upload', filename, true, null);
        return const Res(true);
      } catch (e, s) {
        appdata.settings['dataVersion'] = previousVersion;
        await appdata.saveData(false);
        Log.error("Upload Data", e, s);
        _lastError = e.toString();
        _addSyncLog('upload', null, false, e.toString());
        return Res.error(e.toString());
      } finally {
        data?.deleteIgnoreError();
      }
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  Future<Res<bool>> downloadData() async {
    if (_haveWaitingTask) return const Res(true);
    while (isDownloading || isUploading) {
      _haveWaitingTask = true;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _haveWaitingTask = false;
    _isDownloading = true;
    _lastError = null;
    notifyListeners();
    try {
      var config = _validateConfig();
      if (config == null) {
        _lastError = 'Invalid WebDAV configuration';
        return const Res.error('Invalid WebDAV configuration');
      }
      if (config.isEmpty) {
        return const Res(true);
      }
      String url = config[0];
      String user = config[1];
      String pass = config[2];

      var client = newClient(
        url,
        user: user,
        password: pass,
        adapter: RHttpAdapter(),
      );

      try {
        var files = await client.readDir('/');
        files.sort((a, b) => b.name!.compareTo(a.name!));
        var file = files.firstWhereOrNull((e) => e.name!.endsWith('.venera'));
        if (file == null) {
          throw 'No data file found';
        }
        var version = file.name!
            .split('-')
            .elementAtOrNull(1)
            ?.split('.')
            .first;
        if (version != null && int.tryParse(version) != null) {
          var currentVersion = _dataVersion();
          if (int.parse(version) <= currentVersion) {
            Log.info("Data Sync", 'No new data to download');
            return const Res(true);
          }
        }
        Log.info("Data Sync", "Downloading data from WebDAV server");
        var localFile = File(FilePath.join(App.cachePath, file.name!));
        try {
          await client.read2File(file.name!, localFile.path);
          await importAppData(localFile, true);
        } finally {
          localFile.deleteIgnoreError();
        }
        Log.info("Data Sync", "Data downloaded successfully");
        _addSyncLog('download', null, true, null);
        if (!_hasCompletedInitialSync()) {
          _markInitialSyncCompleted();
        }
        return const Res(true);
      } catch (e, s) {
        Log.error("Data Sync", e, s);
        _lastError = e.toString();
        _addSyncLog('download', null, false, e.toString());
        return Res.error(e.toString());
      }
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }
}
