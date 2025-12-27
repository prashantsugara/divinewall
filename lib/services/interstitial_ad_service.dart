import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:deva_aura/services/config_service.dart';

/// Interstitial ad helper with simple preloading so navigation never feels stuck.
class InterstitialAdService {
  InterstitialAdService._internal();
  static final InterstitialAdService _instance =
      InterstitialAdService._internal();
  factory InterstitialAdService() => _instance;

  final ConfigService _configService = ConfigService();

  InterstitialAd? _cachedAd;
  String? _cachedUnitId;
  bool _loading = false;
  DateTime? _lastShownAt;
  static const Duration _cooldown = Duration(minutes: 2);

  bool get _isInCooldown {
    if (_lastShownAt == null) return false;
    return DateTime.now().difference(_lastShownAt!) < _cooldown;
  }

  /// Preload an interstitial for the current platform.
  Future<void> preload({required bool isAdmin}) async {
    if (kIsWeb || _loading) return;
    try {
      final cfg = _configService.cachedConfig;
      if (!cfg.enableAds || !cfg.enableInterstitialAds) return;
      String? adUnitId;
      // Important: Admins should always see test ads.
      // Prefer the admin-specific (defaults to Google test IDs via ConfigService),
      // and only use canonical production ids for non-admin users.
      if (Platform.isAndroid) {
        if (isAdmin) {
          adUnitId = cfg.interstitialAdUnitAndroidAdmin;
        } else {
          adUnitId = cfg.interstitialAdUnitAndroid ??
              cfg.interstitialAdUnitAndroidUser;
        }
      } else if (Platform.isIOS) {
        if (isAdmin) {
          adUnitId = cfg.interstitialAdUnitIosAdmin;
        } else {
          adUnitId = cfg.interstitialAdUnitIos ?? cfg.interstitialAdUnitIosUser;
        }
      }
      debugPrint(
          '[Ads][Interstitial] Selection: isAdmin=$isAdmin, unitId=$adUnitId');
      if (adUnitId == null || adUnitId.isEmpty) return;

      // If we already have a cached ad with same unit, do nothing.
      if (_cachedAd != null && _cachedUnitId == adUnitId) return;

      _loading = true;
      InterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (InterstitialAd ad) {
            debugPrint('[Ads] Interstitial preloaded');
            _cachedAd?.dispose();
            _cachedAd = ad;
            _cachedUnitId = adUnitId;
            _loading = false;
          },
          onAdFailedToLoad: (LoadAdError error) {
            debugPrint('[Ads] Preload failed: ${error.code} ${error.message}');
            _cachedAd?.dispose();
            _cachedAd = null;
            _cachedUnitId = null;
            _loading = false;
          },
        ),
      );
    } catch (e) {
      debugPrint('[Ads] Preload error: $e');
      _loading = false;
    }
  }

  /// Shows an interstitial if a preloaded one is available. Does not block navigation.
  /// Always calls [onComplete] immediately to keep UI responsive.
  Future<void> showAfterTap({
    required bool isAdmin,
    required VoidCallback onComplete,
  }) async {
    // Immediately continue with navigation to avoid any perceived hang
    onComplete();

    if (kIsWeb) return;

    try {
      // Respect remote toggle for interstitials
      // Respect remote toggle for interstitials
      final cfg = _configService.cachedConfig;
      if (!cfg.enableAds || !cfg.enableInterstitialAds) return;

      // Respect cooldown so interstitials are not shown too frequently
      if (_isInCooldown) {
        // Ensure we have a cached ad ready for when cooldown ends
        if (_cachedAd == null && !_loading) {
          // Fire and forget
          // ignore: unawaited_futures
          preload(isAdmin: isAdmin);
        }
        return;
      }

      // Try to use a cached ad first
      if (_cachedAd != null) {
        final ad = _cachedAd!;
        _cachedAd = null;
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdShowedFullScreenContent: (ad) {
            // Start cooldown as soon as the ad is actually shown
            _lastShownAt = DateTime.now();
          },
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            // Prepare the next ad
            preload(isAdmin: isAdmin);
          },
          onAdFailedToShowFullScreenContent: (ad, err) {
            debugPrint(
                '[Ads] Interstitial show failed: ${err.code} ${err.message}');
            ad.dispose();
            preload(isAdmin: isAdmin);
          },
        );
        // Showing on next microtask so it overlays the next screen if we navigated.
        Future.microtask(() async {
          try {
            await ad.show();
          } catch (e) {
            debugPrint('[Ads] ad.show() crash prevention: $e');
            ad.dispose();
            // Try to preload again to recover state
            preload(isAdmin: isAdmin);
          }
        });
        return;
      }

      // No cached ad: kick off a preload in background so next tap is instant.
      await preload(isAdmin: isAdmin);
    } catch (e) {
      debugPrint('[Ads] showAfterTap error: $e');
    }
  }
}
