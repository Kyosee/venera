import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/foundation/sqlite_connection.dart';

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      open.overrideFor(
        OperatingSystem.windows,
        () => DynamicLibrary.open('winsqlite3.dll'),
      );
    }
  });

  Directory tempDir() {
    final dir = Directory.systemTemp.createTempSync('venera_restore_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    return dir;
  }

  test('restoreDatabaseFiles swaps file content and drops stale sidecars',
      () async {
    final dir = tempDir();
    final targetPath = '${dir.path}${Platform.pathSeparator}target.db';
    final sourcePath = '${dir.path}${Platform.pathSeparator}source.db';

    final target = openSqliteDatabase(targetPath);
    target.execute('CREATE TABLE old_table (id INTEGER PRIMARY KEY, v TEXT);');
    target.execute("INSERT INTO old_table VALUES (1, 'old');");
    target.dispose();
    // Leftover sidecars from an unclean shutdown must not survive the swap:
    // a fresh open would try to recover them against the NEW main file.
    File('$targetPath-wal').writeAsBytesSync([1, 2, 3]);
    File('$targetPath-shm').writeAsBytesSync([4, 5, 6]);

    final source = sqlite3.open(sourcePath);
    source.execute('CREATE TABLE new_table (id TEXT PRIMARY KEY, n INT);');
    source.execute("INSERT INTO new_table VALUES ('a', 42);");
    source.dispose();

    restoreDatabaseFiles({targetPath: sourcePath});

    expect(File('$targetPath-wal').existsSync(), isFalse);
    expect(File('$targetPath-shm').existsSync(), isFalse);

    final reopened = openSqliteDatabase(targetPath);
    addTearDown(reopened.dispose);
    final tables = reopened
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'])
        .toList();
    expect(tables, contains('new_table'));
    expect(tables, isNot(contains('old_table')));
    expect(reopened.select('SELECT n FROM new_table').first['n'], 42);

    // The reopened connection stays writable.
    reopened.execute("INSERT INTO new_table VALUES ('b', 7);");
    expect(reopened.select('SELECT count(*) c FROM new_table').first['c'], 2);
  });

  test('restores a source whose page size differs from the target', () async {
    // The old in-place online backup threw SQLITE_READONLY when the page size
    // differed and the destination was in WAL mode (the WebDAV "reinstall then
    // sync" failure). A file-level swap is immune; keep the case covered.
    final dir = tempDir();
    final targetPath = '${dir.path}${Platform.pathSeparator}target.db';
    final sourcePath = '${dir.path}${Platform.pathSeparator}source.db';

    final target = openSqliteDatabase(targetPath);
    expect(target.select('PRAGMA page_size;').first.values.first, 4096);
    target.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);');
    target.execute("INSERT INTO t VALUES (1, 'old');");
    target.dispose();

    final source = sqlite3.open(sourcePath);
    source.execute('PRAGMA page_size = 1024;');
    source.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);');
    source.execute("INSERT INTO t VALUES (1, 'new');");
    source.dispose();

    restoreDatabaseFiles({targetPath: sourcePath});

    final reopened = openSqliteDatabase(targetPath);
    addTearDown(reopened.dispose);
    expect(reopened.select('SELECT v FROM t').first['v'], 'new');
    reopened.execute("INSERT INTO t VALUES (2, 'more');");
    expect(reopened.select('SELECT count(*) c FROM t').first['c'], 2);
  });

  test('rejects a source that is not a database and keeps the target intact',
      () async {
    final dir = tempDir();
    final targetPath = '${dir.path}${Platform.pathSeparator}target.db';
    final sourcePath = '${dir.path}${Platform.pathSeparator}bad.db';

    final target = openSqliteDatabase(targetPath);
    target.execute('CREATE TABLE t (v TEXT);');
    target.execute("INSERT INTO t VALUES ('keep');");
    target.dispose();

    File(sourcePath).writeAsStringSync('this is not a sqlite database');

    expect(
      () => restoreDatabaseFiles({targetPath: sourcePath}),
      throwsA(isA<SqliteException>()),
    );

    final reopened = openSqliteDatabase(targetPath);
    addTearDown(reopened.dispose);
    expect(reopened.select('SELECT v FROM t').first['v'], 'keep');
  });

  test('aborts before touching any target when a source file is missing',
      () async {
    final dir = tempDir();
    final sep = Platform.pathSeparator;
    final targetA = '${dir.path}${sep}a.db';
    final targetB = '${dir.path}${sep}b.db';
    final sourceA = '${dir.path}${sep}src_a.db';
    final missingSourceB = '${dir.path}${sep}does_not_exist.db';

    for (final entry in {targetA: 'old_a', targetB: 'old_b'}.entries) {
      final db = openSqliteDatabase(entry.key);
      db.execute('CREATE TABLE t (v TEXT);');
      db.execute("INSERT INTO t VALUES ('${entry.value}');");
      db.dispose();
    }
    final srcA = sqlite3.open(sourceA);
    srcA.execute('CREATE TABLE t (v TEXT);');
    srcA.execute("INSERT INTO t VALUES ('new_a');");
    srcA.dispose();

    expect(
      () => restoreDatabaseFiles({targetA: sourceA, targetB: missingSourceB}),
      throwsA(anything),
    );

    // Neither target changed — the batch is all-or-nothing.
    for (final entry in {targetA: 'old_a', targetB: 'old_b'}.entries) {
      final db = openSqliteDatabase(entry.key);
      expect(db.select('SELECT v FROM t').first['v'], entry.value);
      db.dispose();
    }
  });

  test('rolls back a completed swap when a later swap fails', () async {
    final dir = tempDir();
    final sep = Platform.pathSeparator;
    final targetA = '${dir.path}${sep}a.db';
    final targetB = '${dir.path}${sep}b.db';
    final sourceA = '${dir.path}${sep}src_a.db';
    final sourceB = '${dir.path}${sep}src_b.db';

    for (final entry in {
      targetA: 'old_a',
      targetB: 'old_b',
      sourceA: 'new_a',
      sourceB: 'new_b',
    }.entries) {
      final db = openSqliteDatabase(entry.key);
      db.execute('CREATE TABLE t (v TEXT);');
      db.execute("INSERT INTO t VALUES ('${entry.value}');");
      db.dispose();
    }
    // Block target B's set-aside rename by squatting on the aside path with a
    // directory: sources validate and stage fine, target A swaps, then the
    // swap phase fails on B — the rollback path with one completed swap.
    Directory('$targetB.restore-aside').createSync();

    expect(
      () => restoreDatabaseFiles({targetA: sourceA, targetB: sourceB}),
      throwsA(anything),
    );

    // A's completed swap was rolled back; B was never modified.
    for (final entry in {targetA: 'old_a', targetB: 'old_b'}.entries) {
      final db = openSqliteDatabase(entry.key);
      expect(db.select('SELECT v FROM t').first['v'], entry.value);
      db.dispose();
    }
    // No staged copies were left behind.
    expect(File('$targetA.restore-incoming').existsSync(), isFalse);
    expect(File('$targetB.restore-incoming').existsSync(), isFalse);
  });

  test('a staging failure leaves every original untouched', () async {
    final dir = tempDir();
    final sep = Platform.pathSeparator;
    final targetA = '${dir.path}${sep}a.db';
    // Target B lives in a directory that does not exist, so staging its copy
    // fails after A's copy was already staged — before ANY original is touched.
    final targetB = '${dir.path}${sep}no_such_dir${sep}b.db';
    final sourceA = '${dir.path}${sep}src_a.db';
    final sourceB = '${dir.path}${sep}src_b.db';

    for (final entry in {
      targetA: 'old_a',
      sourceA: 'new_a',
      sourceB: 'new_b',
    }.entries) {
      final db = openSqliteDatabase(entry.key);
      db.execute('CREATE TABLE t (v TEXT);');
      db.execute("INSERT INTO t VALUES ('${entry.value}');");
      db.dispose();
    }

    expect(
      () => restoreDatabaseFiles({targetA: sourceA, targetB: sourceB}),
      throwsA(anything),
    );

    final db = openSqliteDatabase(targetA);
    expect(db.select('SELECT v FROM t').first['v'], 'old_a');
    db.dispose();
    expect(File('$targetA.restore-incoming').existsSync(), isFalse);
  });

  test('runExclusive drains in-flight reads and blocks new ones', () async {
    final gateway = DatabaseGateway.instance;

    // A reader already dispatched before the exclusive window opens.
    var inFlightDone = false;
    final inFlight = gateway.guardedRead(() async {
      await Future.delayed(const Duration(milliseconds: 60));
      inFlightDone = true;
    });

    var duringRan = false;
    Future<void>? during;
    final exclusive = gateway.runExclusive(() async {
      // The window must not open until the in-flight read finished.
      expect(inFlightDone, isTrue,
          reason: 'exclusive window opened before draining in-flight reads');
      // A read requested during the window is held off, not run.
      during = gateway.guardedRead(() async => duringRan = true);
      await Future.delayed(const Duration(milliseconds: 40));
      expect(duringRan, isFalse,
          reason: 'read ran while the exclusive window held the DB');
    });

    await exclusive;
    await inFlight;
    await during;
    expect(duringRan, isTrue);
  });

  test('two guarded reads never overlap (serialized)', () async {
    final gateway = DatabaseGateway.instance;
    // Drain any state left by earlier tests.
    await gateway.guardedRead(() async {});

    var active = 0;
    var maxConcurrent = 0;
    Future<void> read() => gateway.guardedRead(() async {
          active++;
          maxConcurrent = maxConcurrent > active ? maxConcurrent : active;
          await Future.delayed(const Duration(milliseconds: 20));
          active--;
        });

    // Fire several at once, as startup does (favorites hash, history load,
    // image-favorites stats). Each opens its own sqlite handle in an isolate;
    // on iOS concurrent opens corrupt the shared C-heap, so they must run one
    // at a time.
    await Future.wait([read(), read(), read(), read()]);
    expect(maxConcurrent, 1,
        reason: 'guarded reads ran concurrently — the crash race is back');
  });

  test('a failing op does not wedge the chain', () async {
    final gateway = DatabaseGateway.instance;
    await expectLater(
      gateway.guardedRead(() async => throw StateError('boom')),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      gateway.runExclusive(() async => throw StateError('boom')),
      throwsA(isA<StateError>()),
    );
    // The next op must still run.
    var ran = false;
    await gateway.guardedRead(() async => ran = true);
    expect(ran, isTrue);
  });
}
