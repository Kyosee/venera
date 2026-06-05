import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:venera/network/cookie_jar.dart';

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      open.overrideFor(
        OperatingSystem.windows,
        () => DynamicLibrary.open('winsqlite3.dll'),
      );
    }
  });

  test('deleteByName removes matching cookie across paths only', () {
    final tempDir = Directory.systemTemp.createTempSync('venera_cookie_jar_');
    final jar = CookieJarSql('${tempDir.path}/cookie.db');
    final uri = Uri.parse('https://example.com/path/page');

    try {
      jar.saveFromResponse(uri, [
        Cookie('cf_clearance', 'root')
          ..domain = '.example.com'
          ..path = '/',
        Cookie('cf_clearance', 'nested')
          ..domain = '.example.com'
          ..path = '/path',
        Cookie('MPIC_bnS5', 'keep')
          ..domain = '.example.com'
          ..path = '/',
      ]);

      expect(jar.loadForRequestCookieHeader(uri), contains('cf_clearance='));

      jar.deleteByName(uri, 'cf_clearance');

      final header = jar.loadForRequestCookieHeader(uri);
      expect(header, isNot(contains('cf_clearance=')));
      expect(header, contains('MPIC_bnS5=keep'));
    } finally {
      jar.dispose();
      tempDir.deleteSync(recursive: true);
    }
  });

  test('saveFromResponse normalizes empty cookie domain and path', () {
    final tempDir = Directory.systemTemp.createTempSync('venera_cookie_jar_');
    final jar = CookieJarSql('${tempDir.path}/cookie.db');
    final uri = Uri.parse('https://example.com/path/page');

    try {
      jar.saveFromResponse(uri, [
        Cookie('cf_clearance', 'value')
          ..domain = ''
          ..path = '',
      ]);

      expect(
        jar.loadForRequestCookieHeader(uri),
        contains('cf_clearance=value'),
      );
    } finally {
      jar.dispose();
      tempDir.deleteSync(recursive: true);
    }
  });
}
