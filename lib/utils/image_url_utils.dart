/// Utilities to normalize/sanitize image URLs for better web compatibility.
class ImageUrlUtils {
  /// Ensures remote image URLs resolve to broadly supported formats on web.
  /// - Unsplash: force JPEG fallback (fm=jpg) to avoid AVIF/WEBP decode issues
  /// - Preserves existing query params (like size w=..)
  static String sanitize(String url) {
    try {
      final uri = Uri.parse(url);
      // Only transform known hosts where format negotiation might break decoding
      if (uri.host.contains('images.unsplash.com')) {
        final qp = Map<String, String>.from(uri.queryParameters);
        // If caller already specified format, respect it
        qp.putIfAbsent('fm', () => 'jpg');
        // Quality reasonable default if not present
        qp.putIfAbsent('q', () => '85');
        final sanitized = uri.replace(queryParameters: qp).toString();
        return sanitized;
      }
      return url;
    } catch (_) {
      return url;
    }
  }

  /// Try to infer a filename that matches the most likely format after sanitation.
  static String inferFileName(String url, {String fallback = 'wallpaper.jpg'}) {
    try {
      final sanitized = sanitize(url);
      final uri = Uri.parse(sanitized);
      String base =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.last : fallback;
      // If no extension, pick one based on hints
      if (!base.contains('.')) {
        final fm = uri.queryParameters['fm'];
        if (fm == 'png') return '${base}.png';
        if (fm == 'webp') return '${base}.webp';
        return '${base}.jpg';
      }
      return base;
    } catch (_) {
      return fallback;
    }
  }
}
