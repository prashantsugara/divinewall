import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const String _kKey = 'onboarding_shown_v1';

  /// Shortcut to check and navigate if needed
  static Future<void> checkAndShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyShown = prefs.getBool(_kKey) ?? false;

    if (alreadyShown) return;

    if (!context.mounted) return;

    // In a real app, you might use Navigator.pushReplacement or a specific route.
    // Here we'll show it as a full-screen dialog or a route.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
    );
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingData> _pages = [
    OnboardingData(
      title: 'Divine Quality',
      description:
          'Experience the divine in stunning 4K and Ultra HD. Hand-picked wallpapers that bring peace to your soul.',
      imagePath: 'assets/images/onboarding_1.png',
      color: Colors.orange,
    ),
    OnboardingData(
      title: 'Daily Darshan',
      description:
          'Let the divine blessing reach you automatically. Set your favorite categories and see a new wallpaper every day.',
      imagePath: 'assets/images/onboarding_2.png',
      color: Colors.deepOrange,
    ),
    OnboardingData(
      title: 'Create & Share',
      description:
          'Express your devotion with our Status Maker. Create beautiful status cards with Sanskrit quotes and share with your loved ones.',
      imagePath: 'assets/images/onboarding_3.png',
      color: Colors.redAccent,
    ),
  ];

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen._kKey, true);
    if (!mounted) return;
    Navigator.of(context).pop(); // Go back to Home
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _pages.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              return OnboardingPageWidget(data: _pages[index]);
            },
          ),

          // Navigation / Indicators
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Page Indicator
                Row(
                  children: List.generate(_pages.length, (index) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(right: 8),
                      height: 8,
                      width: _currentPage == index ? 24 : 8,
                      decoration: BoxDecoration(
                        color: _pages[_currentPage].color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),

                // Button
                _currentPage == _pages.length - 1
                    ? FilledButton(
                        onPressed: _completeOnboarding,
                        style: FilledButton.styleFrom(
                          backgroundColor: _pages[_currentPage].color,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Get Started'),
                      )
                    : IconButton(
                        onPressed: () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                          );
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: _pages[_currentPage].color,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.arrow_forward),
                      ),
              ],
            ),
          ),

          // Skip Button
          Positioned(
            top: 50,
            right: 16,
            child: TextButton(
              onPressed: _completeOnboarding,
              child: Text(
                'Skip',
                style: TextStyle(
                    color: Colors.grey[600], fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingData {
  final String title;
  final String description;
  final String imagePath;
  final Color color;

  OnboardingData({
    required this.title,
    required this.description,
    required this.imagePath,
    required this.color,
  });
}

class OnboardingPageWidget extends StatelessWidget {
  final OnboardingData data;
  const OnboardingPageWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 6,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(data.imagePath),
                fit: BoxFit.cover,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.1),
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: data.color,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  data.description,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.grey[700],
                        height: 1.5,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40), // Space for indicator/button
              ],
            ),
          ),
        ),
      ],
    );
  }
}
