import 'dart:typed_data';
import 'dart:io' show Platform, File;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:deva_aura/utils/image_url_utils.dart';
import 'package:deva_aura/utils/web_image_proxy.dart';
// Keeping Android simple: FileSaver saves to Downloads by default on Android Q+.
// App share link is resolved internally to avoid extra dependencies.

class ShareDownloadUtils {
  /// Share the image as a real file attachment, plus a deep link to the app.
  /// Falls back to text-only share if file attach fails.
  static Future<void> shareImageFileWithAppLink({
    required String imageUrl,
    String? title,
    String? appLink, // If null, uses AppLinks.appShareLink()
    BuildContext? context,
  }) async {
    try {
      final safeUrl = ImageUrlUtils.sanitize(imageUrl);
      // On web, fetch through a proxy for better CORS compatibility
      final effectiveUrl = kIsWeb ? WebImageProxy.displayUrl(safeUrl) : safeUrl;
      final uri = Uri.parse(effectiveUrl);
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final bytes = Uint8List.fromList(res.bodyBytes);
      // Prefer a readable filename from title; otherwise, infer from URL
      final suggestedFromUrl = ImageUrlUtils.inferFileName(safeUrl);
      final baseName = _safeFileNameFromTitle(title) ?? suggestedFromUrl;
      final mimeStr = _inferMimeStringFromUrl(safeUrl);

      final xfile = XFile.fromData(
        bytes,
        name: baseName,
        mimeType: mimeStr,
      );

      final link = appLink?.trim().isNotEmpty == true
          ? appLink!.trim()
          : _appShareLink();
      // Per requirement: when sharing a wallpaper, include only the app link in the text
      final shareText = link.isNotEmpty ? 'Get the app: $link' : '';

      await Share.shareXFiles(
        [xfile],
        text: shareText,
      );
    } catch (e) {
      debugPrint(
          '[Share] File share failed, falling back to link text. Error: $e');
      // Fallback: share text with link and image URL
      await shareImageUrl(imageUrl: imageUrl, title: null, context: context);
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shared link only due to file share limitation'),
            duration: Duration(milliseconds: 1500),
          ),
        );
      }
    }
  }

  static Future<void> shareImageUrl({
    required String imageUrl,
    String? title,
    BuildContext? context,
  }) async {
    try {
      final link = _appShareLink();
      // Per requirement: share only the app link in text (no filename, no image url)
      final text = link.isNotEmpty ? 'Get the app: $link' : imageUrl;
      await Share.share(text);
    } catch (e) {
      debugPrint('[Share] Failed to share: $e');
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share image: $e'),
            duration: const Duration(milliseconds: 1500),
          ),
        );
      }
    }
  }

  static Future<bool> downloadImage({
    required String imageUrl,
    String? suggestedName,
    BuildContext? context,
  }) async {
    try {
      final safeUrl = ImageUrlUtils.sanitize(imageUrl);
      // On web, fetch through a proxy for better CORS compatibility
      final effectiveUrl = kIsWeb ? WebImageProxy.displayUrl(safeUrl) : safeUrl;
      final uri = Uri.parse(effectiveUrl);
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final bytes = Uint8List.fromList(res.bodyBytes);
      final fname = suggestedName ?? ImageUrlUtils.inferFileName(safeUrl);
      final mime = _inferMimeFromUrl(safeUrl);

      // Android/iOS: insert into system Gallery/Photos using gal
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          // Request access on platforms that need it (Android 13+/iOS Photos)
          final hasAccess = await Gal.hasAccess();
          if (!hasAccess) {
            await Gal.requestAccess();
          }

          // Save to an album so it shows under a named folder in gallery apps
          await Gal.putImageBytes(
            bytes,
            album: 'DivineWall',
            name: fname,
          );
        } catch (e) {
          debugPrint(
              '[Download][Mobile] Gallery save via gal failed, falling back to FileSaver: $e');
          await FileSaver.instance.saveFile(
            name: fname,
            bytes: bytes,
            mimeType: mime,
          );
        }
      } else {
        // Default: save with FileSaver (web/iOS/others)
        await FileSaver.instance.saveFile(
          name: fname,
          bytes: bytes,
          mimeType: mime,
        );
      }

      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                  ? 'Saved to Gallery'
                  : 'Image saved',
            ),
            duration: const Duration(milliseconds: 1500),
          ),
        );
      }
      return true;
    } catch (e) {
      debugPrint('[Download] Failed: $e');
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save image: $e'),
            duration: const Duration(milliseconds: 1500),
          ),
        );
      }
      return false;
    }
  }

  static MimeType _inferMimeFromUrl(String url) {
    final lower = url.toLowerCase();
    // Respect explicit fm query when present
    try {
      final uri = Uri.parse(url);
      final fm = uri.queryParameters['fm']?.toLowerCase();
      if (fm == 'png') return MimeType.png;
      if (fm == 'webp') return MimeType.webp;
      if (fm == 'gif') return MimeType.gif;
    } catch (_) {}
    if (lower.endsWith('.png')) return MimeType.png;
    if (lower.endsWith('.webp')) return MimeType.webp;
    if (lower.endsWith('.gif')) return MimeType.gif;
    return MimeType.jpeg;
  }

  static String _inferMimeStringFromUrl(String url) {
    final lower = url.toLowerCase();
    try {
      final uri = Uri.parse(url);
      final fm = uri.queryParameters['fm']?.toLowerCase();
      if (fm == 'png') return 'image/png';
      if (fm == 'webp') return 'image/webp';
      if (fm == 'gif') return 'image/gif';
    } catch (_) {}
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  static String? _safeFileNameFromTitle(String? title) {
    if (title == null || title.trim().isEmpty) return null;
    final base = title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    // Ensure an extension; prefer jpg unless title clearly hints png/webp
    if (base.endsWith('.png') ||
        base.endsWith('.jpg') ||
        base.endsWith('.jpeg') ||
        base.endsWith('.webp')) {
      return base;
    }
    return '$base.jpg';
  }

  static String _composeShareText(
      {String? title, String? link, String? extra}) {
    final pieces = <String>[];
    if (title != null && title.trim().isNotEmpty) pieces.add(title.trim());
    if (link != null && link.trim().isNotEmpty)
      pieces.add('Get the app: ${link.trim()}');
    if (extra != null && extra.trim().isNotEmpty) pieces.add(extra.trim());
    return pieces.join('\n');
  }

  // --- App deep link helpers ---
  // Optionally set these to store or dynamic links after publishing.
  // Use the provided Play Store link across shares
  static const String _androidStoreUrl =
      'https://play.google.com/store/apps/details?id=com.bittruth.gwallpaper';
  static const String _iosStoreUrl = '';
  // For web shares, also point to the same Play Store listing by default
  static const String _webAppUrl =
      'https://play.google.com/store/apps/details?id=com.bittruth.gwallpaper';

  static String _appShareLink() {
    if (kIsWeb) {
      if (_webAppUrl.isNotEmpty) return _webAppUrl;
      return Uri.base.origin; // Dreamflow preview domain by default
    }
    if (defaultTargetPlatform == TargetPlatform.android &&
        _androidStoreUrl.isNotEmpty) {
      return _androidStoreUrl;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        _iosStoreUrl.isNotEmpty) {
      return _iosStoreUrl;
    }
    if (_webAppUrl.isNotEmpty) return _webAppUrl;
    return '';
  }

  /// Share the app link directly (used by Home screen app bar action)
  static Future<void> shareAppLink({BuildContext? context}) async {
    try {
      final link = _appShareLink();
      final text = link.isNotEmpty ? 'Get the app: $link' : '';
      if (text.isEmpty) return;
      await Share.share(text);
    } catch (e) {
      debugPrint('[Share] Failed to share app link: $e');
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share app link: $e'),
            duration: const Duration(milliseconds: 1500),
          ),
        );
      }
    }
  }
}
