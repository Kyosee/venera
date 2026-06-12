import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites_meta.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/foundation/sqlite_connection.dart';

/// A single "Read Later" entry. Implements [Comic] so it can be rendered with
/// the same comic tiles/grids as everything else.
class ReadLaterItem implements Comic {
  @override
  final String id;

  @override
  final String title;

  @override
  final String? subtitle;

  @override
  final String cover;

  final ComicType type;

  @override
  final List<String> tags;

  /// Time the item was added (used for ordering, most recent first).
  final DateTime time;

  const ReadLaterItem({
    required this.id,
    required this.title,
    this.subtitle,
    required this.cover,
    required this.type,
    this.tags = const [],
    required this.time,
  });

  ReadLaterItem.fromRow(Row row)
      : id = row["id"] as String,
        title = (row["title"] as String?) ?? "",
        subtitle = row["subtitle"] as String?,
        cover = (row["cover"] as String?) ?? "",
        type = ComicType(row["type"] as int),
        tags = _parseTags(row["tags"]),
        time = DateTime.fromMillisecondsSinceEpoch((row["time"] as int?) ?? 0);

  static List<String> _parseTags(Object? value) {
    if (value is! String || value.isEmpty) return const [];
    try {
      return decodeJsonList(value);
    } catch (_) {
      return const [];
    }
  }

  @override
  String get sourceKey => type.comicSource?.key ?? "Unknown:${type.value}";

  @override
  String get description => "";

  @override
  String? get language => null;

  @override
  String? get favoriteId => null;

  @override
  int? get maxPage => null;

  @override
  double? get stars => null;

  @override
  Map<String, dynamic> toJson() => {
        "id": id,
        "title": title,
        "subtitle": subtitle,
        "cover": cover,
        "type": type.value,
        "tags": tags,
        "time": time.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is ReadLaterItem &&
      other.id == id &&
      other.type.value == type.value;

  @override
  int get hashCode => Object.hash(id, type.value);
}

class ReadLaterManager with ChangeNotifier {
  static ReadLaterManager? cache;

  ReadLaterManager.create();

  factory ReadLaterManager() =>
      cache == null ? (cache = ReadLaterManager.create()) : cache!;

  late CommonDatabase _db;

  late String _dbPath;

  bool isInitialized = false;

  /// Cache of "type.value:id" keys, for fast [isExist] checks.
  final Set<String> _ids = {};

  static String _key(String id, ComicType type) => "${type.value}:$id";

  Future<void> init() async {
    if (isInitialized) {
      return;
    }
    _dbPath = "${App.dataPath}/read_later.db";
    _db = openSqliteDatabase(_dbPath);
    _db.execute("""
      create table if not exists read_later (
        id text,
        title text,
        subtitle text,
        cover text,
        type int,
        tags text,
        time int,
        primary key (id, type)
      );
    """);
    _migrateSchema();
    _loadIds();
    isInitialized = true;
    notifyListeners();
  }

  /// Expected columns, derived from the create-table schema above. Older
  /// databases were created before some columns existed; `create table if not
  /// exists` is a no-op for them, so we add any missing columns here. Adding a
  /// new field later only needs an entry in this map (mirrors the
  /// addColumnIfMissing pattern in domain_database/history/favorites), so a
  /// schema gap can never throw "no column named ..." again.
  static const Map<String, String> _expectedColumns = {
    "id": "text",
    "title": "text",
    "subtitle": "text",
    "cover": "text",
    "type": "int",
    "tags": "text",
    "time": "int",
  };

  void _migrateSchema() {
    final existing = _db
        .select("PRAGMA table_info(read_later);")
        .map((c) => c["name"] as String)
        .toSet();
    for (final entry in _expectedColumns.entries) {
      if (!existing.contains(entry.key)) {
        _db.execute(
          "alter table read_later add column ${entry.key} ${entry.value};",
        );
      }
    }
  }

  void _loadIds() {
    _ids.clear();
    try {
      final rows = _db.select("select id, type from read_later;");
      for (final row in rows) {
        _ids.add(_key(row["id"] as String, ComicType(row["type"] as int)));
      }
    } catch (e, s) {
      Log.error("ReadLater", e, s);
    }
  }

  bool isExist(String id, ComicType type) {
    if (!isInitialized) return false;
    return _ids.contains(_key(id, type));
  }

  int get count {
    if (!isInitialized) return 0;
    try {
      return _db.select("select count(*) from read_later;").first[0] as int;
    } catch (e, s) {
      Log.error("ReadLater", e, s);
      return 0;
    }
  }

  /// All items, most recent first.
  List<ReadLaterItem> getAll() {
    if (!isInitialized) return const [];
    try {
      final rows = _db.select("select * from read_later order by time desc;");
      return rows.map((r) => ReadLaterItem.fromRow(r)).toList();
    } catch (e, s) {
      Log.error("ReadLater", e, s);
      return const [];
    }
  }

  /// The [limit] most recently added items.
  List<ReadLaterItem> getRecent([int limit = 20]) {
    if (!isInitialized) return const [];
    try {
      final rows = _db.select(
        "select * from read_later order by time desc limit ?;",
        [limit],
      );
      return rows.map((r) => ReadLaterItem.fromRow(r)).toList();
    } catch (e, s) {
      Log.error("ReadLater", e, s);
      return const [];
    }
  }

  static const _insertSql = """
    insert or replace into read_later (id, title, subtitle, cover, type, tags, time)
    values (?, ?, ?, ?, ?, ?, ?);
  """;

  List<Object?> _sqlArgs(ReadLaterItem item) => [
        item.id,
        item.title,
        item.subtitle,
        item.cover,
        item.type.value,
        encodeJsonList(item.tags),
        item.time.millisecondsSinceEpoch,
      ];

  /// Add a comic to "Read Later". Builds the entry from any [Comic].
  Future<void> add(Comic comic) async {
    if (!isInitialized) return;
    final type = ComicType.fromKey(comic.sourceKey);
    await addItem(ReadLaterItem(
      id: comic.id,
      title: comic.title,
      subtitle: comic.subtitle,
      cover: comic.cover,
      type: type,
      tags: comic.tags ?? const [],
      time: DateTime.now(),
    ));
  }

  /// Add a pre-built entry to "Read Later".
  Future<void> addItem(ReadLaterItem item) async {
    if (!isInitialized) return;
    _db.execute(_insertSql, _sqlArgs(item));
    _ids.add(_key(item.id, item.type));
    notifyListeners();
  }

  /// Add multiple pre-built entries in a single transaction.
  Future<void> addMultiple(List<ReadLaterItem> items) async {
    if (!isInitialized || items.isEmpty) return;
    _db.execute("BEGIN TRANSACTION;");
    try {
      for (final item in items) {
        _db.execute(_insertSql, _sqlArgs(item));
        _ids.add(_key(item.id, item.type));
      }
      _db.execute("COMMIT;");
    } catch (e) {
      _db.execute("ROLLBACK;");
      rethrow;
    }
    notifyListeners();
  }

  /// Add multiple comics, building entries from any [Comic].
  Future<void> addComics(List<Comic> comics) async {
    if (!isInitialized || comics.isEmpty) return;
    final now = DateTime.now();
    final items = comics.map((comic) {
      final type = ComicType.fromKey(comic.sourceKey);
      return ReadLaterItem(
        id: comic.id,
        title: comic.title,
        subtitle: comic.subtitle,
        cover: comic.cover,
        type: type,
        tags: comic.tags ?? const [],
        time: now,
      );
    }).toList();
    await addMultiple(items);
  }

  Future<void> remove(String id, ComicType type) async {
    if (!isInitialized) return;
    _db.execute(
      "delete from read_later where id = ? and type = ?;",
      [id, type.value],
    );
    _ids.remove(_key(id, type));
    notifyListeners();
  }

  /// Toggle membership; returns the new state (true = now in read later).
  Future<bool> toggle(Comic comic) async {
    final type = ComicType.fromKey(comic.sourceKey);
    if (isExist(comic.id, type)) {
      await remove(comic.id, type);
      return false;
    }
    await add(comic);
    return true;
  }

  Future<void> removeMultiple(List<ReadLaterItem> items) async {
    if (!isInitialized || items.isEmpty) return;
    _db.execute("BEGIN TRANSACTION;");
    try {
      for (final item in items) {
        _db.execute(
          "delete from read_later where id = ? and type = ?;",
          [item.id, item.type.value],
        );
        _ids.remove(_key(item.id, item.type));
      }
      _db.execute("COMMIT;");
    } catch (e) {
      _db.execute("ROLLBACK;");
      rethrow;
    }
    notifyListeners();
  }

  Future<void> clearAll() async {
    if (!isInitialized) return;
    _db.execute("delete from read_later;");
    _ids.clear();
    notifyListeners();
  }

  /// Reload from disk after an import — re-open DB and refresh cache.
  Future<void> reload() async {
    if (isInitialized) {
      try {
        _db.dispose();
      } catch (_) {}
      isInitialized = false;
    }
    await init();
  }

  void close() {
    if (!isInitialized) return;
    try {
      _db.dispose();
    } catch (_) {}
    isInitialized = false;
  }
}
