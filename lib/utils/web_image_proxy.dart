import 'package:flutter/foundation.dart';

/// Provides a best-effort web fallback for images hosted on domains that may
/// be blocked by CSP or fail CORS preflight when fetched by Flutter web.
///
/// We attempt to proxy Firebase Storage download URLs via a public image proxy
/// on web only. Native/mobile platforms will always use the direct URL.
class WebImageProxy {
  /// Return a URL suitable for display in Image.network on web.
  /// - If not web, returns [url].
  /// - If the host is firebasestorage.googleapis.com, returns a proxied URL
  ///   via images.weserv.nl, otherwise returns [url].
  static String displayUrl(String url) {
    if (!kIsWeb) return url;
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (host.contains('firebasestorage.googleapis.com')) {
        // images.weserv.nl expects a host/path without protocol. To force HTTPS,
        // we prefix with 'ssl:' per their docs. Keep query parameters intact.
        final pathWithQuery = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
        final noScheme = 'ssl:${uri.host}$pathWithQuery';
        final encoded = Uri.encodeComponent(noScheme);
        // Use images.weserv.nl as a transparent proxy for <img> loading.
        // It supports HTTPS and caches responses.
        return 'https://images.weserv.nl/?url=$encoded';
      }
      return url;
    } catch (_) {
      return url;
    }
  }
}
