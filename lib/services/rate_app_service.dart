import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A small helper to gently prompt users to rate the app, with a "Later" deferral.
///
/// Behavior
/// - Only shows on mobile (Android/iOS). Skips web/desktop.
/// - Shows after a few launches, then respects a cooldown when user taps Later.
class RateAppService {
  static const _kOpensKey = 'rate_app_opens';
  static const _kLastPromptAtKey = 'rate_last_prompt_at';
  static const _kDoNotPromptAgainKey = 'rate_do_not_prompt_again';

  // After how many app opens we should show the first prompt.
  static const int _opensThreshold =
      1; // [DEBUG] Reduced from 3 for easier testing

  // Cooldown between prompts when user taps "Later" (in days).
  static const int _laterCooldownDays = 7;

  // Android Play Store applicationId
  static const String _androidAppId = 'com.bittruth.gwallpaper';

  Future<void> bumpLaunchAndMaybePrompt(BuildContext context) async {
    if (kIsWeb) return; // Skip web

    // Limit to mobile platforms using defaultTargetPlatform to avoid dart:io.
    final platform = defaultTargetPlatform;
    final isMobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    if (!isMobile) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      // Respect a final opt-out if user already chose to rate.
      final doNotPrompt = prefs.getBool(_kDoNotPromptAgainKey) ?? false;
      if (doNotPrompt) {
        return;
      }
      final opens = (prefs.getInt(_kOpensKey) ?? 0) + 1;
      await prefs.setInt(_kOpensKey, opens);
      debugPrint('[RateApp] App opens: $opens (Threshold: $_opensThreshold)');

      final lastPromptMs = prefs.getInt(_kLastPromptAtKey) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final cooldownMs = Duration(days: _laterCooldownDays).inMilliseconds;

      final isPastCooldown =
          lastPromptMs == 0 || (nowMs - lastPromptMs) > cooldownMs;

      if (!isPastCooldown) {
        debugPrint(
            '[RateApp] Rate prompt skipped: In cooldown (Last: $lastPromptMs).');
      }

      if (opens >= _opensThreshold && isPastCooldown) {
        debugPrint('[RateApp] Conditions met. Checking availability...');
        // Check availability before triggering
        final review = InAppReview.instance;
        final available = await review.isAvailable();
        debugPrint('[RateApp] InAppReview isAvailable: $available');

        if (available) {
          debugPrint('[RateApp] Requesting review...');
          // [UX] Trigger native review dialog directly.
          await review.requestReview();

          // We set the "last prompt" time and "do not prompt again" flag.
          await prefs.setInt(
              _kLastPromptAtKey, DateTime.now().millisecondsSinceEpoch);
          await prefs.setBool(_kDoNotPromptAgainKey, true);
        } else {
          debugPrint('[RateApp] Review API not available.');
          if (kDebugMode && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      '[Debug] In-App Review unavailable (Debug/Emulator)')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[RateApp] Error while checking prompt conditions: $e');
    }
  }

  /// Directly opens the store listing or native review request, ignoring cooldowns.
  /// Used for manual "Rate App" buttons.
  /// Directly opens the store listing or native review request, ignoring cooldowns.
  /// Used for manual "Rate App" buttons.
  Future<void> requestReviewDirectly(BuildContext context) async {
    // [DEBUG] Show toast instead of real prompt
    if (kDebugMode) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('[Debug] Manual Rate: Would open Store/Review'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final review = InAppReview.instance;
    // For manual requests, we fallback to store listing if native dialog isn't available
    if (await review.isAvailable()) {
      await review.requestReview();
    } else {
      await review.openStoreListing(appStoreId: _androidAppId);
    }
  }

  // _handleRateNow and _showBottomSheet removed as they are no longer needed
  // or integrated directly into the methods above for clarity.

  /// Checks if the user is eligible for a rating prompt (cooldown passed, not opted out).
  /// Does NOT increment open counts or trigger the prompt.
  Future<bool> shouldPrompt({bool ignoreCooldown = false}) async {
    if (kIsWeb) return false;
    final platform = defaultTargetPlatform;
    final isMobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    if (!isMobile) return false;

    // [DEBUG/ADMIN] Skip all checks if ignoreCooldown is true
    if (ignoreCooldown) return true;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kDoNotPromptAgainKey) ?? false) return false;

      final lastPromptMs = prefs.getInt(_kLastPromptAtKey) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final cooldownMs = Duration(days: _laterCooldownDays).inMilliseconds;

      return lastPromptMs == 0 || (nowMs - lastPromptMs) > cooldownMs;
    } catch (e) {
      debugPrint('[RateApp] shouldPrompt error: $e');
      return false;
    }
  }

  /// Triggers the rating prompt immediately (if available) and updates the "last prompt" time.
  /// Call this ONLY if you have established that a prompt should be shown.
  Future<void> promptAfterAction(BuildContext context,
      {bool isAdmin = false}) async {
    debugPrint('[RateApp] promptAfterAction called.');

    // [DEBUG/ADMIN] Show toast instead of real prompt
    if (kDebugMode || isAdmin) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('[Debug/Admin] Rating Prompt would appear here'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      // We do NOT set the permanent "do not prompt again" flag here to allow repeated testing.
      // But we might want to update the timestamp to test cooldowns?
      // User just said "instead of popping", implying visual verification.
      // I will update the timestamp but NOT the permanent opt-out so they can test again after cooldown (or clear data).
      // Actually, for true debug, let's not set anything so they can test "Either Ad or Rating" logic freely?
      // No, the "Either Ad or Rating" logic RELIES on the state being persisted (cooldown).
      // So I MUST persist state to verify the flow works (i.e. next time they should see an Ad).
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _kLastPromptAtKey, DateTime.now().millisecondsSinceEpoch);
      // await prefs.setBool(_kDoNotPromptAgainKey, true); // Uncomment to test "never again"
      return;
    }

    try {
      final review = InAppReview.instance;
      final available = await review.isAvailable();

      if (available) {
        debugPrint('[RateApp] Requesting review (Action Trigger)...');
        await review.requestReview();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            _kLastPromptAtKey, DateTime.now().millisecondsSinceEpoch);
        await prefs.setBool(_kDoNotPromptAgainKey, true);
      } else {
        debugPrint('[RateApp] Review API not available (Action Trigger).');
      }
    } catch (e) {
      debugPrint('[RateApp] Error in promptAfterAction: $e');
    }
  }
}
