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
