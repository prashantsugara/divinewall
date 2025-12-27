import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:deva_aura/auth/auth_manager.dart';
import 'package:deva_aura/screens/login_screen.dart';
import 'package:deva_aura/screens/home_screen.dart';
import 'package:deva_aura/services/config_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthManager _authManager = AuthManager();
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[Splash] initState');
    _startFlow();
  }

  Future<void> _startFlow() async {
    // 1) Non-blocking: attempt to capture a web redirect result if present.
    if (kIsWeb) {
      try {
        debugPrint('[Splash][Web] Checking redirect result...');
        final result = await fb_auth.FirebaseAuth.instance
            .getRedirectResult()
            .timeout(const Duration(seconds: 2));
        if (result.user != null) {
          debugPrint('[Splash] getRedirectResult returned user uid=${result.user!.uid}');
          try {
            await _authManager.ensureCurrentUserDocument();
          } catch (e) {
            debugPrint('[Splash][Warn] ensureCurrentUserDocument after redirect failed: $e');
          }
          try {
            await ConfigService().ensureSeeded();
          } catch (e) {
            debugPrint('[Config][Warn] ensureSeeded after redirect failed: $e');
          }
          if (!mounted) return;
          debugPrint('[Splash] Navigating to Home after redirect');
          _goTo(const HomeScreen());
          return;
        } else {
          debugPrint('[Splash] getRedirectResult returned no user');
        }
      } catch (e) {
        debugPrint('[Splash][Warn] getRedirectResult skipped/failure: $e');
      }
    }

    // 2) Primary decision path: wait for first auth state or time out and decide from currentUser.
    try {
      debugPrint('[Splash] Waiting for first authStateChanges() (timeout 4s)');
      final user = await _authManager.authStateChanges.first
          .timeout(const Duration(seconds: 4));
      if (!mounted || _navigated) return;
      if (user != null) {
        debugPrint('[Splash] authStateChanges -> user present; navigating Home');
        try {
          await ConfigService().ensureSeeded();
        } catch (e) {
          debugPrint('[Config][Warn] ensureSeeded on startup for authenticated user failed: $e');
        }
        _goTo(const HomeScreen());
      } else {
        debugPrint('[Splash] authStateChanges -> no user; navigating Login');
        _goTo(const LoginScreen());
      }
    } on TimeoutException {
      // 3) Timeout fallback: decide from currentUser synchronously.
      if (!mounted || _navigated) return;
      final user = _authManager.currentUser;
      debugPrint('[Splash][Timeout] authStateChanges first() timed out; currentUser=${user?.uid ?? 'null'}');
      _goTo(user != null ? const HomeScreen() : const LoginScreen());
    } catch (e) {
      if (!mounted || _navigated) return;
      debugPrint('[Splash][Error] Unexpected during auth wait: $e');
      final user = _authManager.currentUser;
      _goTo(user != null ? const HomeScreen() : const LoginScreen());
    }

    // 4) Safety net: if for any reason navigation hasn't happened soon, force it.
    Future.delayed(const Duration(seconds: 6), () {
      if (!mounted || _navigated) return;
      final user = _authManager.currentUser;
      debugPrint('[Splash][Watchdog] Forcing navigation (user=${user?.uid ?? 'null'})');
      _goTo(user != null ? const HomeScreen() : const LoginScreen());
    });
  }

  void _goTo(Widget page) {
    if (_navigated || !mounted) return;
    _navigated = true;
    try {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => page),
      );
    } catch (e) {
      debugPrint('[Splash][Error] Navigation failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App logo from assets; falls back to alternate logo, then icon
              SizedBox(
                width: 96,
                height: 96,
                child: Image.asset(
                  'assets/images/divinewall_logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'DivineWall',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Hindu God Wallpapers',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 48),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
