import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class NativeService {
  NativeService._();
  static final NativeService instance = NativeService._();

  static const _channel = MethodChannel('com.bittruth.gwallpaper/auto_wall');

  /// Starts the auto wallpaper worker with the given [frequencyMinutes] and [urls].
  /// On Android, this schedules a WorkManager task.
  /// [targetIndex]: 0=Home, 1=Lock, 2=Both (matches WallpaperScreenTarget enum)
  /// [lockToneIndex]: 0=Normal, 1=BlackAndWhite (matches WallpaperColorTone enum)
  Future<bool> startAutoWallpaper(int frequencyMinutes, List<String> urls,
      int targetIndex, int lockToneIndex) async {
    try {
      debugPrint(
          '[NativeService] Sending ${urls.length} URLs to Android: ${urls.take(3).toList()}...');
      final result = await _channel.invokeMethod('startAutoWallpaper', {
        'frequency': frequencyMinutes,
        'urls': urls,
        'target': targetIndex,
        'lock_tone': lockToneIndex,
      });
      debugPrint('[NativeService] startAutoWallpaper result: $result');
      return result == true;
    } catch (e) {
      debugPrint('[NativeService] startAutoWallpaper failed: $e');
      return false;
    }
  }

  /// Stops the auto wallpaper worker.
  Future<bool> stopAutoWallpaper() async {
    try {
      final result = await _channel.invokeMethod('stopAutoWallpaper');
      return result == true;
    } catch (e) {
      debugPrint('[NativeService] stopAutoWallpaper failed: $e');
      return false;
    }
  }

  /// Updates the pool of URLs without changing the schedule.
  Future<bool> updatePool(List<String> urls) async {
    try {
      debugPrint(
          '[NativeService] Updating pool with ${urls.length} URLs: ${urls.take(3).toList()}...');
      final result = await _channel.invokeMethod('updatePool', {'urls': urls});
      debugPrint('[NativeService] updatePool result: $result');
      return result == true;
    } catch (e) {
      debugPrint('[NativeService] updatePool failed: $e');
      return false;
    }
  }

  /// Triggers an immediate wallpaper update via Native worker.
  Future<bool> triggerNow() async {
    try {
      final result = await _channel.invokeMethod('triggerNow');
      return result == true;
    } catch (e) {
      debugPrint('[NativeService] triggerNow failed: $e');
      return false;
    }
  }

  /// Returns the last time (millis) the wallpaper was changed by the worker.
  Future<int?> getLastWallpaperChangeTime() async {
    try {
      final result = await _channel.invokeMethod('getLastWallpaperChangeTime');
      return result as int?;
    } catch (e) {
      debugPrint('[NativeService] getLastWallpaperChangeTime failed: $e');
      return null;
    }
  }

  /// Requests the system to ignore battery optimizations for this app.
  /// Returns true if the request intent was launched successfully.
  Future<bool> requestBatteryOptimization() async {
    try {
      final result = await _channel.invokeMethod('requestBatteryOptimization');
      return result == true;
    } catch (e) {
      debugPrint('[NativeService] requestBatteryOptimization failed: $e');
      return false;
    }
  }

  /// Triggers the native expiry notification for testing.
  Future<bool> testExpiryNotification() async {
    try {
      final result = await _channel.invokeMethod('testExpiryNotification');
      return result == true;
    } catch (e) {
      debugPrint('[NativeService] testExpiryNotification failed: $e');
      return false;
    }
  }

  Future<String?> checkLaunchPayload() async {
    try {
      final result = await _channel.invokeMethod('checkLaunchPayload');
      return result as String?;
    } catch (e) {
      debugPrint('[NativeService] checkLaunchPayload failed: $e');
      return null;
    }
  }
}
