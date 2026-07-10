import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

Database openSqliteDatabase(String path) {
  final db = sqlite3.open(path);
  db.execute('PRAGMA foreign_keys = ON;');
  db.execute('PRAGMA journal_mode = WAL;');
  db.execute('PRAGMA wal_autocheckpoint = 200;');
  db.execute('PRAGMA synchronous = NORMAL;');
  db.execute('PRAGMA busy_timeout = 5000;');
  return db;
}

void closeSqliteDatabase(String path) {}

/// Single owner of database access ordering for this process.
///
/// Two distinct hazards share one root cause — several native `sqlite3` handles
/// bound to the same file share one process C-heap and one `-wal`/`-shm` memory
/// mapping:
///
///  1. Concurrent background reads. Startup fires several isolate reads at once
///     (favorites hash, async history/folder load, image-favorites stats); each
///     opens its own handle in a fresh `Isolate.run`. On iOS, overlapping
///     opens/steps/`dispose`s corrupt the shared heap — an `abort()` in
///     libmalloc ("pointer being freed was not allocated") ~1s into launch.
///
///  2. A restore that swaps a database file out from under a live reader.
///
/// Both are removed by routing every access through one serial chain. Reads
/// dispatch through [guardedRead] (so no two isolate opens overlap); a restore
/// runs through [runExclusive], which drains every in-flight read and blocks
/// new ones for the whole close→replace→reopen sequence, guaranteeing no handle
/// is open against a file while it is being replaced. Single-threaded Dart
/// makes the enqueue transitions atomic, so nothing slips past once queued.
class DatabaseGateway {
  DatabaseGateway._();

  static final DatabaseGateway instance = DatabaseGateway._();

  /// Tail of the serialized-access chain. Every [guardedRead] and every
  /// [runExclusive] window appends its critical section here, so at most one of
  /// them touches the shared DB files at a time.
  Future<void> _tail = Future.value();

  /// Runs [read] (typically an `Isolate.run` opening one of the shared DB
  /// files) once every earlier queued op — reads and restores alike — has
  /// finished. Serialized, so no two isolate DB ops overlap.
  Future<T> guardedRead<T>(Future<T> Function() read) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return previous.then((_) => read()).whenComplete(done.complete);
  }

  /// Runs [body] with exclusive access to every database: waits for all
  /// in-flight [guardedRead]s to drain, then blocks new ones until [body]
  /// completes. Restores use this to close all connections, replace the files
  /// on disk, and reopen — with no other handle alive at the swap point.
  Future<T> runExclusive<T>(Future<T> Function() body) async {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    await previous;
    try {
      return await body();
    } finally {
      gate.complete();
    }
  }
}

/// Replaces each target database file (key) with its source file (value) by
/// plain file copy, discarding stale `-wal`/`-shm` sidecars. All-or-nothing.
///
/// The caller MUST have closed every connection to the targets first (restores
/// run inside [DatabaseGateway.runExclusive], which additionally blocks the
/// background-isolate readers). Because no SQLite handle is open during the
/// swap, there is no live memory mapping to dangle and no online-backup step to
/// churn sidecars — the native heap corruption and the Windows FILE_SHARE_DELETE
/// error that plagued the old in-place approach cannot occur. The copied files
/// may carry an older (or foreign) schema, so re-running migrations and
/// rebuilding in-memory caches after reopening is the caller's job.
///
/// Every source is validated as a readable SQLite database before anything is
/// touched, and the originals are set aside and restored if any step fails, so
/// a truncated backup entry or a mid-way error can never leave a half-restored
/// data directory.
void restoreDatabaseFiles(Map<String, String> swaps) {
  for (final sourcePath in swaps.values) {
    final db = sqlite3.open(sourcePath, mode: OpenMode.readOnly);
    try {
      db.select('PRAGMA schema_version;');
    } finally {
      db.dispose();
    }
  }
  const suffixes = ['', '-wal', '-shm'];
  // Stage phase: copy every source next to its target BEFORE any original is
  // touched. The vulnerable window per target during the swap phase below is
  // then two directory-entry renames, not a multi-megabyte copy — a process
  // death mid-restore can leave the old or the new file in place, never
  // neither.
  final staged = <String, String>{};
  final setAside = <String, String>{};
  // Targets whose staged copy was renamed into place; rollback may only delete
  // these — a target the swap never reached still holds its ORIGINAL file.
  final swappedIn = <String>[];
  try {
    for (final entry in swaps.entries) {
      final stagedPath = '${entry.key}.restore-incoming';
      final stagedFile = File(stagedPath);
      if (stagedFile.existsSync()) {
        stagedFile.deleteSync();
      }
      File(entry.value).copySync(stagedPath);
      staged[entry.key] = stagedPath;
    }
    // Swap phase: set the originals aside, move the staged copies into place.
    for (final entry in swaps.entries) {
      final targetPath = entry.key;
      for (final suffix in suffixes) {
        final file = File('$targetPath$suffix');
        if (!file.existsSync()) continue;
        final asidePath = '$targetPath$suffix.restore-aside';
        final aside = File(asidePath);
        if (aside.existsSync()) {
          aside.deleteSync();
        }
        file.renameSync(asidePath);
        setAside['$targetPath$suffix'] = asidePath;
      }
      File(staged.remove(targetPath)!).renameSync(targetPath);
      swappedIn.add(targetPath);
    }
  } catch (e) {
    // Roll back: remove only the files this run put in place, then restore the
    // set-aside originals. Never delete a path that was not swapped — for an
    // entry the failure preceded, the file at the target path IS the original.
    for (final targetPath in swappedIn) {
      try {
        final current = File(targetPath);
        if (current.existsSync()) {
          current.deleteSync();
        }
      } catch (_) {}
    }
    for (final entry in setAside.entries) {
      try {
        if (!File(entry.key).existsSync()) {
          File(entry.value).renameSync(entry.key);
        }
      } catch (_) {}
    }
    rethrow;
  } finally {
    for (final stagedPath in staged.values) {
      try {
        final file = File(stagedPath);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
    }
  }
  for (final asidePath in setAside.values) {
    try {
      File(asidePath).deleteSync();
    } catch (_) {}
  }
}

/// Renames a database and its WAL sidecars aside (`.invalid-<timestamp>`) so a
/// fresh one can be created at [path]. For open failures that survive restarts
/// (e.g. a crash left sidecars the next open cannot recover) — trades that
/// store's content for a working app instead of failing every launch.
void backupAsideCorruptDatabase(String path) {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  for (final suffix in ['', '-wal', '-shm']) {
    final file = File('$path$suffix');
    if (!file.existsSync()) continue;
    var backupPath = '$path$suffix.invalid-$timestamp';
    var index = 1;
    while (File(backupPath).existsSync()) {
      backupPath = '$path$suffix.invalid-$timestamp-$index';
      index++;
    }
    try {
      file.renameSync(backupPath);
    } catch (_) {
      // Rename can fail if another handle still pins the file (Windows); the
      // caller's reopen will then surface the original error.
    }
  }
}

Future<void> flushSqliteDatabases() async {}

Future<void> deleteSqliteDatabase(String path) async {
  for (final suffix in ['', '-wal', '-shm']) {
    final file = File('$path$suffix');
    if (await file.exists()) {
      await file.delete();
    }
  }
}

Future<T> withDatabase<T>(
  String path,
  Future<T> Function(Database db) fn,
) async {
  final db = openSqliteDatabase(path);
  try {
    return await fn(db);
  } finally {
    db.dispose();
  }
}

Uint8List exportDatabaseBytes(String path) {
  final db = openSqliteDatabase(path);
  try {
    db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
  } finally {
    db.dispose();
  }
  return File(path).readAsBytesSync();
}

void rebuildDatabaseFromBytes(String path, Uint8List bytes) {
  for (final suffix in ['', '-wal', '-shm']) {
    final file = File('$path$suffix');
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes, flush: true);
}

String _quoteSqlIdentifier(String value) {
  return '"${value.replaceAll('"', '""')}"';
}

Object? _decodeDumpValue(Object? value) {
  if (value is Map) {
    final map = value.cast<String, dynamic>();
    if (map.containsKey(r'$blob')) {
      return base64Decode(map[r'$blob']?.toString() ?? '');
    }
    if (map.containsKey(r'$bigint')) {
      return int.tryParse(map[r'$bigint']?.toString() ?? '');
    }
  }
  return value;
}

void rebuildDatabaseFromDump(
  String path,
  List<dynamic> tables, {
  List<dynamic> indexes = const [],
}) {
  final db = openSqliteDatabase(path);
  db.execute('PRAGMA foreign_keys = OFF;');
  db.execute('BEGIN IMMEDIATE;');
  try {
    final existingTables = db
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((row) => row['name']?.toString())
        .whereType<String>()
        .where((name) => !name.toLowerCase().startsWith('sqlite_'))
        .toList();
    for (final table in existingTables) {
      db.execute('DROP TABLE IF EXISTS ${_quoteSqlIdentifier(table)}');
    }

    for (final table in tables) {
      if (table is! Map) {
        throw FormatException('Invalid sqlite dump table entry: $table');
      }
      final sql = table['sql']?.toString();
      if (sql == null || sql.trim().isEmpty) {
        throw const FormatException('Missing sqlite dump table schema');
      }
      db.execute(sql);
    }

    for (final table in tables) {
      if (table is! Map) continue;
      final name = table['name']?.toString();
      if (name == null || name.isEmpty) {
        throw const FormatException('Missing sqlite dump table name');
      }
      final rows = table['rows'];
      if (rows is! List || rows.isEmpty) continue;
      final columns = table['columns'] is List
          ? (table['columns'] as List).map((e) => e.toString()).toList()
          : const <String>[];
      for (final row in rows) {
        if (row is! List) {
          throw FormatException('Invalid sqlite dump row for $name');
        }
        final placeholders = List.filled(row.length, '?').join(',');
        final columnSql = columns.length == row.length
            ? ' (${columns.map(_quoteSqlIdentifier).join(',')})'
            : '';
        final stmt = db.prepare(
          'INSERT INTO ${_quoteSqlIdentifier(name)}$columnSql '
          'VALUES ($placeholders)',
        );
        try {
          stmt.execute(row.map(_decodeDumpValue).toList());
        } finally {
          stmt.dispose();
        }
      }
    }

    for (final index in indexes) {
      final sql = index?.toString() ?? '';
      if (sql.trim().isNotEmpty) {
        db.execute(sql);
      }
    }

    db.execute('COMMIT;');
  } catch (_) {
    try {
      db.execute('ROLLBACK;');
    } catch (_) {}
    rethrow;
  } finally {
    db.execute('PRAGMA foreign_keys = ON;');
    db.dispose();
  }
}
