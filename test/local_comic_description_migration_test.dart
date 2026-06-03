import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

// 复刻 init() 中的迁移逻辑做纯 DB 验证(不依赖 App 路径)。
void applyDescriptionMigration(Database db) {
  final cols = db.select('PRAGMA table_info(comics);')
      .map((r) => r['name'] as String).toList();
  if (!cols.contains('description')) {
    db.execute(
        "ALTER TABLE comics ADD COLUMN description TEXT NOT NULL DEFAULT '';");
  }
}

void main() {
  test('migration adds description column to legacy table', () {
    final db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE comics (
        id TEXT NOT NULL, title TEXT NOT NULL, subtitle TEXT NOT NULL,
        tags TEXT NOT NULL, directory TEXT NOT NULL, chapters TEXT NOT NULL,
        cover TEXT NOT NULL, comic_type INTEGER NOT NULL,
        downloadedChapters TEXT NOT NULL, created_at INTEGER,
        PRIMARY KEY (id, comic_type));
    ''');
    db.execute("INSERT INTO comics VALUES "
        "('1','t','s','[]','d','{}','c',0,'[]',0);");

    applyDescriptionMigration(db);

    final cols = db.select('PRAGMA table_info(comics);')
        .map((r) => r['name'] as String).toList();
    expect(cols, contains('description'));
    final row = db.select("SELECT description FROM comics WHERE id='1';").first;
    expect(row['description'], '');

    applyDescriptionMigration(db); // 幂等
    db.dispose();
  });
}
