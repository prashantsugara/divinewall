import 'dart:io' show Platform;
import 'dart:async';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart'; // [FIX] Added import

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;

import 'package:deva_aura/main.dart'; // For navigatorKey
import 'package:deva_aura/services/category_service.dart';
import 'package:deva_aura/services/native_service.dart'; // [FIX] Added import
import 'package:deva_aura/screens/wallpaper_list_screen.dart';
import 'package:deva_aura/screens/auto_wallpaper_settings_screen.dart';

/// Top-level background handler. Must be a global function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    debugPrint(
        '[FCM][BG] title="${message.notification?.title}" body="${message.notification?.body}" data=${message.data}');
  } catch (e) {
    debugPrint('[FCM][BG][Err] $e');
  }
}

class NotificationService with WidgetsBindingObserver {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  bool _initialized = false;
  final fln.FlutterLocalNotificationsPlugin _fln =
      fln.FlutterLocalNotificationsPlugin();
  static const int _expiryReminderId = 880071;
  String? pendingPayload;

  final _notificationStreamController = StreamController<String?>.broadcast();
  Stream<String?> get onNotificationClick =>
      _notificationStreamController.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[Notif] App resumed - checking payload');
      consumePendingPayload();
    }
  }

  Future<void> init() async {
    if (_initialized) return;

    WidgetsBinding.instance.addObserver(this);

    tz.initializeTimeZones();
    // [FIX] Set local timezone from device (flutter_timezone)
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      debugPrint(
          '[Notif] Timezone initialized: $timeZoneName (Current: ${tz.TZDateTime.now(tz.local)})');
    } catch (e) {
      debugPrint('[Notif] Failed to get local timezone: $e');
    }

    debugPrint('[FCM] init(kIsWeb=$kIsWeb)');

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('[FCM][Warn] Failed to register background handler: $e');
    }

    await _ensurePermissions();

    try {
      const fln.AndroidInitializationSettings androidInit =
          fln.AndroidInitializationSettings('@mipmap/ic_launcher');
      const fln.DarwinInitializationSettings iosInit =
          fln.DarwinInitializationSettings();
      const fln.InitializationSettings initSettings =
          fln.InitializationSettings(
              android: androidInit, iOS: iosInit, macOS: null);

      await _fln.initialize(initSettings,
          onDidReceiveNotificationResponse: (fln.NotificationResponse resp) {
        debugPrint(
            '[LocalNotif] tapped: id=${resp.id} payload=${resp.payload}');
        if (resp.payload != null) {
          // Direct handling via Global Navigator
          _handleNotificationTap(resp.payload);
          // Keep stream for legacy listeners
          instance._notificationStreamController.add(resp.payload);
        }
      });

      // Cold Start check
      final details = await _fln.getNotificationAppLaunchDetails();
      if (details != null &&
          details.didNotificationLaunchApp &&
          details.notificationResponse?.payload != null) {
        final p = details.notificationResponse?.payload;
        debugPrint('[LocalNotif] Cold Start Payload: $p');
        pendingPayload = p;
      }

      // [FIX] Check for Native Notification Launch (NativeService)
      try {
        final nativePayload = await NativeService.instance.checkLaunchPayload();
        if (nativePayload != null && nativePayload.isNotEmpty) {
          debugPrint('[LocalNotif] Native Launch Payload: $nativePayload');
          // Prioritize Native Payload if LocalNotif didn't find one
          pendingPayload ??= nativePayload;
        }
      } catch (e) {
        debugPrint('[LocalNotif] Native payload check error: $e');
      }
    } catch (e) {
      debugPrint('[LocalNotif][Warn] init failed: $e');
    }

    try {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint(
          '[FCM][Warn] setForegroundNotificationPresentationOptions failed: $e');
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        await FirebaseMessaging.instance.setAutoInitEnabled(true);
      } catch (e) {
        debugPrint('[FCM][Android][Warn] setAutoInitEnabled failed: $e');
      }
    }

    String? token;
    if (!kIsWeb) {
      try {
        token = await FirebaseMessaging.instance
            .getToken()
            .timeout(const Duration(seconds: 6));
        debugPrint('[FCM] Token: $token');
      } on TimeoutException catch (_) {
        debugPrint(
            '[FCM][Warn] getToken timed out (likely no Play Services / offline)');
      } catch (e) {
        debugPrint('[FCM][Warn] getToken failed: $e');
      }
    }

    if (!kIsWeb) {
      if (token != null && token.isNotEmpty) {
        try {
          await FirebaseMessaging.instance
              .subscribeToTopic('all')
              .timeout(const Duration(seconds: 6));
          debugPrint('[FCM] Subscribed to topic "all"');
        } on TimeoutException catch (_) {
          debugPrint(
              '[FCM][Warn] subscribeToTopic timed out; will skip to avoid blocking');
        } catch (e) {
          debugPrint('[FCM][Warn] subscribeToTopic failed: $e');
        }
      }
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint(
          '[FCM][FG] title="${message.notification?.title}" body="${message.notification?.body}" data=${message.data}');
    }, onError: (e, st) {
      debugPrint('[FCM][FG][Err] $e\n$st');
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
          '[FCM][Open] Opened from notification with data=${message.data}');
    }, onError: (e, st) {
      debugPrint('[FCM][Open][Err] $e\n$st');
    });

    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        debugPrint(
            '[FCM][Initial] App opened from terminated via notification. data=${initial.data}');
      }
    } catch (e) {
      debugPrint('[FCM][Warn] getInitialMessage failed: $e');
    }

    _initialized = true;
  }

  /// Centralized handler for notification taps
  Future<void> _handleNotificationTap(String? payload) async {
    if (payload == null) {
      debugPrint('[Notif] Payload is null, ignoring.');
      return;
    }
    debugPrint('[Notif] Handling tap payload: "$payload"');

    if (payload.startsWith('category:')) {
      final parts = payload.split(':');
      if (parts.length < 2) {
        debugPrint('[Notif][Err] Invalid category payload format');
        return;
      }
      final catId = parts[1];
      debugPrint('[Notif] Fetching category for ID: $catId');

      try {
        final category = await CategoryService().getCategory(catId);
        if (category != null) {
          debugPrint('[Notif] Category found: ${category.name}. Navigating...');
          final nav = navigatorKey.currentState;
          if (nav != null) {
            // [Fix] Use pushAndRemoveUntil or just push? Push is fine.
            // Using a unique route name/settings can help debugging
            await nav.push(
              MaterialPageRoute(
                settings: RouteSettings(name: 'WallpaperListScreen_$catId'),
                builder: (_) => WallpaperListScreen(category: category),
              ),
            );
            debugPrint('[Notif] Navigation pushed.');
          } else {
            debugPrint(
                '[Notif][Warn] NavigatorState is NULL! App might be terminating or in weird state.');
            pendingPayload = payload;
          }
        } else {
          debugPrint('[Notif][Warn] Category NOT found for ID: $catId');
          final nav = navigatorKey.currentState;
          if (nav != null && nav.mounted) {
            showDialog(
              context: nav.context,
              builder: (ctx) => AlertDialog(
                title: const Text('Content Unavailable'),
                content: const Text(
                    'The category for this notification is no longer available.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('OK')),
                ],
              ),
            );
          }
        }
      } catch (e, st) {
        debugPrint('[Notif][Err] Navigation/Fetch failed: $e\n$st');
      }
    } else if (payload == 'auto_wallpaper_expired') {
      // ... (existing logic)
      final nav = navigatorKey.currentState;
      if (nav != null) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => const AutoWallpaperSettingsScreen(),
          ),
        );
      }
    } else {
      debugPrint('[Notif] Unknown payload type: $payload');
    }
  }

  Future<void> consumePendingPayload() async {
    if (pendingPayload != null) {
      debugPrint('[Notif] Consuming pending payload: $pendingPayload');
      final p = pendingPayload;
      pendingPayload = null;
      // Small delay to ensure navigator frames are ready if called from initState
      await Future.delayed(
          const Duration(milliseconds: 1000)); // Increased delay
      await _handleNotificationTap(p);
    } else {
      // Re-check Native just in case we missed it earlier
      try {
        final native = await NativeService.instance.checkLaunchPayload();
        if (native != null && native.isNotEmpty) {
          debugPrint('[Notif] Found Late Native Payload: $native');
          await _handleNotificationTap(native);
        }
      } catch (e) {/* ignore */}
    }
  }

  Future<void> _ensurePermissions() async {
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      try {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );
        debugPrint(
            '[FCM][iOS] Permission: alert=${settings.alert} badge=${settings.badge} sound=${settings.sound} status=${settings.authorizationStatus}');
      } catch (e) {
        debugPrint('[FCM][iOS][Warn] requestPermission failed: $e');
      }
      return;
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          final res = await Permission.notification.request();
          debugPrint('[FCM][Android] Notification permission: $res');
        }
      } catch (e) {
        debugPrint('[FCM][Android][Warn] Permission request failed: $e');
      }

      // [FIX] Removed Exact Alarm check as we switched to Inexact scheduling
    }
  }

  Future<bool> areNotificationsEnabled() async {
    try {
      if (kIsWeb) return false;
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (e) {
      debugPrint('[Notif][Warn] areNotificationsEnabled failed: $e');
      return false;
    }
  }

  static Future<void> showExpiryNotificationIsolated() async {
    debugPrint('[Notif] showExpiryNotificationIsolated called');
    final flnPlugin = fln.FlutterLocalNotificationsPlugin();
    const androidDetails = fln.AndroidNotificationDetails(
      'auto_wallpaper_channel',
      'Auto Wallpaper',
      channelDescription: 'Notifications for auto wallpaper updates',
      importance: fln.Importance.high,
      priority: fln.Priority.high,
    );
    const details = fln.NotificationDetails(android: androidDetails);

    try {
      await flnPlugin.initialize(
        const fln.InitializationSettings(
          android: fln.AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
    } catch (e) {
      debugPrint('[Notif] Isolated init warning: $e');
    }

    try {
      await flnPlugin.show(
        999,
        'Auto wallpaper disabled',
        'It’s been 7 days! Tap to turn auto wallpapers back on.',
        details,
        payload: 'auto_wallpaper_expired',
      );
      debugPrint('[Notif] Notification shown successfully');
    } catch (e) {
      debugPrint('[Notif] Failed to show isolated notification: $e');
    }
  }

  Future<void> showAutoWallpaperExpiryReminderNow() async {
    if (kIsWeb) return;
    try {
      final androidDetails = const fln.AndroidNotificationDetails(
        'auto_wallpaper_channel',
        'Auto Wallpaper Expiry',
        channelDescription:
            'Reminder when auto wallpaper is disabled after 7 days',
        importance: fln.Importance.high,
        priority: fln.Priority.high,
      );
      const darwinDetails = fln.DarwinNotificationDetails();
      final details =
          fln.NotificationDetails(android: androidDetails, iOS: darwinDetails);
      await _fln.show(
        _expiryReminderId,
        'Auto wallpaper disabled',
        'It’s been 7 days! Tap to turn auto wallpapers back on.',
        details,
        payload: 'auto_wallpaper_expired',
      );
    } catch (e) {
      debugPrint('[LocalNotif][Warn] show failed: $e');
    }
  }

  Future<void> showTestNotification({
    required String title,
    required String body,
    required String payload,
  }) async {
    const androidDetails = fln.AndroidNotificationDetails(
      'daily_darshan_channel',
      'Daily Darshan',
      channelDescription: 'Daily reminders for specific deities',
      importance: fln.Importance.max,
      priority: fln.Priority.high,
    );
    const details = fln.NotificationDetails(
        android: androidDetails, iOS: fln.DarwinNotificationDetails());

    await _fln.show(
      888,
      title,
      body,
      details,
      payload: payload,
    );
  }

  // Mapping: Day ID (1=Mon, 7=Sun) -> Keywords
  // Mapping: Day ID (1=Mon, 7=Sun) -> Keywords
  // MUST MATCH AutoWallpaperService logic for consistency
  static const Map<int, List<String>> dayMapping = {
    1: ['Lord Shiva', 'Mahadev', 'Bholenath', 'Shiva'],
    2: ['Lord Hanuman', 'Bajrangbali', 'Hanuman'],
    3: ['Lord Ganesha', 'Ganpati', 'Ganesha'],
    4: ['Lord Vishnu', 'Lord Krishna', 'Khatu Shyam', 'Sai Baba'],
    5: ['Goddess Lakshmi', 'Goddess Durga', 'Maa Kali'],
    6: [
      'Lord Hanuman',
      'Bajrangbali',
      'Hanuman'
    ], // Changed to Hanuman as per request
    7: ['Lord Surya', 'Sun God', 'Surya Dev'],
  };

  static const Map<int, String> dayMessages = {
    1: 'Om Namah Shivaya! Start your Monday with Lord Shiva\'s blessings. 🙏',
    2: 'Jai Bajrangbali! Seek strength from Lord Hanuman today. 💪',
    3: 'Ganpati Bappa Morya! Remove obstacles this Wednesday. 🐘',
    4: 'Om Namo Bhagavate Vasudevaya! Thursday is for Lord Vishnu. 🕉️',
    5: 'Jai Mata Di! Seek prosperity from Goddess Lakshmi this Friday. 🌸',
    6: 'Jai Bajrangbali! Dedicate your Saturday to Lord Hanuman. 🕉️', // Updated for Hanuman
    7: 'Om Suryaya Namah! Start your Sunday with brilliance. ☀️',
  };

  Future<void> scheduleDailyDeityNotifications(List<dynamic> categories) async {
    if (kIsWeb) return;

    for (int i = 1; i <= 7; i++) {
      try {
        await _fln.cancel(100 + i);
      } catch (e) {/* ignore */}
    }
    // Also cancel any lingering test notification
    try {
      await _fln.cancel(888);
    } catch (e) {/* ignore */}

    try {
      for (int day = 1; day <= 7; day++) {
        final keywords = dayMapping[day] ?? [];
        String? categoryId;

        debugPrint('[Notif] Sched: Checking Day $day (Keywords: $keywords)');

        for (final cat in categories) {
          final name = (cat.name as String? ?? '').toLowerCase();
          if (name.isEmpty) continue;

          for (final kw in keywords) {
            if (name.contains(kw.toLowerCase())) {
              categoryId = cat.id as String;
              debugPrint(
                  '[Notif]   MATCH! "$name" contains "$kw" -> ID: $categoryId');
              break;
            }
          }
          if (categoryId != null) break;
        }

        if (categoryId != null) {
          await _scheduleWeekly(
            id: 100 + day,
            title: 'Daily Darshan',
            body: dayMessages[day]!,
            payload: 'category:$categoryId',
            weekday: day,
            // [FIX] Debug: Test at 7:30 PM (19:30). Prod: 7:00 AM.
            hour: 7,
            minute: 0,
          );
        } else {
          debugPrint('[Notif]   NO MATCH for Day $day');
        }
      }
      debugPrint('[Notif] Daily Deity Notifications Scheduled');
    } catch (e) {
      debugPrint('[Notif][Warn] Failed to schedule daily: $e');
    }
  }

  Future<void> _scheduleWeekly({
    required int id,
    required String title,
    required String body,
    required String payload,
    required int weekday, // 1=Mon, 7=Sun
    required int hour,
    required int minute,
  }) async {
    try {
      final now = tz.TZDateTime.now(tz.local);

      const androidDetails = fln.AndroidNotificationDetails(
        'daily_darshan_channel',
        'Daily Darshan',
        channelDescription: 'Daily reminders for specific deities',
        importance: fln.Importance.max,
        priority: fln.Priority.high,
      );
      const darwinDetails = fln.DarwinNotificationDetails();
      const details =
          fln.NotificationDetails(android: androidDetails, iOS: darwinDetails);

      // [REVERTED] Debug Mode Override: Removed as per user request.
      // Schedules strictly for 7 AM weekly.

      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      while (scheduledDate.weekday != weekday) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 7));
      }

      await _fln.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        // [FIX] Downgraded to inexact to remove USE_EXACT_ALARM permission
        androidScheduleMode: fln.AndroidScheduleMode.inexact,
        matchDateTimeComponents: fln.DateTimeComponents.dayOfWeekAndTime,
        payload: payload,
      );
      debugPrint(
          '[Notif] Scheduled #$id for $scheduledDate ($title) [Loc: ${scheduledDate.location}]');
    } catch (e) {
      debugPrint('[Notif] Schedule error: $e');
    }
  }

  /// Debug method to schedule a notification with MOCKED content but REAL time.
  /// [mockDay] 1=Mon ... 7=Sun (Determines the Content, e.g. Shiva)
  /// [time] The time to trigger the notification TODAY (or tomorrow if passed).
  Future<void> scheduleDebugNotification({
    required int mockDay,
    required TimeOfDay time,
  }) async {
    final now = DateTime.now();
    var scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    // If time passed, schedule for tomorrow?
    // User said "based on the time I gave it should send me notification".
    // Usually implies "Next occurrence".
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    // Determine content based on MOCKED day
    final safeDay = mockDay.clamp(1, 7);
    final contentBody = dayMessages[safeDay] ?? 'Daily Darshan Debug';
    // We need a category ID to make the payload valid.
    // We'll rely on the existing mapping logic or just use a placeholder if not strictly needed for the test,
    // BUT the user wants to see the "God name" which implies correct content.
    // The payload needs a category ID to navigate.
    // We can try to find one dynamically or just use a dummy.
    // For a robust test, let's just put a dummy 'debug' payload or try to find one.
    // Let's use a special debug payload.

    // Let's use a special debug payload.

    // Fetch real ID for navigation
    String mockPayload = await _findCategoryIdForDay(safeDay);
    debugPrint('[Notif][Debug] Using payload: $mockPayload');

    // (Optional) Try to find a real ID for better realism?
    // This is async and might be slow, let's just stick to the body text verification.

    debugPrint('[Notif][Debug] Scheduling Mock Day=$safeDay at $scheduledDate');

    const androidDetails = fln.AndroidNotificationDetails(
      'daily_darshan_debug_channel_v2', // CHANGED ID
      'Daily Darshan Debug',
      channelDescription: 'Debug notifications for testing',
      importance: fln.Importance.max,
      priority: fln.Priority.high,
    );
    const details = fln.NotificationDetails(android: androidDetails);

    // Convert to TZDateTime for zonedSchedule
    // [FIX] Timezone Workaround:
    // Since flutter_timezone might be missing/uninitialized, tz.local defaults to UTC.
    // Converting a local DateTime (e.g. 10:00 AM) to tz.local (UTC) makes it 10:00 AM UTC.
    // If user is in IST (UTC+5:30), 10:00 AM UTC is 3:30 PM IST.
    // Solution: Calculate the relative duration (e.g. "in 5 minutes") and add to tz.now.
    final difference = scheduledDate.difference(now);
    // Ensure at least a small delay to prevent "past" errors if execution is slow
    final safeDelay =
        difference.isNegative ? const Duration(seconds: 2) : difference;

    // Use proper "now" from the timezone library's perspective + delay
    final tzScheduledDate = tz.TZDateTime.now(tz.local).add(safeDelay);

    debugPrint(
        '[Notif][Debug] Scheduling relative: in ${safeDelay.inSeconds}s (at $tzScheduledDate)');
    debugPrint(
        '[Notif][Debug] System Time: ${DateTime.now()} | TZ Time: ${tz.TZDateTime.now(tz.local)}');
    debugPrint(
        '[Notif][Debug] Note: Using INEXACT scheduling. Notification may be delayed by Android Doze.');

    await _fln.zonedSchedule(
        999, // Dedicated Debug ID
        'Daily Darshan',
        contentBody,
        tzScheduledDate,
        details,
        androidScheduleMode: fln.AndroidScheduleMode.inexact,
        payload: mockPayload);

    debugPrint('[Notif][Debug] Scheduled!');
  }

  /// Helper to find a real category ID for the mock day to ensure navigation works
  Future<String> _findCategoryIdForDay(int day) async {
    try {
      final keywords = dayMapping[day] ?? [];
      debugPrint('[Notif][Debug] Fetching categories with 3s timeout...');
      final categories = await CategoryService()
          .getCategories()
          .timeout(const Duration(seconds: 3));

      for (final cat in categories) {
        final name = cat.name.toLowerCase();
        for (final kw in keywords) {
          if (name.contains(kw.toLowerCase())) {
            return 'category:${cat.id}';
          }
        }
      }
    } catch (e) {
      debugPrint('[Notif][Debug] Failed to fetch categories for payload: $e');
    }
    return 'debug_test_day_$day'; // Fallback
  }

  /// DIRECT DEBUG: Bypasses scheduling to test if notifications can even show up.
  Future<void> showImmediateDebugNotification({required int mockDay}) async {
    final safeDay = mockDay.clamp(1, 7);
    final contentBody = dayMessages[safeDay] ?? 'Daily Darshan Debug';

    // Fetch real ID for navigation
    String mockPayload = await _findCategoryIdForDay(safeDay);
    debugPrint('[Notif][Debug] Using payload: $mockPayload');

    // Explicitly request permissions here too just in case
    if (!kIsWeb && Platform.isAndroid) {
      if (!await Permission.notification.isGranted) {
        await Permission.notification.request();
      }
    }

    const androidDetails = fln.AndroidNotificationDetails(
      'daily_darshan_debug_channel_v2',
      'Daily Darshan Debug',
      channelDescription: 'Debug notifications for testing',
      importance: fln.Importance.max,
      priority: fln.Priority.high,
    );
    const details = fln.NotificationDetails(android: androidDetails);

    await _fln.show(
      888, // Different ID for immediate test
      'Daily Darshan (Instant)',
      contentBody,
      details,
      payload: mockPayload,
    );
    debugPrint('[Notif][Debug] Shown Immediate Notification!');
  }

  Future<void> checkPendingNotifications() async {
    final pending = await _fln.pendingNotificationRequests();
    debugPrint('[Notif] Pending Notifications Count: ${pending.length}');
    for (final p in pending) {
      debugPrint(
          '[Notif] Pending: ID=${p.id}, Title=${p.title}, Body=${p.body}, Payload=${p.payload}');
    }
  }
}
