import 'dart:io' show Platform;
import 'dart:async';
import 'dart:math' show pow;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:deva_aura/services/config_service.dart';
import 'package:deva_aura/auth/auth_manager.dart';

/// Optimized RewardedAdService with preloading and automatic retry logic.
class RewardedAdService {
  RewardedAdService._();
  static final RewardedAdService instance = RewardedAdService._();

  final ConfigService _config = ConfigService();

  RewardedAd? _cachedAd;
  bool _loading = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  /// Loads a rewarded ad in the background.
  Future<void> load({String? debugReason}) async {
    if (kIsWeb || _loading || _cachedAd != null) return;

    try {
      final cfg = await _config.getConfigOnce();
      if (!cfg.enableAds || !cfg.enableRewardedAds) return;

      // Resolve roles
      bool isAdmin = false;
      try {
        final userModel = await AuthManager().getCurrentUserModel();
        isAdmin = AuthManager().isAdmin(userModel);
      } catch (_) {}

      String? adUnitId;
      if (Platform.isAndroid) {
        adUnitId = isAdmin
            ? (cfg.rewardedAdUnitAndroidTest ??
                ConfigService.testRewardedAndroid)
            : (cfg.rewardedAdUnitAndroid ?? ConfigService.testRewardedAndroid);
      } else if (Platform.isIOS) {
        adUnitId = isAdmin
            ? (cfg.rewardedAdUnitIosTest ?? ConfigService.testRewardedIos)
            : (cfg.rewardedAdUnitIos ?? ConfigService.testRewardedIos);
      }

      if (adUnitId == null || adUnitId.isEmpty) return;

      _loading = true;
      debugPrint(
          '[Ads][Rewarded] Loading... reason=$debugReason unit=$adUnitId');

      await RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            debugPrint('[Ads][Rewarded] Loaded successfully');
            _cachedAd = ad;
            _loading = false;
            _retryCount = 0;
          },
          onAdFailedToLoad: (LoadAdError error) {
            debugPrint(
                '[Ads][Rewarded] Load failed: ${error.code} ${error.message}');
            _loading = false;
            _cachedAd = null;

            // Retry logic with exponential backoff
            if (_retryCount < _maxRetries) {
              _retryCount++;
              final delay = Duration(seconds: pow(2, _retryCount).toInt() * 10);
              debugPrint(
                  '[Ads][Rewarded] Retrying in ${delay.inSeconds}s (Retry #$_retryCount)');
              Future.delayed(delay, () => load(debugReason: 'retry'));
            }
          },
        ),
      );
    } catch (e) {
      debugPrint('[Ads][Rewarded] Load error: $e');
      _loading = false;
    }
  }

  /// Shows a rewarded ad and completes with true only if a reward was earned.
  /// Uses a preloaded ad if available, otherwise attempts to load one immediately.
  Future<bool> showReward({String? debugReason}) async {
    if (kIsWeb) return true;

    // Fail-open if disabled
    final cfg = await _config.getConfigOnce();
    if (!cfg.enableAds || !cfg.enableRewardedAds) return true;

    final completer = Completer<bool>();

    void _handleShow(RewardedAd ad) {
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          debugPrint('[Ads][Rewarded] Dismissed');
          ad.dispose();
          _cachedAd = null;
          if (!completer.isCompleted) completer.complete(false);
          // Preload next ad immediately
          load(debugReason: 'after_dismiss');
        },
        onAdFailedToShowFullScreenContent: (ad, err) {
          debugPrint('[Ads][Rewarded] Show failed: ${err.code} ${err.message}');
          ad.dispose();
          _cachedAd = null;
          if (!completer.isCompleted) completer.complete(true); // Fail-open
          load(debugReason: 'after_show_fail');
        },
      );

      ad.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        debugPrint('[Ads][Rewarded] Reward earned');
        if (!completer.isCompleted) completer.complete(true);
      });
    }

    if (_cachedAd != null) {
      debugPrint('[Ads][Rewarded] Using cached ad');
      _handleShow(_cachedAd!);
    } else {
      debugPrint('[Ads][Rewarded] No cache, attempting immediate load');
      // No cached ad, try to load one now

      // Resolve IDs again
      bool isAdmin = false;
      try {
        final userModel = await AuthManager().getCurrentUserModel();
        isAdmin = AuthManager().isAdmin(userModel);
      } catch (_) {}

      String adUnitId = Platform.isAndroid
          ? (isAdmin
              ? (cfg.rewardedAdUnitAndroidTest ??
                  ConfigService.testRewardedAndroid)
              : (cfg.rewardedAdUnitAndroid ??
                  ConfigService.testRewardedAndroid))
          : (isAdmin
              ? (cfg.rewardedAdUnitIosTest ?? ConfigService.testRewardedIos)
              : (cfg.rewardedAdUnitIos ?? ConfigService.testRewardedIos));

      if (adUnitId.isEmpty) return true;

      await RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) => _handleShow(ad),
          onAdFailedToLoad: (err) {
            debugPrint('[Ads][Rewarded] Immediate load failed: ${err.message}');
            if (!completer.isCompleted) completer.complete(true); // Fail-open
          },
        ),
      );
    }

    // Safety timeout
    return completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        debugPrint('[Ads][Rewarded] Global timeout; failing open.');
        return true;
      },
    );
  }
}
