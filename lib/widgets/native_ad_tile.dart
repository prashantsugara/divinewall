import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:deva_aura/services/config_service.dart';

class NativeAdTile extends StatefulWidget {
  final bool isAdmin;
  const NativeAdTile({super.key, required this.isAdmin});

  @override
  State<NativeAdTile> createState() => _NativeAdTileState();
}

class _NativeAdTileState extends State<NativeAdTile> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  final ConfigService _config = ConfigService();

  // Test ID for Native Advanced
  static const _testAdUnitId = 'ca-app-pub-3940256099942544/2247696110';

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  Future<void> _loadAd() async {
    final cfg = await _config.getConfigOnce();
    if (!cfg.enableAds || !cfg.enableNativeAds) return;

    String? adUnitId;
    if (Platform.isAndroid) {
      // Use configured ID or fallback to test
      adUnitId = widget.isAdmin
          ? (cfg.nativeAdUnitAndroidTest ?? _testAdUnitId)
          : cfg.nativeAdUnitAndroid;
      debugPrint(
          '[Ads][Native] Android Selection: isAdmin=${widget.isAdmin}, prodId=${cfg.nativeAdUnitAndroid}, testId=${cfg.nativeAdUnitAndroidTest}, Selected=$adUnitId');
    } else if (Platform.isIOS) {
      adUnitId = widget.isAdmin
          ? (cfg.nativeAdUnitIosTest ?? _testAdUnitId)
          : cfg.nativeAdUnitIos;
    }

    if (adUnitId == null) return;

    _nativeAd = NativeAd(
      adUnitId: adUnitId,
      factoryId:
          'listTile', // Must match the factory ID in MainActivity (Android) / AppDelegate (iOS)
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          debugPrint('[Ads][Native] Ad loaded');
          if (mounted) {
            setState(() {
              _isLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[Ads][Native] Failed to load: $error');
          ad.dispose();
        },
      ),
    );

    _nativeAd?.load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _nativeAd == null) {
      // Return empty container or potentially a placeholder?
      // For grid visuals, an empty box might act as "padding".
      // But best to show nothing until loaded.
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Ad Widget
          Positioned.fill(child: AdWidget(ad: _nativeAd!)),
          // "Ad" badge overlay (often included in native template, but good practice to ensure)
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Ad',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
