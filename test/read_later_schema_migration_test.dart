import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/foundation/read_later.dart';

// These tests validate ReadLaterManager.migrateSchema against databases that
// were NOT created by us — e.g. a read_later.db carried over from a foreign
// Venera fork via WebDAV/backup import. The table name collides but the layout
// differs. migrateSchema must normalize any such table to our canonical 7
// columns, preserve the data it can map by column name, and leave a table that
// our fixed-column INSERT can write to.

const _canonicalInsert = """
  insert or replace into read_later (id, title, subtitle, cover, type, tags, time)
  values (?, ?, ?, ?, ?, ?, ?);
""";

List<String> _columns(Database db) => db
    .select("PRAGMA table_info(read_later);")
    .map((r) => r["name"] as String)
    .toList();

void _expectCanonical(Database db) {
  expect(
    _columns(db)..sort(),
    ["cover", "id", "subtitle", "tags", "time", "title", "type"],
    reason: "table should be normalized to the canonical 7 columns",
  );
  // The canonical INSERT must succeed (this is the bug we are fixing).
  db.execute(_canonicalInsert,
      ["x", "新书", null, "http://c", 1, '["t"]', 123]);
}

void main() {
  test('foreign source_key NOT NULL column is dropped and data preserved', () {
    final db = sqlite3.openInMemory();
    // Foreign schema: extra `source_key text not null` column that our INSERT
    // never supplies — the exact crash reported in the wild.
    db.execute("""
      create table read_later (
        id text, title text, cover text, type int,
        source_key text not null, time int,
        primary key (id, type)
      );
    """);
    db.execute(
      "insert into read_later (id, title, cover, type, source_key, time) "
      "values (?, ?, ?, ?, ?, ?);",
      ["zhanduidashige", "戰隊大失格", "http://cover", 557997769, "mangafunb", 1781411466143],
    );

    ReadLaterManager.migrateSchema(db);

    _expectCanonical(db);
    // The recognized data (id/title/cover/type/time) must survive the rebuild.
    final row = db
        .select("select * from read_later where id = 'zhanduidashige';")
        .first;
    expect(row["title"], "戰隊大失格");
    expect(row["cover"], "http://cover");
    expect(row["type"], 557997769);
    expect(row["time"], 1781411466143);
    db.dispose();
  });

  test('foreign columns of differing type are dropped, kept columns coerced',
      () {
    final db = sqlite3.openInMemory();
    // `time` stored as TEXT in the foreign table; plus an extra column.
    db.execute("""
      create table read_later (
        id text, title text, type int, time text, extra_blob blob,
        primary key (id, type)
      );
    """);
    db.execute(
      "insert into read_later (id, title, type, time, extra_blob) "
      "values ('a', 't', 5, '999', x'00');",
    );

    ReadLaterManager.migrateSchema(db);

    _expectCanonical(db);
    final row = db.select("select * from read_later where id = 'a';").first;
    expect(row["title"], "t");
    // INT column affinity coerces the numeric string back to an int.
    expect(row["time"], 999);
    db.dispose();
  });

  test('older subset-of-our-columns table is additively backfilled, not rebuilt',
      () {
    final db = sqlite3.openInMemory();
    // Only our own columns, but missing subtitle/tags (an older OUR schema).
    db.execute("""
      create table read_later (
        id text, title text, cover text, type int, time int,
        primary key (id, type)
      );
    """);
    db.execute(
      "insert into read_later (id, title, cover, type, time) "
      "values ('b', 'bt', 'bc', 2, 7);",
    );

    ReadLaterManager.migrateSchema(db);

    _expectCanonical(db);
    final row = db.select("select * from read_later where id = 'b';").first;
    expect(row["title"], "bt");
    expect(row["subtitle"], isNull);
    expect(row["tags"], isNull);
    db.dispose();
  });

  test('already-canonical table is left untouched and writable', () {
    final db = sqlite3.openInMemory();
    db.execute("""
      create table read_later (
        id text, title text, subtitle text, cover text,
        type int, tags text, time int,
        primary key (id, type)
      );
    """);
    db.execute(_canonicalInsert, ["c", "ct", "cs", "cc", 3, "[]", 9]);

    ReadLaterManager.migrateSchema(db);

    _expectCanonical(db);
    expect(
      db.select("select count(*) from read_later;").first[0],
      // original row + the probe row from _expectCanonical
      2,
    );
    db.dispose();
  });

  test('rows with null primary-key columns are skipped, not fatal', () {
    final db = sqlite3.openInMemory();
    db.execute("""
      create table read_later (
        id text, title text, type int, source_key text not null
      );
    """);
    // A foreign row missing our `time` and with a null id should not abort the
    // whole rebuild — insert or ignore skips it.
    db.execute(
      "insert into read_later (id, title, type, source_key) "
      "values (null, 'orphan', 1, 'sk');",
    );
    db.execute(
      "insert into read_later (id, title, type, source_key) "
      "values ('ok', 'good', 1, 'sk');",
    );

    ReadLaterManager.migrateSchema(db);

    _expectCanonical(db);
    // The valid row survives; the probe row from _expectCanonical is also there.
    final ids = db
        .select("select id from read_later order by id;")
        .map((r) => r["id"])
        .toList();
    expect(ids, contains("ok"));
    db.dispose();
  });
}
