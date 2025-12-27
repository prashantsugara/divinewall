import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_wallpaper_manager/flutter_wallpaper_manager.dart'
    as wpm;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import 'package:deva_aura/utils/wallpaper_setter_stub.dart';

WallpaperSetter getWallpaperSetter() => _MobileWallpaperSetter();

class _MobileWallpaperSetter implements WallpaperSetter {
  @override
  Future<bool> setFromUrl(String imageUrl,
      {WallpaperApplyOptions options = const WallpaperApplyOptions()}) async {
    final bytes = await _downloadBytes(imageUrl);
    if (bytes == null) return false;
    return _setFromBytes(bytes, options: options);
  }

  @override
  Future<bool> setFromFile(String path,
      {WallpaperApplyOptions options = const WallpaperApplyOptions()}) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final bytes = await file.readAsBytes();
      return _setFromBytes(bytes, options: options);
    } catch (e) {
      debugPrint('[Wallpaper][Mobile][Error] setFromFile failed: $e');
      return false;
    }
  }

  Future<bool> _setFromBytes(Uint8List bytes,
      {required WallpaperApplyOptions options}) async {
    try {
      img.Image? decoded;
      var anySuccess = false;

      if (options.target != WallpaperScreenTarget.lock) {
        decoded ??= _decodeAndBake(bytes);
        final homeFile = await _writeTempFile(
          bytes,
          decodedCache: decoded,
          suffix: '_home',
          target: _WallpaperProcessingTarget.home,
        );
        final size = await homeFile.length();
        debugPrint(
            '[Wallpaper][Mobile] Prepared home file: ${homeFile.path} (size: $size bytes)');

        if (size == 0) {
          debugPrint(
              '[Wallpaper][Mobile][Error] Home file is empty! Aborting apply.');
          anySuccess = false;
        } else {
          final applied = await _applyWallpaper(
              homeFile.path, wpm.WallpaperManager.HOME_SCREEN);
          debugPrint('[Wallpaper][Mobile] Home apply result: $applied');
          anySuccess = anySuccess || applied;
        }
      }

      if (options.target != WallpaperScreenTarget.home) {
        decoded ??= _decodeAndBake(bytes);
        final lockFile = await _writeTempFile(
          bytes,
          decodedCache: decoded,
          suffix: options.lockColorTone == WallpaperColorTone.blackAndWhite
              ? '_lock_bw'
              : '_lock',
          target: _WallpaperProcessingTarget.lock,
          grayscale: options.lockColorTone == WallpaperColorTone.blackAndWhite,
        );
        debugPrint('[Wallpaper][Mobile] Prepared lock file: ${lockFile.path}');
        final applied = await _applyWallpaper(
            lockFile.path, wpm.WallpaperManager.LOCK_SCREEN);
        debugPrint('[Wallpaper][Mobile] Lock apply result: $applied');
        anySuccess = anySuccess || applied;
      }

      return anySuccess;
    } catch (e, st) {
      debugPrint('[Wallpaper][Mobile][Error] setFromBytes failed: $e\n$st');
      return false;
    }
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    try {
      // Use CacheManager to support offline mode if image was previously fetched
      final file = await DefaultCacheManager().getSingleFile(url);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (e, st) {
      debugPrint(
          '[Wallpaper][Mobile][Error] Download/Cache failed for $url: $e');
      return null;
    }
  }

  Future<File> _writeTempFile(
    Uint8List bytes, {
    String suffix = '',
    bool grayscale = false,
    _WallpaperProcessingTarget target = _WallpaperProcessingTarget.home,
    img.Image? decodedCache,
  }) async {
    try {
      final preparedBytes = _prepareBytes(
        bytes,
        grayscale: grayscale,
        target: target,
        decodedCache: decodedCache,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}$suffix.jpg');
      await file.writeAsBytes(preparedBytes);
      return file;
    } catch (e, st) {
      debugPrint(
          '[Wallpaper][Mobile][Error] Failed to write temp file: $e\n$st');
      rethrow;
    }
  }

  Uint8List _prepareBytes(
    Uint8List bytes, {
    bool grayscale = false,
    _WallpaperProcessingTarget target = _WallpaperProcessingTarget.home,
    img.Image? decodedCache,
  }) {
    try {
      final decoded = decodedCache ?? _decodeAndBake(bytes);
      if (decoded == null) return bytes;

      img.Image processed = decoded;
      if (target == _WallpaperProcessingTarget.lock) {
        processed = _centerCropToScreenAspect(processed);
      }

      if (grayscale) {
        processed = img.grayscale(processed);
      }

      final quality = grayscale ? 90 : 95;
      return Uint8List.fromList(img.encodeJpg(processed, quality: quality));
    } catch (e, st) {
      debugPrint(
          '[Wallpaper][Mobile][Warn] Failed to prepare bytes (grayscale=$grayscale target=$target): $e\n$st');
      return bytes;
    }
  }

  img.Image? _decodeAndBake(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      return img.bakeOrientation(decoded);
    } catch (e, st) {
      debugPrint(
          '[Wallpaper][Mobile][Warn] Failed to decode for orientation bake: $e\n$st');
      return null;
    }
  }

  img.Image _centerCropToScreenAspect(img.Image image) {
    final ratio = _WallpaperScreenMetrics.instance.aspectRatio;
    if (ratio == null || ratio <= 0) return image;

    final imgRatio = image.width / image.height;
    if ((imgRatio - ratio).abs() < 0.005) return image;

    if (imgRatio > ratio) {
      final targetWidth = math.max(1, (image.height * ratio).round());
      if (targetWidth >= image.width) return image;
      final dx = ((image.width - targetWidth) / 2).round();
      final safeDx = dx.clamp(0, image.width - targetWidth).toInt();
      return img.copyCrop(image,
          x: safeDx, y: 0, width: targetWidth, height: image.height);
    }

    final targetHeight = math.max(1, (image.width / ratio).round());
    if (targetHeight >= image.height) return image;
    final dy = ((image.height - targetHeight) / 2).round();
    final safeDy = dy.clamp(0, image.height - targetHeight).toInt();
    return img.copyCrop(image,
        x: 0, y: safeDy, width: image.width, height: targetHeight);
  }

  Future<bool> _applyWallpaper(String path, int location) async {
    try {
      debugPrint(
          '[Wallpaper][Mobile] Applying wallpaper file: $path to location: $location');
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('[Wallpaper][Mobile][Error] File does not exist at $path');
        return false;
      }

      final res =
          await wpm.WallpaperManager.setWallpaperFromFile(path, location);
      debugPrint(
          '[Wallpaper][Mobile] setWallpaperFromFile($location) returned: $res');
      return res;
    } catch (e, st) {
      debugPrint(
          '[Wallpaper][Mobile][Error] Failed to apply wallpaper: $e\n$st');
      return false;
    }
  }
}

class _WallpaperScreenMetrics {
  _WallpaperScreenMetrics._();
  static final _WallpaperScreenMetrics instance = _WallpaperScreenMetrics._();

  double? _aspectRatio;
  double? get aspectRatio => _aspectRatio ??= _computeAspectRatio();

  double? _computeAspectRatio() {
    const fallbackRatio = 9 / 16; // Portrait default
    try {
      final dispatcher = ui.PlatformDispatcher.instance;
      final view = dispatcher.views.isNotEmpty
          ? dispatcher.views.first
          : dispatcher.implicitView;
      final size = view?.physicalSize;
      if (size == null || size.height == 0) {
        debugPrint(
            '[Wallpaper][Mobile][Warn] No Flutter view available for aspect ratio; using fallback');
        return fallbackRatio;
      }
      final ratio = size.width / size.height;
      if (ratio.isFinite && ratio > 0) {
        return ratio;
      }
      debugPrint(
          '[Wallpaper][Mobile][Warn] Invalid screen ratio ($ratio); using fallback');
      return fallbackRatio;
    } catch (e, st) {
      debugPrint(
          '[Wallpaper][Mobile][Warn] Unable to read screen aspect ratio: $e\n$st');
      return fallbackRatio;
    }
  }
}

enum _WallpaperProcessingTarget { home, lock }
