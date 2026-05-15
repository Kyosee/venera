import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/history.dart';
import 'package:venera/utils/data_web.dart';

void main() {
  test('extractWebDbWithHelper posts to extract-db route', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestDone = Completer<void>();

    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/sync/webdav/extract-db');
      final body = await utf8.decoder.bind(request).join();
      expect(jsonDecode(body), {'dataBase64': 'abc'});

      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'ok': true, 'databases': {}}));
      await request.response.close();
      requestDone.complete();
    });

    try {
      final dio = Dio(
        BaseOptions(baseUrl: 'http://${server.address.host}:${server.port}'),
      );
      final data = await extractWebDbWithHelper('abc', dio: dio);

      expect(data['ok'], isTrue);
      await requestDone.future.timeout(const Duration(seconds: 1));
    } finally {
      await server.close(force: true);
    }
  });

  test(
    'collectWebDbImportStatus ignores archives without db entries',
    () async {
      final zipBytes = _zipArchive({
        'appdata.json': utf8.encode('{"settings":{},"searchHistory":[]}'),
      });
      final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
      var helperCalled = false;

      final status = await collectWebDbImportStatus(
        zipBytes,
        archive,
        extractDb: (_) async {
          helperCalled = true;
          return const {};
        },
      );

      expect(status, isNull);
      expect(helperCalled, isFalse);
    },
  );

  test('collectWebDbImportStatus records extracted table summaries', () async {
    final zipBytes = _zipArchive({
      'appdata.json': utf8.encode('{"settings":{},"searchHistory":[]}'),
      'history.db': [1, 2, 3],
      'cookie.db': [4, 5, 6],
    });
    final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    String? capturedBase64;

    final status = await collectWebDbImportStatus(
      zipBytes,
      archive,
      now: DateTime.utc(2026, 5, 14),
      extractDb: (dataBase64) async {
        capturedBase64 = dataBase64;
        return {
          'ok': true,
          'databases': {
            'history.db': {
              'ok': true,
              'tables': [
                {
                  'name': 'history',
                  'columns': ['id', 'title'],
                  'rows': [
                    ['1', 'First'],
                    ['2', 'Second'],
                  ],
                },
              ],
            },
            'cookie.db': {'ok': false, 'error': 'invalid sqlite'},
          },
        };
      },
    );

    expect(capturedBase64, base64Encode(zipBytes));
    expect(status, isNotNull);
    expect(status!['state'], 'pending_merge');
    expect(status['helperOk'], isTrue);
    expect(status['createdAt'], '2026-05-14T00:00:00.000Z');

    final entries = (status['entries'] as Map).cast<String, dynamic>();
    final history = (entries['history.db'] as Map).cast<String, dynamic>();
    expect(history['extracted'], isTrue);
    expect(history['merged'], isFalse);
    expect(history['rowCount'], 2);
    expect(history['tables'], [
      {'name': 'history', 'rows': 2},
    ]);

    final cookies = (entries['cookie.db'] as Map).cast<String, dynamic>();
    expect(cookies['extracted'], isFalse);
    expect(cookies['merged'], isFalse);
    expect(cookies['error'], 'invalid sqlite');
  });

  test('collectWebDbImportStatus marks helper failures as pending', () async {
    final zipBytes = _zipArchive({
      'appdata.json': utf8.encode('{"settings":{},"searchHistory":[]}'),
      'local_favorite.db': [1],
    });
    final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);

    final status = await collectWebDbImportStatus(
      zipBytes,
      archive,
      extractDb: (_) async => throw StateError('helper offline'),
    );

    expect(status, isNotNull);
    expect(status!['helperOk'], isFalse);
    expect(status['error'].toString(), contains('helper offline'));

    final entries = (status['entries'] as Map).cast<String, dynamic>();
    final favorites = (entries['local_favorite.db'] as Map)
        .cast<String, dynamic>();
    expect(favorites['present'], isTrue);
    expect(favorites['extracted'], isFalse);
    expect(favorites['merged'], isFalse);
  });

  test('importWebServerDbDumps refreshes HistoryManager cache', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'venera-history-import-',
    );
    final previousDataPath = App.dataPath;
    final previousHistoryManager = HistoryManager.cache;
    App.dataPath = tempDir.path;
    HistoryManager.cache = null;
    addTearDown(() async {
      HistoryManager.cache?.close();
      HistoryManager.cache = previousHistoryManager;
      App.dataPath = previousDataPath;
      await tempDir.delete(recursive: true);
    });

    final manager = HistoryManager();
    await manager.init();
    expect(manager.find('demo', ComicType.local), isNull);

    final status = await importWebServerDbDumps({
      'history.db': {
        'ok': true,
        'tables': [
          {
            'name': 'history',
            'sql': '''
              create table history (
                id text,
                title text,
                subtitle text,
                cover text,
                time int,
                type int,
                ep int,
                page int,
                readEpisode text,
                max_page int,
                chapter_group int,
                primary key (id, type)
              );
            ''',
            'columns': [
              'id',
              'title',
              'subtitle',
              'cover',
              'time',
              'type',
              'ep',
              'page',
              'readEpisode',
              'max_page',
              'chapter_group',
            ],
            'rows': [
              [
                'demo',
                'Demo',
                'Sub',
                'cover',
                DateTime.utc(2026, 5, 15).millisecondsSinceEpoch,
                ComicType.local.value,
                3,
                8,
                '1,2,3',
                20,
                null,
              ],
            ],
          },
        ],
      },
    }, now: DateTime.utc(2026, 5, 15));

    final history = HistoryManager().find('demo', ComicType.local);
    expect((status!['entries'] as Map)['history.db']['merged'], isTrue);
    expect(history, isNotNull);
    expect(history!.page, 8);
    expect(history.readEpisode, {'1', '2', '3'});
  });

  test('importWebServerComicSources restores comic source files', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'venera-comic-source-',
    );
    final previousDataPath = App.dataPath;
    final previousIsInitialized = App.isInitialized;
    App.dataPath = tempDir.path;
    App.isInitialized = false;
    addTearDown(() async {
      App.dataPath = previousDataPath;
      App.isInitialized = previousIsInitialized;
      await tempDir.delete(recursive: true);
    });

    final imported = await importWebServerComicSources([
      {
        'name': 'demo.js',
        'dataBase64': base64Encode(utf8.encode('function demo() {}')),
      },
      {
        'name': 'demo.data',
        'dataBase64': base64Encode(utf8.encode('{"ok":true}')),
      },
    ]);

    expect(imported, 2);
    expect(File('${tempDir.path}/comic_source/demo.js').existsSync(), isTrue);
    expect(File('${tempDir.path}/comic_source/demo.data').existsSync(), isTrue);
    expect(
      await File('${tempDir.path}/comic_source/demo.js').readAsString(),
      'function demo() {}',
    );
    expect(
      await File('${tempDir.path}/comic_source/demo.data').readAsString(),
      '{"ok":true}',
    );
  });
}

List<int> _zipArchive(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return ZipEncoder().encode(archive);
}
