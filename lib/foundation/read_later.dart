import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_type.dart';
import 'package:venera/foundation/favorites_meta.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/foundation/sqlite_connection.dart';
import 'package:venera/utils/server_db.dart';

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
    _loadIds();
    isInitialized = true;
    notifyListeners();
  }

  void _loadIds() {
    _ids.clear();
    if (kIsWeb) return;
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
    _trackServerWrite(_upsertServer(item));
    notifyListeners();
  }

  Future<void> remove(String id, ComicType type) async {
    if (!isInitialized) return;
    _db.execute(
      "delete from read_later where id = ? and type = ?;",
      [id, type.value],
    );
    _ids.remove(_key(id, type));
    _trackServerWrite(_deleteServer(id, type));
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
    for (final item in items) {
      _trackServerWrite(_deleteServer(item.id, item.type));
    }
    notifyListeners();
  }

  Future<void> clearAll() async {
    if (!isInitialized) return;
    _db.execute("delete from read_later;");
    _ids.clear();
    _trackServerWrite(_clearServer());
    notifyListeners();
  }

  // ---- Web server sync (no-ops on native) ----

  final _pendingServerWrites = <Future<void>>{};

  void _trackServerWrite(Future<void> pending) {
    _pendingServerWrites.add(pending);
    unawaited(
      pending.whenComplete(() => _pendingServerWrites.remove(pending)),
    );
  }

  /// Wait for in-flight server writes to finish (used before WebDAV upload).
  Future<void> waitServerReadLaterSync() async {
    if (!kIsWeb || _pendingServerWrites.isEmpty) return;
    await Future.wait(_pendingServerWrites.toList());
  }

  Future<void> _upsertServer(ReadLaterItem item) async {
    if (!kIsWeb) return;
    try {
      await const ServerDbClient().upsertReadLater(item);
    } catch (e, s) {
      Log.error("Server DB ReadLater", e, s);
    }
  }

  Future<void> _deleteServer(String id, ComicType type) async {
    if (!kIsWeb) return;
    try {
      await const ServerDbClient().deleteReadLater(id, type);
    } catch (e, s) {
      Log.error("Server DB ReadLater", e, s);
    }
  }

  Future<void> _clearServer() async {
    if (!kIsWeb) return;
    try {
      await const ServerDbClient().clearReadLater();
    } catch (e, s) {
      Log.error("Server DB ReadLater", e, s);
    }
  }

  /// Reload from disk after an import (native) — re-open DB and refresh cache.
  Future<void> reload() async {
    if (kIsWeb) {
      await loadFromServer();
      return;
    }
    if (isInitialized) {
      try {
        _db.dispose();
      } catch (_) {}
      isInitialized = false;
    }
    await init();
  }

  /// Web only: pull the full list from the server into the local mirror DB.
  Future<void> loadFromServer() async {
    if (!kIsWeb || !isInitialized) return;
    try {
      final items = await const ServerDbClient().listReadLater();
      if (items == null) return;
      _db.execute("delete from read_later;");
      _ids.clear();
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
    } catch (e, s) {
      Log.error("Server DB ReadLater", e, s);
    }
  }

  void close() {
    if (!isInitialized) return;
    try {
      _db.dispose();
    } catch (_) {}
    isInitialized = false;
  }
}
