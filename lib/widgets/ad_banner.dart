import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:deva_aura/services/config_service.dart';

/// Banner placements for selecting screen-specific ad unit IDs from config.
enum BannerPlacement { welcome, wallpapers, viewer }

/// A small banner ad widget that respects remote enable/disable flag and
/// selects the ad unit id from Firestore using canonical per-screen keys.
class AdBanner extends StatefulWidget {
  final bool isAdmin; // kept for compatibility, no longer used for id selection
  final BannerPlacement placement;
  const AdBanner({super.key, required this.isAdmin, required this.placement});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  final ConfigService _configService = ConfigService();
  BannerAd? _bannerAd;
  AdSize? _adSize;
  bool _loading = true;
  bool _enabled = false;

  static const String _testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';

  @override
  void initState() {
    super.initState();
    // Do not attempt to load ads on web.
    if (kIsWeb) {
      _loading = false;
      _enabled = false;
      return;
    }
    _loadConfigAndAd();
  }

  Future<void> _loadConfigAndAd() async {
    try {
      final cfg = await _configService.getConfigOnce();
      final enabled = cfg.enableAds && cfg.enableBannerAds;
      debugPrint('[Ads] Config loaded: enable_ad=$enabled');
      if (!enabled) {
        setState(() {
          _enabled = false;
          _loading = false;
        });
        return;
      }
      String? adUnitId;
      final place = widget.placement.name;
      final platformLabel = !kIsWeb && Platform.isAndroid
          ? 'android'
          : (!kIsWeb && Platform.isIOS ? 'ios' : 'other');

      // Admins should always see test ads. Prefer role-specific admin id
      // (defaults to Google test ids via ConfigService) or fall back to
      // platform test ids.
      if (!kIsWeb && widget.isAdmin) {
        if (Platform.isAndroid) {
          adUnitId =
              cfg.bannerAdUnitAndroidAdmin ?? ConfigService.testBannerAndroid;
        } else if (Platform.isIOS) {
          adUnitId = cfg.bannerAdUnitIosAdmin ?? ConfigService.testBannerIos;
        }
        debugPrint(
            '[Ads] Admin detected, forcing test banner id for place=$place on $platformLabel: $adUnitId');
      } else {
        if (!kIsWeb && Platform.isAndroid) {
          switch (widget.placement) {
            case BannerPlacement.welcome:
              adUnitId = cfg.bannerWelcomeAdUnitAndroid ??
                  cfg.bannerAdUnitAndroid ??
                  _testBannerAndroid;
              break;
            case BannerPlacement.wallpapers:
              adUnitId = cfg.bannerWallpapersAdUnitAndroid ??
                  cfg.bannerAdUnitAndroid ??
                  _testBannerAndroid;
              break;
            case BannerPlacement.viewer:
              // Fallback to generic if specific not set
              adUnitId = cfg.bannerViewerAdUnitAndroid ??
                  cfg.bannerAdUnitAndroid ??
                  _testBannerAndroid;
              break;
          }
        } else if (!kIsWeb && Platform.isIOS) {
          switch (widget.placement) {
            case BannerPlacement.welcome:
              adUnitId = cfg.bannerWelcomeAdUnitIos ??
                  cfg.bannerAdUnitIos ??
                  _testBannerIos;
              break;
            case BannerPlacement.wallpapers:
              adUnitId = cfg.bannerWallpapersAdUnitIos ??
                  cfg.bannerAdUnitIos ??
                  _testBannerIos;
              break;
            case BannerPlacement.viewer:
              adUnitId = cfg.bannerViewerAdUnitIos ??
                  cfg.bannerAdUnitIos ??
                  _testBannerIos;
              break;
          }
        }
        debugPrint(
            '[Ads] Selected banner id for place=$place on $platformLabel: $adUnitId');
      }

      if (adUnitId == null || adUnitId!.isEmpty) {
        debugPrint('[Ads] No ad unit id configured for this platform.');
        setState(() {
          _enabled = false;
          _loading = false;
        });
        return;
      }

      // Determine full-width adaptive size for the current orientation.
      AdSize size = AdSize.banner;
      try {
        final width = MediaQuery.of(context).size.width.truncate();
        // Prefer anchored adaptive banner size if supported.
        final adaptive =
            await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
                width);
        if (adaptive != null) {
          size = adaptive;
        }
      } catch (_) {/* fallback to standard banner */}

      debugPrint(
          '[Ads][Banner] Loading Ad: placement=${widget.placement}, isAdmin=${widget.isAdmin}, id=$adUnitId');
      final banner = BannerAd(
        adUnitId: adUnitId!,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted) return;
            debugPrint('[Ads] Banner loaded with unit: $adUnitId');
            setState(() {
              _bannerAd = ad as BannerAd;
              _adSize = size;
              _enabled = true;
              _loading = false;
            });
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint(
                '[Ads] Banner failed to load: ${error.code} ${error.message}');
            ad.dispose();
            if (!mounted) return;
            setState(() {
              _bannerAd = null;
              _enabled = false;
              _loading = false;
            });
          },
        ),
      );

      await banner.load();
    } catch (e) {
      debugPrint('[Ads] Failed to init banner: $e');
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_enabled || _bannerAd == null) {
      return const SizedBox.shrink();
    }
    final height = (_adSize ?? _bannerAd!.size).height.toDouble();
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Center(
        child: SizedBox(
          width: (_adSize ?? _bannerAd!.size).width.toDouble(),
          height: height,
          child: AdWidget(ad: _bannerAd!),
        ),
      ),
    );
  }
}
