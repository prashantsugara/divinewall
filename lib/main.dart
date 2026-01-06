import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:deva_aura/theme.dart';
import 'package:deva_aura/firebase_options.dart';
import 'package:deva_aura/screens/splash_screen.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:deva_aura/services/config_service.dart';
import 'package:flutter/services.dart';
import 'package:deva_aura/services/meta_tracking_service.dart';
import 'package:deva_aura/services/notification_service.dart';
import 'package:deva_aura/services/auto_wallpaper_service.dart';
import 'package:deva_aura/auth/auth_manager.dart'; // [FIX] Added missing import

import 'package:timezone/data/latest_all.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // [FIX] Ensure anonymous auth for global likes (Must be after Firebase.initializeApp)
  final auth = AuthManager();
  if (auth.currentUser == null) {
    try {
      await auth.signInAnonymously();
    } catch (e) {
      debugPrint('Failed to sign in anonymously: $e');
    }
  }

  // Do not block app launch on config seeding; run it in the background.
  // This prevents cold-start hangs when offline.
  // Splash/Home may also backfill config, but this ensures it eventually exists.
  // Intentionally not awaited.
  // ignore: unawaited_futures
  Future(() async {
    try {
      await ConfigService().ensureSeeded();
    } catch (e) {
      debugPrint('[Config][Warn] Background seed skipped/offline: $e');
    }
  });
  // Initialize config listener for instant ad flags
  ConfigService().init();

  // Log runtime origin and Firebase options to help diagnose web auth domain issues
  try {
    debugPrint('[App] Web origin: ${Uri.base.origin}');
    final opts = Firebase.app().options;
    final maskedApiKey = (opts.apiKey.length >= 6)
        ? '${opts.apiKey.substring(0, 4)}***${opts.apiKey.substring(opts.apiKey.length - 2)}'
        : '***';
    debugPrint(
        '[App] FirebaseOptions: projectId=${opts.projectId}, appId=${opts.appId}, apiKey=$maskedApiKey, authDomain=${opts.authDomain ?? 'null'}');
  } catch (e) {
    debugPrint('[App][Warn] Failed to log Firebase options/origin: $e');
  }
  // Initialize Google Mobile Ads SDK on mobile platforms only
  if (!kIsWeb) {
    try {
      await MobileAds.instance.initialize();
      debugPrint('[Ads] Google Mobile Ads initialized');
    } catch (e) {
      debugPrint('[Ads][Warn] Failed to initialize MobileAds: $e');
    }
  }
  // Initialize Meta (Facebook) App Events for install/open tracking
  try {
    await MetaTrackingService().init();
  } catch (e) {
    debugPrint('[Meta][Warn] init failed: $e');
  }
  // Initialize Firebase Cloud Messaging (permissions, token, listeners)
  try {
    await NotificationService.instance.init();
  } catch (e, st) {
    debugPrint('[FCM][Warn] init failed: $e\n$st');
  }
  // Initialize auto-wallpaper background scheduler and refresh pool once (Android only)
  try {
    await AutoWallpaperService.instance.ensureInitialized();
    // Fire-and-forget pool refresh; uses user-or-guest favorites if needed
    Future(() async {
      try {
        // We don't have user model here quickly; pool will refresh after user visits settings too
        await AutoWallpaperService.instance.refreshPool();
        await AutoWallpaperService.instance
            .applyScheduling(preserveSchedule: true);
      } catch (e) {
        debugPrint('[AutoWall][Warn] Startup refresh failed: $e');
      }
    });
  } catch (e) {
    debugPrint('[AutoWall][Warn] init failed: $e');
  }
  // Modern edge-to-edge using Flutter services API
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      // Divider color is deprecated on Android Q+
    ));
  } catch (e) {
    debugPrint('[UI] Failed to set edge-to-edge mode: $e');
  }
  runApp(const MyApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'DivineWall',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
    );
  }
}
