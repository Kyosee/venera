import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:venera/foundation/log.dart';
import 'package:venera/network/cors_proxy.dart';

class WebHelperBrowserCookie {
  const WebHelperBrowserCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path,
  });

  final String name;
  final String value;
  final String? domain;
  final String? path;

  factory WebHelperBrowserCookie.fromJson(Map<dynamic, dynamic> json) {
    return WebHelperBrowserCookie(
      name: json['name']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
      domain: json['domain']?.toString(),
      path: json['path']?.toString(),
    );
  }
}

class WebHelperBrowserState {
  const WebHelperBrowserState({
    required this.sessionId,
    required this.url,
    required this.title,
    required this.viewUrl,
    required this.userAgent,
    required this.localStorage,
    required this.localStorageByOrigin,
    required this.cookies,
  });

  final String sessionId;
  final String url;
  final String title;
  final String viewUrl;
  final String userAgent;
  final Map<String, dynamic> localStorage;
  final Map<String, Map<String, dynamic>> localStorageByOrigin;
  final List<WebHelperBrowserCookie> cookies;

  factory WebHelperBrowserState.fromJson(Map<dynamic, dynamic> json) {
    final state = json['state'] is Map ? json['state'] as Map : json;
    final rawCookies = state['cookies'] is List ? state['cookies'] as List : [];
    final rawStorage = state['localStorage'] is Map
        ? state['localStorage'] as Map
        : const {};
    final rawStorageByOrigin = state['localStorageByOrigin'] is Map
        ? state['localStorageByOrigin'] as Map
        : const {};

    return WebHelperBrowserState(
      sessionId: json['sessionId']?.toString() ?? '',
      url: state['url']?.toString() ?? '',
      title: state['title']?.toString() ?? '',
      viewUrl: json['viewUrl']?.toString() ?? '',
      userAgent: state['userAgent']?.toString() ?? '',
      localStorage: rawStorage.map((key, value) => MapEntry('$key', value)),
      localStorageByOrigin: rawStorageByOrigin.map((origin, value) {
        final storage = value is Map ? value : const {};
        return MapEntry(
          '$origin',
          storage.map((key, value) => MapEntry('$key', value)),
        );
      }),
      cookies: rawCookies
          .whereType<Map>()
          .map(WebHelperBrowserCookie.fromJson)
          .where((cookie) => cookie.name.isNotEmpty)
          .toList(),
    );
  }

  List<String> valuesForCookieFields(List<String> fields) {
    final byName = <String, String>{};
    final byLowerName = <String, String>{};
    for (final cookie in cookies) {
      byName[cookie.name] = cookie.value;
      byLowerName[cookie.name.toLowerCase()] = cookie.value;
    }
    return fields
        .map((field) => byName[field] ?? byLowerName[field.toLowerCase()] ?? '')
        .toList();
  }
}

class WebLoginImportData {
  const WebLoginImportData({
    this.url,
    this.userAgent,
    this.authorization,
    this.localStorage = const {},
    this.sessionStorage = const {},
    this.cookies = const [],
  });

  final String? url;
  final String? userAgent;
  final String? authorization;
  final Map<String, dynamic> localStorage;
  final Map<String, dynamic> sessionStorage;
  final List<WebHelperBrowserCookie> cookies;

  factory WebLoginImportData.parse(String input, {String? fallbackUrl}) {
    final text = input.trim();
    if (text.isEmpty) return WebLoginImportData(url: fallbackUrl);
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return WebLoginImportData._fromMap(decoded, fallbackUrl: fallbackUrl);
      }
    } catch (_) {}
    return WebLoginImportData._fromHeaders(text, fallbackUrl: fallbackUrl);
  }

  bool get hasLoginPayload {
    return cookies.isNotEmpty ||
        localStorage.isNotEmpty ||
        sessionStorage.isNotEmpty ||
        token != null;
  }

  String? get token {
    return _extractTokenFromMap(localStorage) ??
        _extractTokenFromMap(sessionStorage) ??
        _normalizeTokenCandidate(authorization) ??
        _extractTokenFromCookies(cookies);
  }

  List<String> valuesForCookieFields(List<String> fields) {
    final byName = <String, String>{};
    final byLowerName = <String, String>{};
    for (final cookie in cookies) {
      byName[cookie.name] = cookie.value;
      byLowerName[cookie.name.toLowerCase()] = cookie.value;
    }
    return fields
        .map((field) => byName[field] ?? byLowerName[field.toLowerCase()] ?? '')
        .toList();
  }

  static WebLoginImportData _fromMap(
    Map<dynamic, dynamic> source, {
    String? fallbackUrl,
  }) {
    final headers = _mapFromAny(source['headers'] ?? source['requestHeaders']);
    final cookies = <WebHelperBrowserCookie>[
      ..._cookiesFromAny(source['cookies']),
      ..._parseCookieHeader(_stringFromAny(source['cookie'])),
      ..._parseCookieHeader(_stringFromAny(source['documentCookie'])),
      ..._parseCookieHeader(_headerValue(headers, 'cookie')),
      ..._parseSetCookieLines(source['setCookie'] ?? source['setCookies']),
    ];
    return WebLoginImportData(
      url: _stringFromAny(source['url'] ?? source['href']) ?? fallbackUrl,
      userAgent:
          _stringFromAny(source['userAgent'] ?? source['ua']) ??
          _headerValue(headers, 'user-agent'),
      authorization:
          _stringFromAny(source['authorization']) ??
          _headerValue(headers, 'authorization'),
      localStorage: _mapFromAny(source['localStorage']),
      sessionStorage: _mapFromAny(source['sessionStorage']),
      cookies: _dedupeCookies(cookies),
    );
  }

  static WebLoginImportData _fromHeaders(String text, {String? fallbackUrl}) {
    String? cookieHeader;
    String? userAgent;
    String? authorization;
    final setCookies = <WebHelperBrowserCookie>[];
    for (final rawLine in text.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trim();
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final name = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      if (name == 'cookie') {
        cookieHeader = [
          if (cookieHeader != null && cookieHeader.isNotEmpty) cookieHeader,
          value,
        ].join('; ');
      } else if (name == 'set-cookie') {
        final cookie = _parseSetCookie(value);
        if (cookie != null) setCookies.add(cookie);
      } else if (name == 'user-agent') {
        userAgent = value;
      } else if (name == 'authorization') {
        authorization = value;
      }
    }
    return WebLoginImportData(
      url: fallbackUrl,
      userAgent: userAgent,
      authorization: authorization,
      cookies: _dedupeCookies([
        ..._parseCookieHeader(cookieHeader),
        ...setCookies,
      ]),
    );
  }
}

class WebLoginImportStatus {
  const WebLoginImportStatus({
    required this.status,
    this.receivedAt,
    this.data,
  });

  final String status;
  final String? receivedAt;
  final WebLoginImportData? data;

  bool get isCompleted => status == 'completed' && data != null;

  factory WebLoginImportStatus.fromJson(Map<dynamic, dynamic> json) {
    final payload = json['payload'];
    return WebLoginImportStatus(
      status: json['status']?.toString() ?? 'pending',
      receivedAt: json['receivedAt']?.toString(),
      data: payload is Map ? WebLoginImportData._fromMap(payload) : null,
    );
  }
}

class WebHelperBrowserClient {
  WebHelperBrowserClient({Dio? dio, this.proxyEndpoint}) : _dio = dio ?? Dio();

  final Dio _dio;
  final String? proxyEndpoint;

  String? _route(String route) {
    final proxyUrl = resolveCorsProxyEndpoint(
      explicitEndpoint: proxyEndpoint,
      useSameOriginDefault: true,
    );
    if (proxyUrl == null) return null;
    return buildHelperRouteUrl(proxyUrl, route);
  }

  Future<WebHelperBrowserState?> createSession({
    required String url,
    String? sessionId,
    bool syncCookies = true,
    Duration wait = const Duration(seconds: 45),
  }) async {
    final endpoint = _route('browser/session');
    if (endpoint == null) return null;
    try {
      final response = await _dio.post(
        endpoint,
        data: {
          'url': url,
          if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
          'syncCookies': syncCookies,
          'waitMs': wait.inMilliseconds,
        },
      );
      if (response.data is Map) {
        return WebHelperBrowserState.fromJson(response.data as Map);
      }
    } catch (error, stack) {
      Log.warning(
        'Web Helper Browser',
        'Create session failed: $error\n$stack',
      );
    }
    return null;
  }

  Future<WebHelperBrowserState?> state(String sessionId, {String? url}) async {
    final endpoint = _route('browser/session/$sessionId/state');
    if (endpoint == null) return null;
    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: {if (url != null) 'url': url},
      );
      if (response.data is Map) {
        return WebHelperBrowserState.fromJson(response.data as Map);
      }
    } catch (error, stack) {
      Log.warning('Web Helper Browser', 'Read state failed: $error\n$stack');
    }
    return null;
  }

  Future<WebHelperBrowserState?> syncCookies(
    String sessionId, {
    String? url,
  }) async {
    final endpoint = _route('browser/session/$sessionId/sync-cookies');
    if (endpoint == null) return null;
    try {
      final response = await _dio.post(
        endpoint,
        data: {if (url != null) 'url': url},
      );
      if (response.data is Map) {
        return WebHelperBrowserState.fromJson(response.data as Map);
      }
    } catch (error, stack) {
      Log.warning('Web Helper Browser', 'Sync cookies failed: $error\n$stack');
    }
    return null;
  }

  String? loginImportUrl(String code) {
    return _routeWithSegments(['login-import', code]);
  }

  String? loginImportShortcutUrl(String code) {
    return _routeWithSegments(['login-import', code, 'shortcut']);
  }

  String? _routeWithSegments(List<String> routeSegments) {
    final base = _route('');
    if (base == null) return null;
    final uri = Uri.parse(base);
    return uri
        .replace(
          pathSegments: [
            ...uri.pathSegments.where((segment) => segment.isNotEmpty),
            ...routeSegments,
          ],
        )
        .toString();
  }

  Future<WebLoginImportStatus?> loginImportStatus(String code) async {
    final endpoint = loginImportUrl(code);
    if (endpoint == null) return null;
    try {
      final response = await _dio.get(endpoint);
      if (response.data is Map) {
        return WebLoginImportStatus.fromJson(response.data as Map);
      }
    } catch (error, stack) {
      Log.warning(
        'Web Helper Browser',
        'Read login import failed: $error\n$stack',
      );
    }
    return null;
  }

  Future<void> clearLoginImport(String code) async {
    final endpoint = loginImportUrl(code);
    if (endpoint == null) return;
    try {
      await _dio.delete(endpoint);
    } catch (error, stack) {
      Log.warning(
        'Web Helper Browser',
        'Clear login import failed: $error\n$stack',
      );
    }
  }

  String? eventsUrl(String sessionId, {String? url}) {
    final endpoint = _route('browser/session/$sessionId/events');
    if (endpoint == null || url == null || url.isEmpty) return endpoint;
    final uri = Uri.parse(endpoint);
    return uri
        .replace(queryParameters: {...uri.queryParameters, 'url': url})
        .toString();
  }

  Future<void> close(String sessionId) async {
    final endpoint = _route('browser/session/$sessionId/close');
    if (endpoint == null) return;
    try {
      await _dio.post(endpoint);
    } catch (error, stack) {
      Log.warning('Web Helper Browser', 'Close session failed: $error\n$stack');
    }
  }
}

String createWebLoginImportCode(String sourceKey) {
  final prefix = sourceKey
      .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '')
      .trim();
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  final token = base64UrlEncode(bytes).replaceAll('=', '');
  final safePrefix = prefix.isEmpty ? 'login' : prefix;
  return '${safePrefix.substring(0, min(safePrefix.length, 40))}-$token';
}

String? extractTokenFromHelperBrowserState(WebHelperBrowserState state) {
  return _extractTokenFromMap(state.localStorage) ??
      _extractTokenFromCookies(state.cookies) ??
      _extractTokenFromAny(state.localStorageByOrigin, aggressive: true);
}

String? _stringFromAny(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

Map<String, dynamic> _mapFromAny(dynamic value) {
  if (value is! Map) return const {};
  return value.map((key, value) => MapEntry(key.toString(), value));
}

String? _headerValue(Map<String, dynamic> headers, String name) {
  final lowerName = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lowerName) {
      return _stringFromAny(entry.value);
    }
  }
  return null;
}

List<WebHelperBrowserCookie> _cookiesFromAny(dynamic value) {
  if (value is String) return _parseCookieHeader(value);
  if (value is! List) return const [];
  final cookies = <WebHelperBrowserCookie>[];
  for (final item in value) {
    if (item is Map) {
      final cookie = WebHelperBrowserCookie.fromJson(item);
      if (cookie.name.isNotEmpty) cookies.add(cookie);
    } else if (item is String) {
      cookies.addAll(_parseCookieHeader(item));
    }
  }
  return cookies;
}

List<WebHelperBrowserCookie> _parseCookieHeader(String? value) {
  var text = value?.trim() ?? '';
  if (text.isEmpty) return const [];
  final separator = text.indexOf(':');
  if (separator > 0 &&
      text.substring(0, separator).trim().toLowerCase() == 'cookie') {
    text = text.substring(separator + 1).trim();
  }
  final cookies = <WebHelperBrowserCookie>[];
  for (final part in text.split(';')) {
    final item = part.trim();
    final equals = item.indexOf('=');
    if (equals <= 0) continue;
    final name = item.substring(0, equals).trim();
    final cookieValue = item.substring(equals + 1).trim();
    if (name.isEmpty || _isSetCookieAttribute(name)) continue;
    cookies.add(WebHelperBrowserCookie(name: name, value: cookieValue));
  }
  return cookies;
}

List<WebHelperBrowserCookie> _parseSetCookieLines(dynamic value) {
  if (value is String) {
    final cookie = _parseSetCookie(value);
    return cookie == null ? const [] : [cookie];
  }
  if (value is! List) return const [];
  return value
      .map(_parseSetCookie)
      .whereType<WebHelperBrowserCookie>()
      .toList();
}

WebHelperBrowserCookie? _parseSetCookie(dynamic value) {
  var text = _stringFromAny(value);
  if (text == null) return null;
  final separator = text.indexOf(':');
  if (separator > 0 &&
      text.substring(0, separator).trim().toLowerCase() == 'set-cookie') {
    text = text.substring(separator + 1).trim();
  }
  final parts = text.split(';').map((e) => e.trim()).toList();
  if (parts.isEmpty) return null;
  final firstEquals = parts.first.indexOf('=');
  if (firstEquals <= 0) return null;
  final name = parts.first.substring(0, firstEquals).trim();
  final cookieValue = parts.first.substring(firstEquals + 1).trim();
  String? domain;
  String? path;
  for (final attribute in parts.skip(1)) {
    final equals = attribute.indexOf('=');
    if (equals <= 0) continue;
    final key = attribute.substring(0, equals).trim().toLowerCase();
    final value = attribute.substring(equals + 1).trim();
    if (key == 'domain') {
      domain = value;
    } else if (key == 'path') {
      path = value;
    }
  }
  return WebHelperBrowserCookie(
    name: name,
    value: cookieValue,
    domain: domain,
    path: path,
  );
}

bool _isSetCookieAttribute(String name) {
  return const {
    'path',
    'domain',
    'expires',
    'max-age',
    'samesite',
  }.contains(name.toLowerCase());
}

List<WebHelperBrowserCookie> _dedupeCookies(
  List<WebHelperBrowserCookie> cookies,
) {
  final result = <String, WebHelperBrowserCookie>{};
  for (final cookie in cookies) {
    result[[cookie.domain ?? '', cookie.path ?? '', cookie.name].join('\x00')] =
        cookie;
  }
  return result.values.toList();
}

const _tokenKeyHints = {'token', 'access_token', 'auth_token', 'authorization'};

String? _extractTokenFromCookies(List<WebHelperBrowserCookie> cookies) {
  for (final cookie in cookies) {
    final name = cookie.name.toLowerCase();
    if (!_tokenKeyHints.contains(name) && !name.contains('token')) continue;
    final token = _normalizeTokenCandidate(cookie.value);
    if (token != null) return token;
  }
  return null;
}

String? _extractTokenFromMap(Map<dynamic, dynamic> values) {
  for (final entry in values.entries) {
    final key = entry.key.toString().toLowerCase();
    if (key.contains('token') || key.contains('authorization')) {
      final token = _extractTokenFromAny(entry.value, aggressive: true);
      if (token != null) return token;
    }
  }
  return null;
}

String? _extractTokenFromAny(dynamic value, {bool aggressive = false}) {
  if (value == null) return null;
  if (value is Map) {
    final byKey = _extractTokenFromMap(value);
    if (byKey != null) return byKey;
    if (!aggressive) return null;
    for (final entry in value.entries) {
      final token = _extractTokenFromAny(entry.value, aggressive: true);
      if (token != null) return token;
    }
    return null;
  }
  if (value is List) {
    for (final item in value) {
      final token = _extractTokenFromAny(item, aggressive: aggressive);
      if (token != null) return token;
    }
    return null;
  }
  final text = value.toString().trim();
  if (text.startsWith('{') || text.startsWith('[')) {
    try {
      return _extractTokenFromAny(jsonDecode(text), aggressive: true);
    } catch (_) {}
  }
  return _normalizeTokenCandidate(text);
}

String? _normalizeTokenCandidate(dynamic value) {
  if (value == null) return null;
  var token = value.toString().trim();
  if (token.isEmpty || token == 'null' || token == 'undefined') return null;
  try {
    token = Uri.decodeComponent(token);
  } catch (_) {}
  final lower = token.toLowerCase();
  if (lower.startsWith('token ')) {
    token = token.substring(6).trim();
  } else if (lower.startsWith('bearer ')) {
    token = token.substring(7).trim();
  }
  if (token.length < 16 || token.contains(RegExp(r'\s'))) return null;
  if (RegExp(r'''[{}\[\]"']''').hasMatch(token)) return null;
  return token;
}
