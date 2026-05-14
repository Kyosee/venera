import 'dart:convert';

const corsProxyUserAgentHeader = 'X-Venera-User-Agent';
const corsProxyCookieHeader = 'X-Venera-Cookie';
const corsProxyRefererHeader = 'X-Venera-Referer';
const corsProxyOriginHeader = 'X-Venera-Origin';
const corsProxyForwardHeadersHeader = 'X-Venera-Forward-Headers';

const _sourceHeaderMetadata = {
  'user-agent': corsProxyUserAgentHeader,
  'cookie': corsProxyCookieHeader,
  'referer': corsProxyRefererHeader,
  'origin': corsProxyOriginHeader,
};

const _proxyMetadataHeaders = {
  'x-venera-user-agent',
  'x-venera-cookie',
  'x-venera-referer',
  'x-venera-origin',
  'x-venera-forward-headers',
};

const _neverForwardSourceHeaders = {
  'accept-charset',
  'accept-encoding',
  'access-control-request-headers',
  'access-control-request-method',
  'connection',
  'content-length',
  'date',
  'dnt',
  'expect',
  'host',
  'keep-alive',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
  'via',
};

const _neverForwardSourceHeaderPrefixes = {'proxy-', 'sec-'};

String? normalizeCorsProxyEndpoint(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;

  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return raw;

  final path = uri.path.endsWith('/') && uri.path.length > 1
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  final segments = path.split('/').where((e) => e.isNotEmpty).toList();
  final lastSegment = segments.isEmpty ? null : segments.last;
  if (lastSegment == 'proxy' || lastSegment == 'proxy.php') {
    return uri.replace(path: path.isEmpty ? uri.path : path).toString();
  }

  final normalizedPath = path.isEmpty || path == '/' ? '/proxy' : '$path/proxy';
  return uri.replace(path: normalizedPath).toString();
}

String? resolveCorsProxyEndpoint({
  String? explicitEndpoint,
  bool useSameOriginDefault = false,
  Uri? currentUri,
}) {
  final explicit = normalizeCorsProxyEndpoint(explicitEndpoint);
  if (explicit != null) return explicit;
  if (!useSameOriginDefault) return null;

  final uri = currentUri ?? Uri.base;
  if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
    return null;
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  return normalizeCorsProxyEndpoint('${uri.scheme}://${uri.host}$port');
}

String buildCorsProxyUrl(String endpoint, Uri target) {
  final separator = endpoint.contains('?') ? '&' : '?';
  return '$endpoint${separator}url=${Uri.encodeComponent(target.toString())}';
}

String buildHelperRouteUrl(String proxyEndpoint, String route) {
  final uri = Uri.parse(proxyEndpoint);
  final routeSegments = route
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList();
  final segments = uri.pathSegments.where((e) => e.isNotEmpty).toList();
  if (segments.isNotEmpty &&
      (segments.last == 'proxy' || segments.last == 'proxy.php')) {
    segments.removeLast();
  }
  segments.addAll(routeSegments);
  return uri.replace(pathSegments: segments).toString();
}

void preserveCorsProxySourceHeaders(Map<String, dynamic> headers) {
  final originalKeys = headers.keys.map((e) => e.toString()).toList();
  final forwardHeaderNames = <String>[];

  for (final key in originalKeys) {
    final lower = key.toLowerCase();
    final metadataHeader = _sourceHeaderMetadata[lower];
    if (metadataHeader != null) {
      final value = _removeHeaderCaseInsensitive(headers, lower);
      if (value != null && value.toString().isNotEmpty) {
        headers[metadataHeader] = value;
      }
      continue;
    }
    if (_shouldForwardSourceHeader(lower)) {
      forwardHeaderNames.add(key);
    }
  }

  if (forwardHeaderNames.isNotEmpty) {
    headers[corsProxyForwardHeadersHeader] = jsonEncode(forwardHeaderNames);
  }
}

List<String> decodeCorsProxyForwardHeaderNames(Object? value) {
  if (value == null) return const [];
  if (value is Iterable) {
    return value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
  final raw = value.toString();
  if (raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Iterable) {
      return decoded
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    }
  } catch (_) {
    // Older helper builds accept comma-separated names; keep decoder tolerant.
  }
  return raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

bool _shouldForwardSourceHeader(String lower) {
  return !_sourceHeaderMetadata.containsKey(lower) &&
      !_proxyMetadataHeaders.contains(lower) &&
      !_neverForwardSourceHeaders.contains(lower) &&
      !_neverForwardSourceHeaderPrefixes.any(lower.startsWith);
}

dynamic _removeHeaderCaseInsensitive(
  Map<String, dynamic> headers,
  String lowerName,
) {
  dynamic result;
  final keys = headers.keys.map((e) => e.toString()).toList();
  for (final key in keys) {
    if (key.toLowerCase() == lowerName) {
      result = headers.remove(key) ?? result;
    }
  }
  return result;
}
