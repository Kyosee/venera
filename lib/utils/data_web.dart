import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/domain_database.dart';
import 'package:venera/foundation/favorites.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/foundation/sqlite_connection.dart';
import 'package:venera/network/cookie_jar.dart';

import 'io.dart';

const webPendingDbImportKey = 'webPwaPendingDbImport';
const _webDbEntries = [
  'data/venera.db',
  'history.db',
  'local_favorite.db',
  'cookie.db',
];

typedef WebDbExtractClient =
    Future<Map<String, dynamic>> Function(String dataBase64);

Future<File> exportAppData([bool sync = true]) async {
  final file = File(
    FilePath.join(
      App.cachePath,
      '${DateTime.now().millisecondsSinceEpoch}.venera',
    ),
  );
  final archive = Archive();

  void addArchiveFile(String name, List<int> bytes) {
    final copied = bytes.toList(growable: false);
    archive.addFile(ArchiveFile(name, copied.length, copied));
  }

  try {
    await flushSqliteDatabases();
  } catch (e, s) {
    Log.warning('Export Data', 'Failed to flush web sqlite: $e\n$s');
  }

  final databaseEntries = {
    'history.db': FilePath.join(App.dataPath, 'history.db'),
    'local_favorite.db': FilePath.join(App.dataPath, 'local_favorite.db'),
    'data/venera.db': DomainDatabase.databasePathFor(App.dataPath),
    'cookie.db': FilePath.join(App.dataPath, 'cookie.db'),
  };
  for (final entry in databaseEntries.entries) {
    try {
      addArchiveFile(entry.key, exportDatabaseBytes(entry.value));
    } catch (e, s) {
      Log.warning('Export Data', 'Failed to export ${entry.key}: $e\n$s');
    }
  }

  final data = jsonDecode(jsonEncode(appdata.toJson())) as Map<String, dynamic>;
  if (sync) {
    final settings = data['settings'];
    if (settings is Map) {
      final disabledFields = appdata.splitField(
        appdata.settings['disableSyncFields'] as String,
      );
      for (final field in disabledFields) {
        settings.remove(field);
      }
    }
  }
  final bytes = utf8.encode(jsonEncode(data));
  addArchiveFile('appdata.json', bytes);

  final comicSourceDir = Directory(FilePath.join(App.dataPath, 'comic_source'));
  if (comicSourceDir.existsSync()) {
    for (final entity in comicSourceDir.listSync()) {
      if (entity is! File) {
        continue;
      }
      final name = entity.name;
      if (!name.endsWith('.js') && !name.endsWith('.data')) {
        continue;
      }
      try {
        addArchiveFile('comic_source/$name', await entity.readAsBytes());
      } catch (e, s) {
        Log.warning(
          'Export Data',
          'Failed to export comic source $name: $e\n$s',
        );
      }
    }
  }

  await file.writeAsBytes(ZipEncoder().encode(archive));
  return file;
}

Future<void> importAppData(File file, [bool checkVersion = false]) async {
  final zipBytes = await file.readAsBytes();
  final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
  final appdataEntry = archive.findFile('appdata.json');
  if (appdataEntry == null) {
    throw const FormatException('Missing appdata.json in backup');
  }
  final bytes = appdataEntry.readBytes();
  if (bytes == null) {
    throw const FormatException('Invalid appdata.json in backup');
  }
  final data = jsonDecode(utf8.decode(bytes));
  if (data is! Map) {
    throw const FormatException('Invalid appdata.json in backup');
  }
  final appDataJson = Map<String, dynamic>.from(data);
  if (checkVersion) {
    final settings = appDataJson['settings'];
    final version = settings is Map ? settings['dataVersion'] : null;
    final currentVersion = appdata.settings['dataVersion'];
    if (version is int &&
        currentVersion is num &&
        version <= currentVersion.toInt()) {
      return;
    }
  }
  final dbImportStatus = await importWebDbEntries(zipBytes, archive);
  appdata.syncData(appDataJson);
  if (dbImportStatus != null) {
    if (dbImportStatus['state'] == 'merged') {
      appdata.implicitData.remove(webPendingDbImportKey);
    } else {
      appdata.implicitData[webPendingDbImportKey] = dbImportStatus;
      Log.warning(
        'Import Data',
        'Imported appdata.json; sqlite DB entries are not fully merged: '
            '${(dbImportStatus['entries'] as Map).keys.join(', ')}',
      );
    }
    appdata.writeImplicitData();
  }
  await _importComicSources(archive);
  try {
    await flushSqliteDatabases();
  } catch (e, s) {
    Log.warning('Import Data', 'Failed to flush web sqlite: $e\n$s');
  }
}

Future<void> importPicaData(File file) async {
  throw UnsupportedError('Pica data import is not supported on web.');
}

@visibleForTesting
Future<Map<String, dynamic>> extractWebDbWithHelper(
  String dataBase64, {
  Dio? dio,
}) async {
  final client =
      dio ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      );
  final response = await client.post(
    '/sync/webdav/extract-db',
    data: {'dataBase64': dataBase64},
    options: Options(extra: const {'maskDataInLog': true}),
  );
  final data = response.data;
  if (data is Map) {
    return data.cast<String, dynamic>();
  }
  throw StateError('Unexpected helper response');
}

@visibleForTesting
Future<Map<String, dynamic>?> collectWebDbImportStatus(
  List<int> zipBytes,
  Archive archive, {
  WebDbExtractClient? extractDb,
  DateTime? now,
}) async {
  final presentEntries = _webDbEntries
      .where((entry) => archive.findFile(entry) != null)
      .toList();
  if (presentEntries.isEmpty) {
    return null;
  }

  final status = <String, dynamic>{
    'version': 1,
    'state': 'pending_merge',
    'createdAt': (now ?? DateTime.now()).toIso8601String(),
    'reason': 'Web import restored appdata only; sqlite DB merge is pending.',
    'entries': {
      for (final entry in presentEntries)
        entry: {'present': true, 'extracted': false, 'merged': false},
    },
  };

  try {
    final helperData = await (extractDb ?? extractWebDbWithHelper)(
      base64Encode(zipBytes),
    );
    final databases = helperData['databases'];
    if (databases is! Map) {
      throw StateError('Unexpected extract-db response');
    }
    status['helperOk'] = true;
    status['entries'] = _summarizeExtractedDatabases(presentEntries, databases);
  } catch (e, s) {
    status['helperOk'] = false;
    status['error'] = e.toString();
    Log.warning(
      'Import Data',
      'Failed to extract sqlite data via helper: $e\n$s',
    );
  }

  return status;
}

@visibleForTesting
Future<Map<String, dynamic>?> importWebDbEntries(
  List<int> zipBytes,
  Archive archive, {
  WebDbExtractClient? extractDb,
  DateTime? now,
}) async {
  final presentEntries = _webDbEntries
      .where((entry) => archive.findFile(entry) != null)
      .toList();
  if (presentEntries.isEmpty) {
    return null;
  }

  final status = <String, dynamic>{
    'version': 1,
    'state': 'pending_merge',
    'createdAt': (now ?? DateTime.now()).toIso8601String(),
    'entries': {
      for (final entry in presentEntries)
        entry: {'present': true, 'extracted': false, 'merged': false},
    },
  };

  try {
    final helperData = await (extractDb ?? extractWebDbWithHelper)(
      base64Encode(zipBytes),
    );
    final databases = helperData['databases'];
    if (databases is! Map) {
      throw StateError('Unexpected extract-db response');
    }
    status['helperOk'] = true;
    status['entries'] = await _importExtractedDatabases(
      presentEntries,
      databases,
    );
    final entries = (status['entries'] as Map).values.whereType<Map>();
    status['state'] = entries.every((entry) => entry['merged'] == true)
        ? 'merged'
        : 'partial_merge';
  } catch (e, s) {
    status['helperOk'] = false;
    status['error'] = e.toString();
    Log.warning(
      'Import Data',
      'Failed to import sqlite data via helper: $e\n$s',
    );
  }

  return status;
}

Future<Map<String, dynamic>> _importExtractedDatabases(
  List<String> presentEntries,
  Map<dynamic, dynamic> databases,
) async {
  final result = _summarizeExtractedDatabases(presentEntries, databases);
  for (final entryName in presentEntries) {
    final entryStatus = (result[entryName] as Map).cast<String, dynamic>();
    final rawDatabase = databases[entryName];
    if (rawDatabase is! Map || rawDatabase['ok'] != true) {
      continue;
    }
    final database = rawDatabase.cast<String, dynamic>();
    final tables = database['tables'];
    if (tables is! List) {
      entryStatus['error'] = 'Missing table dump';
      continue;
    }
    try {
      await _closeWebDatabase(entryName);
      rebuildDatabaseFromDump(
        _webDatabaseTargetPath(entryName),
        tables,
        indexes: database['indexes'] is List
            ? database['indexes'] as List
            : const [],
      );
      await _initWebDatabase(entryName);
      entryStatus['merged'] = true;
    } catch (e, s) {
      entryStatus['merged'] = false;
      entryStatus['error'] = e.toString();
      Log.warning('Import Data', 'Failed to import $entryName: $e\n$s');
      try {
        await _initWebDatabase(entryName);
      } catch (_) {}
    }
  }
  return result;
}

String _webDatabaseTargetPath(String entryName) {
  return switch (entryName) {
    'data/venera.db' => DomainDatabase.databasePathFor(App.dataPath),
    'history.db' => FilePath.join(App.dataPath, 'history.db'),
    'local_favorite.db' => FilePath.join(App.dataPath, 'local_favorite.db'),
    'cookie.db' => FilePath.join(App.dataPath, 'cookie.db'),
    _ => throw ArgumentError('Unsupported web database entry: $entryName'),
  };
}

Future<void> _closeWebDatabase(String entryName) async {
  switch (entryName) {
    case 'data/venera.db':
      App.domain.close();
      Directory(
        FilePath.join(App.dataPath, DomainDatabase.dataDirectoryName),
      ).createSync(recursive: true);
      break;
    case 'history.db':
      HistoryManager().close();
      break;
    case 'local_favorite.db':
      try {
        LocalFavoritesManager().close();
      } catch (_) {}
      break;
    case 'cookie.db':
      SingleInstanceCookieJar.instance?.dispose();
      SingleInstanceCookieJar.instance = null;
      break;
  }
}

Future<void> _initWebDatabase(String entryName) async {
  switch (entryName) {
    case 'data/venera.db':
      await App.domain.init(App.dataPath);
      break;
    case 'history.db':
      await HistoryManager().init();
      break;
    case 'local_favorite.db':
      await LocalFavoritesManager().init();
      LocalFavoritesManager().notifyChanges();
      break;
    case 'cookie.db':
      SingleInstanceCookieJar.instance = SingleInstanceCookieJar(
        FilePath.join(App.dataPath, 'cookie.db'),
      )..init();
      break;
  }
}

Future<void> _importComicSources(Archive archive) async {
  final entries = archive
      .where((entry) => entry.isFile && entry.name.startsWith('comic_source/'))
      .toList();
  if (entries.isEmpty) {
    return;
  }
  final targetDir = Directory(FilePath.join(App.dataPath, 'comic_source'));
  if (targetDir.existsSync()) {
    targetDir.deleteSync(recursive: true);
  }
  targetDir.createSync(recursive: true);
  for (final entry in entries) {
    final name = entry.name.replaceFirst('comic_source/', '');
    if (name.isEmpty || (!name.endsWith('.js') && !name.endsWith('.data'))) {
      continue;
    }
    final bytes = entry.readBytes();
    if (bytes == null) {
      continue;
    }
    await File(FilePath.join(targetDir.path, name)).writeAsBytes(bytes);
  }
  await ComicSourceManager().reload();
}

Map<String, dynamic> _summarizeExtractedDatabases(
  List<String> presentEntries,
  Map<dynamic, dynamic> databases,
) {
  final result = <String, dynamic>{};
  for (final entryName in presentEntries) {
    final rawDatabase = databases[entryName];
    if (rawDatabase is! Map) {
      result[entryName] = {
        'present': true,
        'extracted': false,
        'merged': false,
        'error': 'Missing helper result',
      };
      continue;
    }

    final database = rawDatabase.cast<String, dynamic>();
    final tableSummaries = <Map<String, dynamic>>[];
    var rowCount = 0;
    final tables = database['tables'];
    if (tables is List) {
      for (final rawTable in tables) {
        if (rawTable is! Map) {
          continue;
        }
        final table = rawTable.cast<String, dynamic>();
        final rows = table['rows'];
        final rowsCount = rows is List ? rows.length : 0;
        rowCount += rowsCount;
        tableSummaries.add({
          'name': table['name']?.toString() ?? '',
          'rows': rowsCount,
        });
      }
    }

    result[entryName] = {
      'present': true,
      'extracted': database['ok'] == true,
      'merged': false,
      if (database['error'] != null) 'error': database['error'].toString(),
      'tables': tableSummaries,
      'rowCount': rowCount,
    };
  }
  return result;
}
