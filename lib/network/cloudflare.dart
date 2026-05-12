import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/consts.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/pages/webview.dart';

import 'cookie_jar.dart';

class CloudflareException implements DioException {
  final String url;

  CloudflareException(this.url);

  @override
  String toString() {
    return "CloudflareException: $url";
  }

  static CloudflareException? fromString(String message) {
    var match = RegExp(r"CloudflareException: (.+)").firstMatch(message);
    if (match == null) return null;
    return CloudflareException(match.group(1)!);
  }

  @override
  DioException copyWith({
    RequestOptions? requestOptions,
    Response<dynamic>? response,
    DioExceptionType? type,
    Object? error,
    StackTrace? stackTrace,
    String? message,
  }) {
    return this;
  }

  @override
  Object? get error => this;

  @override
  String? get message => toString();

  @override
  RequestOptions get requestOptions => RequestOptions();

  @override
  Response? get response => null;

  @override
  StackTrace get stackTrace => StackTrace.empty;

  @override
  DioExceptionType get type => DioExceptionType.badResponse;

  @override
  DioExceptionReadableStringBuilder? stringBuilder;
}

class CloudflareInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.headers['cookie'].toString().contains('cf_clearance') ||
        _isCloudflareVerifiedHost(options.uri.host)) {
      _applyBrowserHeaders(options);
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 403) {
      handler.next(_check(err.response!) ?? err);
    } else {
      handler.next(err);
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.statusCode == 403) {
      var err = _check(response);
      if (err != null) {
        handler.reject(err);
        return;
      }
    }
    handler.next(response);
  }

  CloudflareException? _check(Response response) {
    if (response.headers['cf-mitigated']?.firstOrNull == "challenge") {
      SingleInstanceCookieJar.instance?.deleteByName(
        response.requestOptions.uri,
        'cf_clearance',
      );
      return CloudflareException(response.requestOptions.uri.toString());
    }
    return null;
  }
}

const _cloudflareVerifiedHostsKey = 'cloudflareVerifiedHosts';

void _applyBrowserHeaders(RequestOptions options) {
  _setHeader(options, 'User-Agent', appdata.implicitData['ua'] ?? webUA);
  _putHeaderIfAbsent(
    options,
    'Accept',
    'text/html,application/xhtml+xml,application/xml;q=0.9,'
        'image/avif,image/webp,image/apng,*/*;q=0.8',
  );
  _putHeaderIfAbsent(options, 'Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.8');
  if (options.method.toUpperCase() == 'GET') {
    _putHeaderIfAbsent(options, 'Upgrade-Insecure-Requests', '1');
  }
}

void _setHeader(RequestOptions options, String name, Object value) {
  var keys = options.headers.keys
      .where((key) => key.toLowerCase() == name.toLowerCase())
      .toList();
  for (var key in keys) {
    options.headers.remove(key);
  }
  options.headers[name] = value;
}

void _putHeaderIfAbsent(RequestOptions options, String name, Object value) {
  var exists = options.headers.keys.any(
    (key) => key.toLowerCase() == name.toLowerCase(),
  );
  if (!exists) {
    options.headers[name] = value;
  }
}

bool _isCloudflareVerifiedHost(String host) {
  var data = appdata.implicitData[_cloudflareVerifiedHostsKey];
  return data is List && data.contains(host);
}

void _markCloudflareVerifiedHost(String host) {
  var data = appdata.implicitData[_cloudflareVerifiedHostsKey];
  var hosts = data is List ? data.whereType<String>().toSet() : <String>{};
  if (hosts.add(host)) {
    appdata.implicitData[_cloudflareVerifiedHostsKey] = hosts.toList();
    appdata.writeImplicitData();
  }
}

String _cloudflareProfilePath(Uri uri) {
  var host = uri.host.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  return "${App.dataPath}\\cloudflare_webview\\$host";
}

void _resetCloudflareProfile(Uri uri) {
  if (!App.isWindows) {
    return;
  }
  try {
    var dir = io.Directory(_cloudflareProfilePath(uri));
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  } catch (e, s) {
    Log.warning(
      "Cloudflare",
      "Failed to reset Cloudflare webview profile\n$e\n$s",
    );
  }
}

void passCloudflare(CloudflareException e, void Function() onFinished) async {
  var url = e.url;
  var uri = Uri.parse(url);
  var completed = false;
  SingleInstanceCookieJar.instance?.deleteByName(uri, 'cf_clearance');
  _resetCloudflareProfile(uri);

  void finish() {
    if (completed) {
      return;
    }
    completed = true;
    onFinished();
  }

  void saveCookies(Map<String, String> cookies) {
    var domain = uri.host;
    var splits = domain.split('.');
    if (splits.length > 1) {
      domain = ".${splits[splits.length - 2]}.${splits[splits.length - 1]}";
    }
    SingleInstanceCookieJar.instance?.deleteByName(uri, 'cf_clearance');
    SingleInstanceCookieJar.instance?.saveFromResponse(
      uri,
      List<io.Cookie>.generate(cookies.length, (index) {
        var cookie = io.Cookie(
          cookies.keys.elementAt(index),
          cookies.values.elementAt(index),
        );
        cookie.domain = domain;
        return cookie;
      }),
    );
    Log.info(
      "Cloudflare",
      "Saved ${cookies.length} cookies, "
          "cf_clearance=${cookies.containsKey('cf_clearance')}",
    );
    _markCloudflareVerifiedHost(uri.host);
  }

  // Desktop WebView can read cookies more reliably than in-app WebView on
  // Windows, especially Cloudflare's HttpOnly clearance cookie.
  var useDesktopWebview = false;
  if (App.isDesktop) {
    try {
      useDesktopWebview = await DesktopWebview.isAvailable();
    } catch (e, s) {
      Log.warning(
        "Cloudflare",
        "Desktop webview is unavailable, fallback to AppWebview\n$e\n$s",
      );
    }
  }

  if (useDesktopWebview) {
    var webview = DesktopWebview(
      initialUrl: url,
      userDataFolderWindows: _cloudflareProfilePath(uri),
      onTitleChange: (title, controller) async {
        var head =
            await controller.evaluateJavascript("document.head.innerHTML") ??
            "";
        var body =
            await controller.evaluateJavascript("document.body.innerHTML") ??
            "";
        Log.info("Cloudflare", "Checking head: $head");
        var isChallenging =
            head.contains('#challenge-success-text') ||
            head.contains("#challenge-error-text") ||
            head.contains("#challenge-form") ||
            body.contains("challenge-platform") ||
            body.contains("window._cf_chl_opt");
        if (!isChallenging) {
          Log.info(
            "Cloudflare",
            "Cloudflare is passed due to there is no challenge css",
          );
          var ua = controller.userAgent;
          if (ua != null) {
            appdata.implicitData['ua'] = ua;
            appdata.writeImplicitData();
          }
          var cookiesMap = await controller.getCookies(url);
          saveCookies(cookiesMap);
          controller.close();
          finish();
        }
      },
      onClose: finish,
    );
    webview.open();
  } else {
    bool success = false;
    void check(InAppWebViewController controller) async {
      if (success) {
        return;
      }
      var head =
          (await controller.evaluateJavascript(
            source: "document.head.innerHTML",
          ))?.toString() ??
          "";
      var body =
          (await controller.evaluateJavascript(
            source: "document.body.innerHTML",
          ))?.toString() ??
          "";
      Log.info("Cloudflare", "Checking head: $head");
      var isChallenging =
          head.contains('#challenge-success-text') ||
          head.contains("#challenge-error-text") ||
          head.contains("#challenge-form") ||
          body.contains("challenge-platform") ||
          body.contains("window._cf_chl_opt");
      if (!isChallenging) {
        Log.info(
          "Cloudflare",
          "Cloudflare is passed due to there is no challenge css",
        );
        success = true;
        var ua = await controller.getUA();
        if (ua != null) {
          appdata.implicitData['ua'] = ua;
          appdata.writeImplicitData();
        }
        var cookies = await controller.getCookies(url) ?? [];
        SingleInstanceCookieJar.instance?.deleteByName(uri, 'cf_clearance');
        SingleInstanceCookieJar.instance?.saveFromResponse(uri, cookies);
        Log.info(
          "Cloudflare",
          "Saved ${cookies.length} cookies, "
              "cf_clearance=${cookies.any((cookie) => cookie.name == 'cf_clearance')}",
        );
        _markCloudflareVerifiedHost(uri.host);
        App.rootPop();
      }
    }

    await App.rootContext.to(
      () => AppWebview(
        initialUrl: url,
        singlePage: true,
        onTitleChange: (title, controller) async {
          // Keep the webview open until page load stops; title changes can fire
          // before Cloudflare has flushed cookies to the platform store.
        },
        onLoadStop: (controller) async {
          check(controller);
        },
        onStarted: (controller) async {
          var ua = await controller.getUA();
          if (ua != null) {
            appdata.implicitData['ua'] = ua;
            appdata.writeImplicitData();
          }
        },
      ),
    );
    finish();
  }
}
