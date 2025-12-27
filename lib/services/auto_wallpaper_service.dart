import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

import 'package:deva_aura/services/favorite_service.dart';
import 'package:deva_aura/services/wallpaper_service.dart';
import 'package:deva_aura/utils/wallpaper_setter.dart';
import 'package:deva_aura/services/native_service.dart';

/// SharedPreferences keys
const String _kEnabledKey = 'auto_wallpaper_enabled';
const String _kSourceKey = 'auto_wallpaper_source';
const String _kCategoryIdKey = 'auto_wallpaper_category_id';
const String _kFrequencyMinKey = 'auto_wallpaper_frequency_minutes';
const String _kPoolKey = 'auto_wallpaper_pool_urls';
const String _kEnabledAtKey = 'auto_wallpaper_enabled_at_millis';
const String _kTargetKey = 'auto_wallpaper_target';
const String _kLockToneKey = 'auto_wallpaper_lock_tone';
const String _kUserIdKey = 'auto_wallpaper_user_id';
const String _kHasUsedBeforeKey = 'auto_wallpaper_has_used_before';
const String _kDayPoolsKey = 'auto_wallpaper_day_pools_json';

enum AutoWallpaperSource { favorites, category, random, dayWise }

class AutoWallpaperSettings {
  final bool enabled;
  final AutoWallpaperSource source;
  final String? categoryId;
  final int frequencyMinutes;
  final DateTime? enabledAt;
  final WallpaperScreenTarget target;
  final WallpaperColorTone lockTone;

  const AutoWallpaperSettings({
    required this.enabled,
    required this.source,
    required this.frequencyMinutes,
    required this.target,
    required this.lockTone,
    this.categoryId,
    this.enabledAt,
  });

  AutoWallpaperSettings copyWith({
    bool? enabled,
    AutoWallpaperSource? source,
    String? categoryId,
    int? frequencyMinutes,
    WallpaperScreenTarget? target,
    WallpaperColorTone? lockTone,
  }) {
    return AutoWallpaperSettings(
      enabled: enabled ?? this.enabled,
      source: source ?? this.source,
      categoryId: categoryId ?? this.categoryId,
      frequencyMinutes: frequencyMinutes ?? this.frequencyMinutes,
      target: target ?? this.target,
      lockTone: lockTone ?? this.lockTone,
      enabledAt: this.enabledAt,
    );
  }

  static Future<AutoWallpaperSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEnabledKey) ?? false;
    final sourceIndex =
        prefs.getInt(_kSourceKey) ?? AutoWallpaperSource.favorites.index;
    final frequency = prefs.getInt(_kFrequencyMinKey) ?? 60;
    final catId = prefs.getString(_kCategoryIdKey);
    final enabledAtMillis = prefs.getInt(_kEnabledAtKey);
    final enabledAt = enabledAtMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(enabledAtMillis, isUtc: true)
        : null;

    final source = AutoWallpaperSource
        .values[sourceIndex.clamp(0, AutoWallpaperSource.values.length - 1)];

    final targetIndex =
        prefs.getInt(_kTargetKey) ?? WallpaperScreenTarget.home.index;
    final lockToneIndex =
        prefs.getInt(_kLockToneKey) ?? WallpaperColorTone.normal.index;

    final target = WallpaperScreenTarget
        .values[targetIndex.clamp(0, WallpaperScreenTarget.values.length - 1)];
    final lockTone = WallpaperColorTone
        .values[lockToneIndex.clamp(0, WallpaperColorTone.values.length - 1)];

    return AutoWallpaperSettings(
      enabled: enabled,
      source: source,
      categoryId: catId,
      frequencyMinutes: frequency,
      enabledAt: enabledAt,
      target: target,
      lockTone: lockTone,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, enabled);
    await prefs.setInt(_kSourceKey, source.index);
    await prefs.setInt(_kFrequencyMinKey, frequencyMinutes);
    await prefs.setInt(_kTargetKey, target.index);
    await prefs.setInt(_kLockToneKey, lockTone.index);
    if (categoryId?.isNotEmpty == true) {
      await prefs.setString(_kCategoryIdKey, categoryId!);
    } else {
      await prefs.remove(_kCategoryIdKey);
    }
    if (enabled) {
      final existing = prefs.getInt(_kEnabledAtKey);
      if (existing == null) {
        await prefs.setInt(
            _kEnabledAtKey, DateTime.now().toUtc().millisecondsSinceEpoch);
      }
      // Save Debug Mode status for Native checking
      await prefs.setBool('auto_wallpaper_is_debug', kDebugMode);
    } else {
      await prefs.remove(_kEnabledAtKey);
      await prefs.remove('auto_wallpaper_is_debug');
    }
  }
}

class AutoWallpaperService {
  AutoWallpaperService._();
  static final AutoWallpaperService instance = AutoWallpaperService._();

  final FavoriteService _favoriteService = FavoriteService();
  final WallpaperService _wallpaperService = WallpaperService();

  Future<void> ensureInitialized() async {
    // [FIX] Ensure IsDebug flag is always up to date for Native Worker
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_wallpaper_is_debug', kDebugMode);

    _checkFallback();
  }

  Future<void> _checkFallback() async {
    try {
      final lastRun = await NativeService.instance.getLastWallpaperChangeTime();
      final settings = await AutoWallpaperSettings.load();
      if (settings.enabled) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final freqMillis = settings.frequencyMinutes * 60 * 1000;

        if (lastRun == null || (now - lastRun) > (freqMillis * 1.5)) {
          debugPrint(
              '[AutoWall] Fallback: Overdue or never run. Triggering immediate update.');
          await NativeService.instance.triggerNow();
        }
      }
    } catch (e) {
      debugPrint('[AutoWall] Fallback check failed: $e');
    }
  }

  Future<List<String>> refreshPool({String? currentUserId}) async {
    final settings = await AutoWallpaperSettings.load();
    final prefs = await SharedPreferences.getInstance();
    List<String> urls = [];
    try {
      if (currentUserId != null) {
        await prefs.setString(_kUserIdKey, currentUserId);
      } else {
        currentUserId = prefs.getString(_kUserIdKey);
      }

      if (settings.source == AutoWallpaperSource.favorites) {
        final favs =
            await _favoriteService.getFavoritesForUserOrGuest(currentUserId);
        final ids = favs.map((f) => f.wallpaperId).toList();
        final walls = await _wallpaperService.getWallpapersByIds(ids);
        urls = walls.map((w) => w.imageUrl).where((u) => u.isNotEmpty).toList();

        if (urls.isEmpty) {
          debugPrint(
              '[AutoWall] No favorites found. Falling back to Top Liked.');
          urls = await _fetchTopLiked();
        }
      } else if (settings.source == AutoWallpaperSource.category) {
        final catId = settings.categoryId;
        if (catId != null && catId.isNotEmpty) {
          debugPrint(
              '[AutoWall] Fetching wallpapers for category ID: $catId using WallpaperService...');
          try {
            // Unify logic: Use the same service as the UI
            final result = await _wallpaperService.getWallpapersPaginated(
              categoryId: catId,
              limit: 50, // Fetch a good batch
              sort: WallpaperSortOption.mostLiked, // Default to liked
            );

            urls = result.wallpapers
                .map((w) => w.imageUrl)
                .where((u) => u.isNotEmpty)
                .toList();

            debugPrint(
                '[AutoWall] WallpaperService returned ${result.wallpapers.length} items. Valid URLs: ${urls.length}');

            if (urls.isEmpty) {
              // Try fallback to Newest if Most Liked failed (though service handles index error partially, explicit check helps)
              debugPrint(
                  '[AutoWall] Primary fetch returned 0. Trying Newest sort...');
              final resultNewest =
                  await _wallpaperService.getWallpapersPaginated(
                categoryId: catId,
                limit: 50,
                sort: WallpaperSortOption.newest,
              );
              urls = resultNewest.wallpapers
                  .map((w) => w.imageUrl)
                  .where((u) => u.isNotEmpty)
                  .toList();
              debugPrint(
                  '[AutoWall] Fallback (Newest) returned ${urls.length} items.');
            }
          } catch (e) {
            debugPrint(
                '[AutoWall][Error] Failed to fetch category wallpapers via service: $e');
            // Last resort fallback: try raw query without sort
            try {
              debugPrint('[AutoWall] Attempting raw unsorted fallback...');
              final snap = await FirebaseFirestore.instance
                  .collection('wallpapers')
                  .where('categoryId', isEqualTo: catId)
                  .limit(50)
                  .get();
              urls = snap.docs
                  .map((d) => d.data()['imageUrl'] as String? ?? '')
                  .where((u) => u.isNotEmpty)
                  .toList();
              debugPrint(
                  '[AutoWall] Raw fallback returned ${urls.length} items.');
            } catch (e2) {
              debugPrint('[AutoWall][Error] Raw fallback failed: $e2');
            }
          }
        } else {
          debugPrint(
              '[AutoWall][Warn] Category ID is null or empty in settings.');
        }
      } else if (settings.source == AutoWallpaperSource.dayWise) {
        // [Opt] Fetch TODAY's pool immediately
        final weekday = DateTime.now().weekday;
        final dayNames = {
          1: 'Monday (Shiva)',
          2: 'Tuesday (Hanuman)',
          3: 'Wednesday (Ganesha)',
          4: 'Thursday (Vishnu)',
          5: 'Friday (Lakshmi)',
          6: 'Saturday (Hanuman/Shani)',
          7: 'Sunday (Surya)'
        };
        debugPrint(
            '[AutoWall] DayWise: Detected weekday $weekday (${dayNames[weekday]})');

        // [DEBUG] Capture details for diagnosis
        StringBuffer debugLog = StringBuffer();
        debugLog.writeln('Day: $weekday (${dayNames[weekday]})');

        urls = await _fetchDayPool(weekday, debugLog: debugLog);

        // Fire-and-forget full week refresh
        _refreshRemainingDaysInBackground();

        if (urls.isEmpty) {
          debugPrint('[AutoWall] Today pool empty. Fallback to random.');
          debugLog.writeln('Pool Empty. Fetching Top Liked (Random)...');
          urls = await _fetchTopLiked();
        } else {
          debugPrint('[AutoWall] Successfully found ${urls.length} images.');
        }

        // [DEBUG] SHow diagnosis to user if pool was empty or strict mode
        // For now, let's ALWAYS show it if looking for Hanuman (Tuesday) failed
        if (urls.isEmpty && weekday == 2) {
          // We can't show dialog here easily as it's background service capable
          // But valid validation happens in UI.
        }

        // Save the debug log to prefs for UI to show?
        if (debugLog.isNotEmpty) {
          prefs.setString('last_day_fetch_log', debugLog.toString());
        }
      } else {
        // Random
        urls = await _fetchTopLiked();
      }
    } catch (e, st) {
      debugPrint('[AutoWall][Warn] refreshPool failed: $e\n$st');
      return [];
    }

    // Shuffle main pool
    urls.shuffle();

    await prefs.setStringList(_kPoolKey, urls);
    debugPrint('[AutoWall] Pool refreshed with ${urls.length} urls.');
    return urls;
  }

  Future<bool> applyScheduling({bool preserveSchedule = false}) async {
    if (kIsWeb) return false;
    final settings = await AutoWallpaperSettings.load();

    if (!settings.enabled) {
      debugPrint('[AutoWall] Disabled; cancelling native work');
      return await NativeService.instance.stopAutoWallpaper();
    }

    final prefs = await SharedPreferences.getInstance();
    List<String> pool = prefs.getStringList(_kPoolKey) ?? [];

    if (pool.isEmpty) {
      pool = await refreshPool();
    }

    if (pool.isEmpty) {
      debugPrint('[AutoWall] Pool empty, cannot schedule.');
      return false;
    }

    // [FIX] Debug: Force 15 mins to catch 20-min expiry
    final minutes = kDebugMode ? 15 : settings.frequencyMinutes;
    final targetIndex = settings.target.index;
    final lockToneIndex = settings.lockTone.index;

    if (preserveSchedule) {
      await NativeService.instance.updatePool(pool);
      return true;
    }

    bool started = await NativeService.instance
        .startAutoWallpaper(minutes, pool, targetIndex, lockToneIndex);

    // FORCE IMMEDIATE TRIGGER unconditionally to support "Immediate Change" feature
    // even if scheduling periodic work failed or was skipped.
    debugPrint('[AutoWall] Triggering immediate update...');
    await NativeService.instance.triggerNow();

    return started;
  }

  Future<void> _refreshRemainingDaysInBackground() async {
    Future(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await _refreshDayWisePools(prefs);
      } catch (e) {
        debugPrint('[AutoWall] Background week refresh failed: $e');
      }
    });
  }

  Future<List<String>> _fetchDayPool(int day, {StringBuffer? debugLog}) async {
    List<String> keywords = [];

    // Mapping matches NotificationService
    switch (day) {
      case 1:
        keywords = ['Lord Shiva', 'Mahadev', 'Bholenath', 'Shiva'];
        break;
      case 2:
        keywords = ['Lord Hanuman', 'Bajrangbali', 'Hanuman'];
        break;
      case 3:
        keywords = ['Lord Ganesha', 'Ganpati', 'Ganesha'];
        break;
      case 4:
        keywords = [
          'Lord Vishnu',
          'Lord Krishna',
          'Khatu Shyam',
          'Sai Baba',
          'Krishna'
        ];
        break;
      case 5:
        keywords = ['Goddess Lakshmi', 'Goddess Durga', 'Maa Kali'];
        break;
      case 6:
        keywords = ['Lord Hanuman', 'Bajrangbali', 'Hanuman'];
        break;
      case 7:
        keywords = ['Lord Surya', 'Sun God', 'Surya Dev'];
        break;
    }

    debugLog?.writeln('Keywords: $keywords');

    try {
      final catSnap =
          await FirebaseFirestore.instance.collection('categories').get();
      final allCats = catSnap.docs;

      Set<String> targetCatIds = {};
      for (final cat in allCats) {
        final data = cat.data();
        final name = (data['name'] as String? ?? '').toLowerCase();

        if (name.isEmpty) continue;

        for (final k in keywords) {
          if (name.contains(k.toLowerCase())) {
            // Collect BOTH Document ID and Field ID (if different)
            targetCatIds.add(cat.id);
            final fieldId = data['id'] as String?;
            if (fieldId != null && fieldId.isNotEmpty) {
              targetCatIds.add(fieldId);
            }
            debugLog?.writeln(
                'Matched Cat: "${data['name']}" (ID: ${cat.id}, Field: $fieldId)');
          }
        }
      }

      List<String> dayUrls = [];
      if (targetCatIds.isNotEmpty) {
        debugLog?.writeln('Scanning ${targetCatIds.length} Category IDs...');
        // We iterate through all potential IDs.
        for (final cid in targetCatIds.take(10)) {
          QuerySnapshot wSnap;
          try {
            wSnap = await FirebaseFirestore.instance
                .collection('wallpapers')
                .where('categoryId', isEqualTo: cid)
                .orderBy('likesCount', descending: true)
                .limit(
                    100) // Checking for 100 images per category to cover a full day
                .get();
          } catch (e) {
            // Fallback for missing index
            wSnap = await FirebaseFirestore.instance
                .collection('wallpapers')
                .where('categoryId', isEqualTo: cid)
                .limit(100)
                .get();
          }
          if (wSnap.docs.isNotEmpty) {
            dayUrls.addAll(wSnap.docs.map((d) => d['imageUrl'] as String));
            debugLog?.writeln('Found ${wSnap.docs.length} via Cat=$cid');
          }
        }
      } else {
        debugLog?.writeln('No Categories matched keywords.');
      }

      if (dayUrls.isEmpty && keywords.isNotEmpty) {
        debugLog?.writeln('Cat failed. Trying Search...');
        // Try simple keywords first, then composite?
        // Let's try "Hanuman" directly
        for (final key in keywords) {
          // Skip long phrases for tag search if possible, or try them all
          // Actually, simple names are best for tags.
          if (key.contains(' '))
            continue; // Skip "Lord Hanuman", stick to "Hanuman"

          try {
            debugLog?.writeln('Searching tag: "$key"...');
            final searchResults = await _wallpaperService.searchWallpapers(key);
            if (searchResults.isNotEmpty) {
              dayUrls.addAll(searchResults
                  .map((w) => w.imageUrl)
                  .where((u) => u.isNotEmpty));
              debugLog?.writeln('Search "$key": Found ${searchResults.length}');
              if (dayUrls.length >= 50) break; // Found enough
            }
          } catch (e) {
            debugLog?.writeln('Search err: $e');
          }
        }

        // If still empty, try the original robust fallback (last keyword)
        if (dayUrls.isEmpty) {
          final searchKey = keywords.last;
          debugLog?.writeln('Fallback Search: "$searchKey"');
          final res = await _wallpaperService.searchWallpapers(searchKey);
          dayUrls.addAll(res.map((w) => w.imageUrl));
        }
      }

      if (dayUrls.isEmpty) {
        debugLog?.writeln('All attempts failed. Returning empty.');
        return [];
      }

      dayUrls.shuffle();
      return dayUrls;
    } catch (e) {
      debugLog?.writeln('Critical Error: $e');
      // Return empty, logic will fallback to Top Liked if this happens
      return [];
    }
  }

  Future<void> _refreshDayWisePools(SharedPreferences prefs) async {
    Map<String, List<String>> dayPools = {};
    try {
      debugPrint('[AutoWall] Refreshing weekly pools (1-7)...');
      for (int day = 1; day <= 7; day++) {
        final urls = await _fetchDayPool(day);
        if (urls.isNotEmpty) {
          dayPools[day.toString()] = urls;
        } else {
          // Fallback to random if day fetch fails completely
          dayPools[day.toString()] = (await _fetchTopLiked()).take(20).toList();
        }
      }
      await prefs.setString(_kDayPoolsKey, jsonEncode(dayPools));
      debugPrint('[AutoWall] Full Week Refreshed.');
    } catch (e) {
      debugPrint('[AutoWall] Full Week Refresh Failed: $e');
    }
  }

  Future<List<String>> _fetchTopLiked() async {
    try {
      final query = FirebaseFirestore.instance
          .collection('wallpapers')
          .orderBy('likesCount', descending: true)
          .limit(50);

      final snap = await query.get();
      final urls = snap.docs
          .map((d) => d.data()['imageUrl'] as String? ?? '')
          .where((u) => u.isNotEmpty)
          .toList();

      if (urls.isNotEmpty) {
        urls.shuffle();
        return urls;
      }
    } catch (e) {
      debugPrint(
          '[AutoWall] Top-liked query failed (possible missing index): $e');
    }

    try {
      final query =
          FirebaseFirestore.instance.collection('wallpapers').limit(50);
      final snap = await query.get();
      final urls = snap.docs
          .map((d) => d.data()['imageUrl'] as String? ?? '')
          .where((u) => u.isNotEmpty)
          .toList();
      urls.shuffle();
      return urls;
    } catch (e) {
      return [];
    }
  }

  Future<void> handlePostSave(AutoWallpaperSettings settings) async {}

  Future<bool> isFirstTimeUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kHasUsedBeforeKey) != true;
  }

  Future<void> markFirstTimeUserAsDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasUsedBeforeKey, true);
  }
}
