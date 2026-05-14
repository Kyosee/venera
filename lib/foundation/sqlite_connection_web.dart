import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';

final _databases = <String, CommonDatabase>{};

WasmSqlite3? _wasmSqlite;
IndexedDbFileSystem? _indexedDbFileSystem;
int _transientVfsId = 0;

Future<void> initWebSqlite() async {
  if (_wasmSqlite != null) return;
  _wasmSqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  final fs = await IndexedDbFileSystem.open(dbName: 'venera_sqlite');
  _indexedDbFileSystem = fs;
  _wasmSqlite!.registerVirtualFileSystem(fs, makeDefault: true);
}

CommonDatabase openSqliteDatabase(String path) {
  if (_databases.containsKey(path)) {
    return _databases[path]!;
  }
  if (_wasmSqlite == null) {
    throw StateError('Web SQLite not initialized. Call initWebSqlite() first.');
  }
  final db = _wasmSqlite!.open(path);
  db.execute('PRAGMA journal_mode = DELETE;');
  db.execute('PRAGMA synchronous = NORMAL;');
  _databases[path] = db;
  return db;
}

Future<T> withDatabase<T>(
  String path,
  Future<T> Function(CommonDatabase db) fn,
) async {
  final db = openSqliteDatabase(path);
  try {
    return await fn(db);
  } finally {
    await flushSqliteDatabases();
  }
}

Uint8List exportDatabaseBytes(String path) {
  final src = openSqliteDatabase(path);
  final vfsName = _nextTransientVfsName('_exp');
  final tempVfs = InMemoryFileSystem(name: vfsName);
  _wasmSqlite!.registerVirtualFileSystem(tempVfs);
  try {
    final dst = _wasmSqlite!.open('/export.db', vfs: vfsName);
    try {
      _cloneDatabase(src, dst);
    } finally {
      dst.dispose();
    }
    final buffer = tempVfs.fileData['/export.db'];
    if (buffer == null) {
      throw StateError('Export produced no output');
    }
    return Uint8List.fromList(buffer.buffer.asUint8List(0, buffer.length));
  } finally {
    _wasmSqlite!.unregisterVirtualFileSystem(tempVfs);
  }
}

String _nextTransientVfsName(String prefix) {
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_transientVfsId++}';
}

void closeSqliteDatabase(String path) {
  final db = _databases.remove(path);
  try {
    db?.dispose();
  } catch (_) {}
}

Future<void> flushSqliteDatabases() async {
  await _indexedDbFileSystem?.flush();
}

Future<void> deleteSqliteDatabase(String path) async {
  closeSqliteDatabase(path);
  try {
    _indexedDbFileSystem?.xDelete(path, 0);
  } catch (_) {}
  await flushSqliteDatabases();
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

void _cloneDatabase(CommonDatabase src, CommonDatabase dst) {
  final tables = src.select(
    "SELECT sql FROM sqlite_master WHERE type='table' AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%'",
  );
  for (final row in tables) {
    dst.execute(row['sql'] as String);
  }
  final tableNames = src
      .select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      )
      .map((row) => row['name'] as String)
      .toList();
  for (final name in tableNames) {
    final rows = src.select('SELECT * FROM ${_quoteSqlIdentifier(name)}');
    if (rows.isEmpty) continue;
    final cols = rows.first.keys.toList();
    final placeholders = List.filled(cols.length, '?').join(',');
    final colNames = cols.map(_quoteSqlIdentifier).join(',');
    final stmt = dst.prepare(
      'INSERT INTO ${_quoteSqlIdentifier(name)} ($colNames) '
      'VALUES ($placeholders)',
    );
    try {
      for (final row in rows) {
        stmt.execute(cols.map((column) => row[column]).toList());
      }
    } finally {
      stmt.dispose();
    }
  }
  final indexes = src.select(
    "SELECT sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL",
  );
  for (final row in indexes) {
    dst.execute(row['sql'] as String);
  }
}

void rebuildDatabaseFromDump(
  String path,
  List<dynamic> tables, {
  List<dynamic> indexes = const [],
}) {
  closeSqliteDatabase(path);
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
  }
}
