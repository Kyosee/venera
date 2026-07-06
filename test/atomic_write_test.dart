import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/utils/io.dart' show writeStringAtomic;

// appdata.json / implicitData.json are replaced through writeStringAtomic so
// a process kill mid-write can never leave a truncated file — the load paths
// reset unparseable JSON wholesale, which used to wipe every setting
// (WebDAV credentials, dataVersion, task histories) after an unlucky kill.

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('venera_atomic_write');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('creates a new file with the exact content', () async {
    final path = "${dir.path}${Platform.pathSeparator}a.json";
    await writeStringAtomic(path, '{"k":1}');
    expect(File(path).readAsStringSync(), '{"k":1}');
  });

  test('replaces an existing file and leaves no temp file behind', () async {
    final path = "${dir.path}${Platform.pathSeparator}a.json";
    File(path).writeAsStringSync('old');
    await writeStringAtomic(path, 'new content');
    expect(File(path).readAsStringSync(), 'new content');
    expect(File('$path.tmp').existsSync(), false,
        reason: "the temp file must be renamed away on success");
  });

  test('sequential writes keep the last content', () async {
    final path = "${dir.path}${Platform.pathSeparator}a.json";
    for (var i = 0; i < 5; i++) {
      await writeStringAtomic(path, 'v$i');
    }
    expect(File(path).readAsStringSync(), 'v4');
  });
}
