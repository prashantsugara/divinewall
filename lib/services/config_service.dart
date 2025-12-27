import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AppConfig {
  final bool enableAds;
  final bool enableInterstitialAds;
  final bool enableBannerAds;
  final bool enableNativeAds;
  final bool enableRewardedAds; // [NEW]
  // Legacy generic fields (kept for backward compatibility)
  final String? bannerAdUnitAndroid;
  final String? bannerAdUnitIos;

  // Role-specific fields (deprecated – kept for backward compatibility)
  final String? bannerAdUnitAndroidUser;
  final String? bannerAdUnitIosUser;
  final String? bannerAdUnitAndroidAdmin;
  final String? bannerAdUnitIosAdmin;

  // Placement-specific banner IDs (screen-specific, canonical)
  // Canonical keys expected in Firestore:
  //   banner_ad_unit_android_welcome
  //   banner_ad_unit_ios_welcome
  //   banner_ad_unit_android_wallpapers
  //   banner_ad_unit_ios_wallpapers
  final String? bannerWelcomeAdUnitAndroid;
  final String? bannerWelcomeAdUnitIos;
  final String? bannerWallpapersAdUnitAndroid;
  final String? bannerWallpapersAdUnitIos;
  final String? bannerViewerAdUnitAndroid; // [NEW]
  final String? bannerViewerAdUnitIos; // [NEW]

  // Interstitial canonical (single id per platform)
  final String? interstitialAdUnitAndroid;
  final String? interstitialAdUnitIos;

  // Interstitial role-specific fields (deprecated – kept for fallback)
  final String? interstitialAdUnitAndroidUser;
  final String? interstitialAdUnitIosUser;
  final String? interstitialAdUnitAndroidAdmin;
  final String? interstitialAdUnitIosAdmin;

  // Native Ads
  final String? nativeAdUnitAndroid;
  final String? nativeAdUnitIos;
  final String? nativeAdUnitAndroidTest; // [NEW]
  final String? nativeAdUnitIosTest; // [NEW]

  // Rewarded canonical (single id per platform)
  final String? rewardedAdUnitAndroid;
  final String? rewardedAdUnitIos;
  // Rewarded TEST ids (optional; fallback to Google test ids)
  final String? rewardedAdUnitAndroidTest;
  final String? rewardedAdUnitIosTest;

  const AppConfig({
    required this.enableAds,
    required this.enableInterstitialAds,
    required this.enableBannerAds,
    required this.enableNativeAds,
    required this.enableRewardedAds,
    this.bannerAdUnitAndroid,
    this.bannerAdUnitIos,
    this.bannerAdUnitAndroidUser,
    this.bannerAdUnitIosUser,
    this.bannerAdUnitAndroidAdmin,
    this.bannerAdUnitIosAdmin,
    this.bannerWelcomeAdUnitAndroid,
    this.bannerWelcomeAdUnitIos,
    this.bannerWallpapersAdUnitAndroid,
    this.bannerWallpapersAdUnitIos,
    this.bannerViewerAdUnitAndroid,
    this.bannerViewerAdUnitIos,
    this.interstitialAdUnitAndroid,
    this.interstitialAdUnitIos,
    this.interstitialAdUnitAndroidUser,
    this.interstitialAdUnitIosUser,
    this.interstitialAdUnitAndroidAdmin,
    this.interstitialAdUnitIosAdmin,
    this.nativeAdUnitAndroid,
    this.nativeAdUnitIos,
    this.nativeAdUnitAndroidTest,
    this.nativeAdUnitIosTest,
    this.rewardedAdUnitAndroid,
    this.rewardedAdUnitIos,
    this.rewardedAdUnitAndroidTest,
    this.rewardedAdUnitIosTest,
  });

  factory AppConfig.fromMap(Map<String, dynamic>? data) {
    final d = data ?? <String, dynamic>{};
    // Keep legacy fields as fallbacks for role-based ones
    final legacyAndroid = d['banner_ad_unit_android'] as String?;
    final legacyIos = d['banner_ad_unit_ios'] as String?;

    return AppConfig(
      enableAds: (d['enable_ad'] as bool?) ?? false,
      enableInterstitialAds: (d['enable_interstitial_ad'] as bool?) ?? true,
      enableBannerAds: (d['enable_banner_ad'] as bool?) ?? true,
      enableNativeAds: (d['enable_native_ad'] as bool?) ?? true,
      enableRewardedAds: (d['enable_rewarded_ad'] as bool?) ?? true,
      bannerAdUnitAndroid: legacyAndroid,
      bannerAdUnitIos: legacyIos,
      bannerAdUnitAndroidUser:
          (d['banner_ad_unit_android_user'] as String?) ?? legacyAndroid,
      bannerAdUnitIosUser:
          (d['banner_ad_unit_ios_user'] as String?) ?? legacyIos,
      bannerAdUnitAndroidAdmin:
          (d['banner_ad_unit_android_admin'] as String?) ??
              ConfigService.testBannerAndroid,
      bannerAdUnitIosAdmin: (d['banner_ad_unit_ios_admin'] as String?) ??
          ConfigService.testBannerIos,
      // Support both canonical and older naming for placement-specific banners
      bannerWelcomeAdUnitAndroid:
          (d['banner_ad_unit_android_welcome'] as String?) ??
              (d['banner_welcome_ad_unit_android'] as String?),
      bannerWelcomeAdUnitIos: (d['banner_ad_unit_ios_welcome'] as String?) ??
          (d['banner_welcome_ad_unit_ios'] as String?),
      bannerWallpapersAdUnitAndroid:
          (d['banner_ad_unit_android_wallpapers'] as String?) ??
              (d['banner_wallpapers_ad_unit_android'] as String?),
      bannerWallpapersAdUnitIos:
          (d['banner_ad_unit_ios_wallpapers'] as String?) ??
              (d['banner_wallpapers_ad_unit_ios'] as String?),
      bannerViewerAdUnitAndroid:
          (d['banner_viewer_ad_unit_android'] as String?) ??
              (d['banner_ad_unit_android_viewer'] as String?),
      bannerViewerAdUnitIos: (d['banner_viewer_ad_unit_ios'] as String?) ??
          (d['banner_ad_unit_ios_viewer'] as String?),
      // Canonical interstitials
      interstitialAdUnitAndroid: d['interstitial_ad_unit_android'] as String?,
      interstitialAdUnitIos: d['interstitial_ad_unit_ios'] as String?,
      interstitialAdUnitAndroidUser:
          d['interstitial_ad_unit_android_user'] as String?,
      interstitialAdUnitIosUser: d['interstitial_ad_unit_ios_user'] as String?,
      interstitialAdUnitAndroidAdmin:
          (d['interstitial_ad_unit_android_admin'] as String?) ??
              ConfigService.testInterstitialAndroid,
      interstitialAdUnitIosAdmin:
          (d['interstitial_ad_unit_ios_admin'] as String?) ??
              ConfigService.testInterstitialIos,
      // Native
      nativeAdUnitAndroid: d['native_ad_unit_android'] as String?,
      nativeAdUnitIos: d['native_ad_unit_ios'] as String?,
      nativeAdUnitAndroidTest: d['native_ad_unit_android_test'] as String?,
      nativeAdUnitIosTest: d['native_ad_unit_ios_test'] as String?,
      // Rewarded
      rewardedAdUnitAndroid: d['rewarded_ad_unit_android'] as String?,
      rewardedAdUnitIos: d['rewarded_ad_unit_ios'] as String?,
      rewardedAdUnitAndroidTest: d['rewarded_ad_unit_android_test'] as String?,
      rewardedAdUnitIosTest: d['rewarded_ad_unit_ios_test'] as String?,
    );
  }
}

/// Provides access to the app-wide config stored in Firestore.
///
/// Firestore structure:
///   collection: config
///     doc: app
///       fields:
///         enable_ad: bool
///         banner_ad_unit_android: string
///         banner_ad_unit_ios: string
class ConfigService {
  ConfigService._internal();
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;

  static final _docRef =
      FirebaseFirestore.instance.collection('config').doc('app');

  // Google test banner IDs
  static const String testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String testBannerIos = 'ca-app-pub-3940256099942544/2934735716';

  // Google test interstitial IDs
  static const String testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String testInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';

  // Google test rewarded IDs
  static const String testRewardedAndroid =
      'ca-app-pub-3940256099942544/5224354917';
  static const String testRewardedIos =
      'ca-app-pub-3940256099942544/1712485313';

  /// Ensures a config document exists and is normalized to canonical keys.
  /// Defaults use Google test ad unit IDs so ads can be verified immediately.
  ///
  /// Offline-safe: short timeouts on reads/writes; errors are logged and ignored.
  Future<void> ensureSeeded(
      {Duration timeout = const Duration(seconds: 3)}) async {
    DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      // Try server first, but allow returning quickly when offline.
      snap = await _docRef
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(timeout);
    } catch (e) {
      // If even cached read fails/times out, skip seeding silently.
      // This prevents startup hangs when offline.
      debugPrint('[Config][Warn] get() skipped (offline/timeout): $e');
      return;
    }
    if (!snap.exists) {
      // Create with canonical defaults only
      try {
        await _docRef.set({
          'enable_ad': true,
          'enable_interstitial_ad': true,
          'enable_banner_ad': true,
          'enable_native_ad': true,
          'enable_rewarded_ad': true,
          // Canonical banner ids per screen
          'banner_ad_unit_android_welcome': testBannerAndroid,
          'banner_ad_unit_ios_welcome': testBannerIos,
          'banner_ad_unit_android_wallpapers': testBannerAndroid,
          'banner_ad_unit_ios_wallpapers': testBannerIos,
          // Canonical interstitial ids
          'interstitial_ad_unit_android': testInterstitialAndroid,
          'interstitial_ad_unit_ios': testInterstitialIos,
          // Canonical rewarded ids
          'rewarded_ad_unit_android': testRewardedAndroid,
          'rewarded_ad_unit_ios': testRewardedIos,
          'updatedAt': DateTime.now().toIso8601String(),
          'note': 'Seeded by app. Replace test IDs with production ones.'
        }, SetOptions(merge: true)).timeout(timeout);
      } catch (e) {
        // Likely offline; safe to ignore.
        debugPrint(
            '[Config][Warn] initial set() skipped (offline/timeout): $e');
      }
      return;
    }

    // If exists, migrate to canonical keys and remove obsolete ones.
    final data = snap.data() ?? <String, dynamic>{};
    final Map<String, dynamic> patch = {};

    String? _pickFirstNonEmpty(List<String> keys) {
      for (final k in keys) {
        final v = data[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    void addIfMissing(String key, String value) {
      final current = data[key];
      if (current == null || (current is String && current.isEmpty)) {
        patch[key] = value;
      }
    }

    // Ensure toggles
    if (data['enable_ad'] == null) patch['enable_ad'] = true;
    if (data['enable_interstitial_ad'] == null)
      patch['enable_interstitial_ad'] = true;
    if (data['enable_banner_ad'] == null) patch['enable_banner_ad'] = true;
    if (data['enable_native_ad'] == null) patch['enable_native_ad'] = true;
    if (data['enable_rewarded_ad'] == null) patch['enable_rewarded_ad'] = true;

    // Canonical banners per screen
    final androidWelcome = _pickFirstNonEmpty([
          'banner_ad_unit_android_welcome',
          'banner_welcome_ad_unit_android',
          'banner_ad_unit_android_welcome_user',
          'banner_ad_unit_android_welcome_admin',
          'banner_ad_unit_android',
        ]) ??
        testBannerAndroid;
    final iosWelcome = _pickFirstNonEmpty([
          'banner_ad_unit_ios_welcome',
          'banner_welcome_ad_unit_ios',
          'banner_ad_unit_ios_welcome_user',
          'banner_ad_unit_ios_welcome_admin',
          'banner_ad_unit_ios',
        ]) ??
        testBannerIos;
    final androidWallpapers = _pickFirstNonEmpty([
          'banner_ad_unit_android_wallpapers',
          'banner_wallpapers_ad_unit_android',
          'banner_ad_unit_android_wallpapers_user',
          'banner_ad_unit_android_wallpapers_admin',
          'banner_ad_unit_android',
        ]) ??
        testBannerAndroid;
    final iosWallpapers = _pickFirstNonEmpty([
          'banner_ad_unit_ios_wallpapers',
          'banner_wallpapers_ad_unit_ios',
          'banner_ad_unit_ios_wallpapers_user',
          'banner_ad_unit_ios_wallpapers_admin',
          'banner_ad_unit_ios',
        ]) ??
        testBannerIos;

    addIfMissing('banner_ad_unit_android_welcome', androidWelcome);
    addIfMissing('banner_ad_unit_ios_welcome', iosWelcome);
    addIfMissing('banner_ad_unit_android_wallpapers', androidWallpapers);
    addIfMissing('banner_ad_unit_ios_wallpapers', iosWallpapers);

    // Viewer
    final androidViewer = _pickFirstNonEmpty([
          'banner_viewer_ad_unit_android',
          'banner_ad_unit_android_viewer',
          'banner_ad_unit_android'
        ]) ??
        testBannerAndroid;
    final iosViewer = _pickFirstNonEmpty([
          'banner_viewer_ad_unit_ios',
          'banner_ad_unit_ios_viewer',
          'banner_ad_unit_ios'
        ]) ??
        testBannerIos;
    addIfMissing('banner_viewer_ad_unit_android', androidViewer);
    addIfMissing('banner_viewer_ad_unit_ios', iosViewer);

    // Canonical interstitials per platform
    final interAndroid = _pickFirstNonEmpty([
          'interstitial_ad_unit_android',
          'interstitial_ad_unit_android_user',
          'interstitial_ad_unit_android_admin',
        ]) ??
        testInterstitialAndroid;
    final interIos = _pickFirstNonEmpty([
          'interstitial_ad_unit_ios',
          'interstitial_ad_unit_ios_user',
          'interstitial_ad_unit_ios_admin',
        ]) ??
        testInterstitialIos;

    addIfMissing('interstitial_ad_unit_android', interAndroid);
    addIfMissing('interstitial_ad_unit_ios', interIos);

    addIfMissing('interstitial_ad_unit_android', interAndroid);
    addIfMissing('interstitial_ad_unit_ios', interIos);

    // Native
    // Using advanced native test id as default
    // Android: ca-app-pub-3940256099942544/2247696110
    // iOS: ca-app-pub-3940256099942544/3986624511
    addIfMissing(
        'native_ad_unit_android', 'ca-app-pub-3940256099942544/2247696110');
    addIfMissing(
        'native_ad_unit_ios', 'ca-app-pub-3940256099942544/3986624511');

    // Native Test (Admin) - distinct keys so we don't overwrite production with test if user toggles admin
    // Using Google generic native advanced video test id
    addIfMissing('native_ad_unit_android_test',
        'ca-app-pub-3940256099942544/2247696110');
    addIfMissing(
        'native_ad_unit_ios_test', 'ca-app-pub-3940256099942544/3986624511');

    // Rewarded per platform
    final rewAndroid = _pickFirstNonEmpty([
          'rewarded_ad_unit_android',
        ]) ??
        testRewardedAndroid;
    final rewIos = _pickFirstNonEmpty([
          'rewarded_ad_unit_ios',
        ]) ??
        testRewardedIos;

    addIfMissing('rewarded_ad_unit_android', rewAndroid);
    addIfMissing('rewarded_ad_unit_ios', rewIos);

    // Rewarded TEST ids (allow overriding Google test ids from config)
    final rewAndroidTest = _pickFirstNonEmpty([
          'rewarded_ad_unit_android_test',
        ]) ??
        testRewardedAndroid;
    final rewIosTest = _pickFirstNonEmpty([
          'rewarded_ad_unit_ios_test',
        ]) ??
        testRewardedIos;

    addIfMissing('rewarded_ad_unit_android_test', rewAndroidTest);
    addIfMissing('rewarded_ad_unit_ios_test', rewIosTest);

    if (patch.isNotEmpty) {
      patch['updatedAt'] = DateTime.now().toIso8601String();
      try {
        await _docRef.set(patch, SetOptions(merge: true)).timeout(timeout);
      } catch (e) {
        debugPrint('[Config][Warn] patch set() skipped (offline/timeout): $e');
      }
    }

    // Remove obsolete keys to reduce confusion
    final List<String> obsolete = [
      // Legacy generic banner ids
      'banner_ad_unit_android',
      'banner_ad_unit_ios',
      // Older placement naming
      'banner_welcome_ad_unit_android',
      'banner_welcome_ad_unit_ios',
      'banner_wallpapers_ad_unit_android',
      'banner_wallpapers_ad_unit_ios',
      // Role-specific banners
      'banner_ad_unit_android_user',
      'banner_ad_unit_ios_user',
      'banner_ad_unit_android_admin',
      'banner_ad_unit_ios_admin',
      'banner_ad_unit_android_welcome_user',
      'banner_ad_unit_android_welcome_admin',
      'banner_ad_unit_ios_welcome_user',
      'banner_ad_unit_ios_welcome_admin',
      'banner_ad_unit_android_wallpapers_user',
      'banner_ad_unit_android_wallpapers_admin',
      'banner_ad_unit_ios_wallpapers_user',
      'banner_ad_unit_ios_wallpapers_admin',
      // Role-specific interstitials
      'interstitial_ad_unit_android_user',
      'interstitial_ad_unit_android_admin',
      'interstitial_ad_unit_ios_user',
      'interstitial_ad_unit_ios_admin',
    ];

    final Map<String, dynamic> deletions = {};
    for (final key in obsolete) {
      if (data.containsKey(key)) {
        deletions[key] = FieldValue.delete();
      }
    }
    if (deletions.isNotEmpty) {
      deletions['updatedAt'] = DateTime.now().toIso8601String();
      try {
        await _docRef.update(deletions).timeout(timeout);
      } catch (e) {
        debugPrint(
            '[Config][Warn] delete obsolete keys skipped (offline/timeout): $e');
      }
    }
  }

  AppConfig _cachedConfig = const AppConfig(
    enableAds: false,
    enableInterstitialAds: true,
    enableBannerAds: true,
    enableNativeAds: true,
    enableRewardedAds: true,
  );
  AppConfig get cachedConfig => _cachedConfig;

  /// Initialize the service by listening to config changes in real-time.
  /// Call this early in app startup (e.g. main.dart or splash).
  Future<void> init() async {
    // Initial fetch to have data immediately available
    _cachedConfig = await getConfigOnce();
    // Listen for updates
    watchConfig().listen((cfg) {
      _cachedConfig = cfg;
    });
  }

  Stream<AppConfig> watchConfig() {
    return _docRef
        .snapshots()
        .map((snap) => AppConfig.fromMap(snap.data() as Map<String, dynamic>?));
  }

  Future<AppConfig> getConfigOnce() async {
    try {
      final snap = await _docRef
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 2));
      return AppConfig.fromMap(snap.data());
    } catch (e) {
      debugPrint('[Config][Warn] getConfigOnce failed (offline/timeout): $e');
      // Return safe defaults when offline; ads disabled by default in fromMap
      return AppConfig.fromMap(null);
    }
  }
}
