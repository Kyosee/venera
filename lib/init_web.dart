import 'dart:js_interop';

import 'package:venera/foundation/sqlite_connection_web.dart';

Future<void> initPlatformServices() async {
  await initWebSqlite();
  _registerLifecycleFlush();
}

@JS('window.addEventListener')
external void _windowAddEventListener(String type, JSFunction callback);

void _registerLifecycleFlush() {
  try {
    _windowAddEventListener('beforeunload', (() {
      flushSqliteDatabases();
    }).toJS);
    _windowAddEventListener('pagehide', (() {
      flushSqliteDatabases();
    }).toJS);
  } catch (_) {}
}

void initAndroidExtras() {}

Future<void> trySetHighRefreshRate() async {}
