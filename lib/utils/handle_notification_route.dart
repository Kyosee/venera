import 'package:flutter/services.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/pages/downloading_page.dart';
import 'package:venera/pages/follow_updates_page.dart';
import 'package:venera/pages/tasks_page.dart';

bool _isHandling = false;

/// Handle taps on background-task notifications (Android only).
///
/// Each foreground service tags its notification's PendingIntent with a route
/// string (see the native `*KeepAliveService`); MainActivity forwards it over
/// the `venera/notification_route` event channel. Here we map the route to a
/// page and navigate, so tapping a follow-update / sync / download card lands
/// on the matching screen instead of merely opening the app (#148).
void handleNotificationRoute() async {
  if (_isHandling) return;
  _isHandling = true;

  var channel = const EventChannel('venera/notification_route');
  await for (var event in channel.receiveBroadcastStream()) {
    if (event is! String) continue;
    // The navigator can lag a cold start; wait briefly for it to attach.
    if (App.mainNavigatorKey == null) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    switch (event) {
      case 'follow_updates':
        App.rootContext.to(() => const FollowUpdatesPage());
      case 'tasks':
        App.rootContext.to(() => const TasksPage());
      case 'downloading':
        App.rootContext.to(() => const DownloadingPage());
    }
  }
}
