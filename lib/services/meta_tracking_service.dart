import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Facebook App Events
import 'package:facebook_app_events/facebook_app_events.dart';

/// Handles Meta (Facebook) App Events initialization and basic install/session tracking.
///
/// Notes for setup (replace placeholders in platform configs):
/// - Android: set strings.xml values facebook_app_id and facebook_client_token.
/// - iOS: set FacebookAppID and FacebookClientToken in Info.plist.
/// - iOS (optional): request tracking authorization if you plan to use IDFA.
class MetaTrackingService {
  MetaTrackingService._();
  static final MetaTrackingService _i = MetaTrackingService._();
  factory MetaTrackingService() => _i;

  final FacebookAppEvents _fb = FacebookAppEvents();
  bool _initialized = false;

  static const _kFirstOpenLogged = 'meta_first_open_logged';

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) return; // Not supported on web
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    try {
      // Enable automatic tracking where supported
      await _fb.setAutoLogAppEventsEnabled(true);

      // Log install/activation event once per install
      final prefs = await SharedPreferences.getInstance();
      final already = prefs.getBool(_kFirstOpenLogged) ?? false;
      if (!already) {
        try {
          await _fb.logEvent(name: 'fb_mobile_activate_app');
          await prefs.setBool(_kFirstOpenLogged, true);
          debugPrint('[Meta] Logged first activation event');
        } catch (e) {
          debugPrint('[Meta][Warn] logActivatedApp failed: $e');
        }
      }

      // Also log a generic app open for each launch
      try {
        await _fb.logEvent(name: 'fb_mobile_app_open');
      } catch (e) {
        debugPrint('[Meta][Warn] app open event failed: $e');
      }

      _initialized = true;
      debugPrint('[Meta] App Events initialized');
    } catch (e) {
      debugPrint('[Meta][Error] Initialization failed: $e');
    }
  }
}
