import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deva_aura/screens/onboarding_screen.dart';

class AutoWallpaperCoach {
  /// checks if we should show the onboarding, and if so, shows it.
  static Future<void> checkAndShow(BuildContext context) async {
    // Delegate to the new Onboarding Screen logic
    await OnboardingScreen.checkAndShow(context);
  }

  /// For testing/debug: helper to reset the flag
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('onboarding_shown_v1');
  }
}
