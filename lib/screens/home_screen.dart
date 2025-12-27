import 'package:flutter/material.dart';
import 'package:deva_aura/auth/auth_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:deva_aura/models/user_model.dart';
import 'package:deva_aura/models/category_model.dart';
import 'package:deva_aura/services/category_service.dart';
import 'package:deva_aura/screens/login_screen.dart';
import 'package:deva_aura/screens/wallpaper_list_screen.dart';
import 'package:deva_aura/screens/favorites_screen.dart';
import 'package:deva_aura/services/wallpaper_service.dart';
import 'package:deva_aura/models/wallpaper_model.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:deva_aura/utils/image_url_utils.dart';
import 'package:deva_aura/utils/web_image_proxy.dart';
import 'package:deva_aura/widgets/ad_banner.dart';
import 'package:deva_aura/services/interstitial_ad_service.dart';
import 'package:deva_aura/utils/share_download_utils.dart';
import 'package:deva_aura/services/rate_app_service.dart';
import 'package:deva_aura/screens/auto_wallpaper_settings_screen.dart';
import 'package:deva_aura/utils/auto_wallpaper_coach.dart';
import 'package:deva_aura/services/notification_service.dart';
import 'package:deva_aura/services/native_service.dart';
import 'package:deva_aura/services/rewarded_ad_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthManager _authManager = AuthManager();
  final CategoryService _categoryService = CategoryService();
  UserModel? _currentUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // [FIX] Check for pending notification payload after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.consumePendingPayload();
    });
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _authManager.getCurrentUserModel();
      if (mounted) {
        setState(() {
          _currentUser = user;
          _isLoading = false;
        });

        // Post-frame tasks to not block rendering
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Preload interstitial and rewarded ads
          final isAdmin = _authManager.isAdmin(user);
          // Fire-and-forget; don't await
          // ignore: unawaited_futures
          InterstitialAdService().preload(isAdmin: isAdmin);
          // ignore: unawaited_futures
          RewardedAdService.instance.load(debugReason: 'home_startup');

          // Rate app prompt
          RateAppService().bumpLaunchAndMaybePrompt(context);

          // Auto Wallpaper Coach
          AutoWallpaperCoach.checkAndShow(context);

          // [NEW] Schedule Daily Darshan Notifications
          _scheduleNotifications();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _scheduleNotifications() async {
    try {
      final categories = await _categoryService.getCategories();
      await NotificationService.instance
          .scheduleDailyDeityNotifications(categories);
    } catch (e) {
      debugPrint('[HomeScreen] Failed to schedule notifications: $e');
    }
  }

  Future<void> _triggerTestNotification() async {
    // Admin check or Debug Mode
    if (!kDebugMode && !_authManager.isAdmin(_currentUser)) return;

    try {
      final cats = await _categoryService.getCategories();
      if (cats.isNotEmpty && mounted) {
        // [Logic Improvement] Find category for TODAY to verify mapping
        final day = DateTime.now().weekday; // 1=Mon
        final keywords = NotificationService.dayMapping[day] ?? [];

        CategoryModel? targetCat;

        // Find matching category
        for (final cat in cats) {
          final name = cat.name.toLowerCase();
          for (final kw in keywords) {
            if (name.contains(kw.toLowerCase())) {
              targetCat = cat;
              break;
            }
          }
          if (targetCat != null) break;
        }

        // Fallback if no specific deity found for today (or category missing)
        // We still want to test the notification mechanism
        targetCat ??= cats.first;

        final isExactMatch =
            targetCat.id != cats.first.id || keywords.isNotEmpty;

        await NotificationService.instance.showTestNotification(
          title:
              'Test (${isExactMatch ? "Today's Match" : "Fallback"}): ${targetCat.name}',
          body: NotificationService.dayMessages[day] ?? 'Daily Darshan Test',
          payload: 'category:${targetCat.id}',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sent test for: ${targetCat.name}')),
        );
      }
    } catch (e) {
      debugPrint('Test notification failed: $e');
    }
  }

  Future<void> _signOut() async {
    await _authManager.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Future<void> _launchWhatsAppChannel() async {
    final Uri url =
        Uri.parse('https://whatsapp.com/channel/0029VbBZGFN3QxS5t2l5wu0Y');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch WhatsApp channel')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          height: 28,
          child: Image.asset(
            'assets/images/divinewall_logo.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Join WhatsApp Channel',
            icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.green),
            onPressed: _launchWhatsAppChannel,
          ),
          IconButton(
            tooltip: 'Share app',
            icon: const Icon(Icons.share),
            onPressed: () => ShareDownloadUtils.shareAppLink(context: context),
          ),
          IconButton(
            tooltip: 'Daily Darshan settings',
            icon: const Icon(Icons.wallpaper),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const AutoWallpaperSettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.favorite),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FavoritesScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') _signOut();
              if (value == 'auto_wall') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const AutoWallpaperSettingsScreen()),
                );
              }
              if (value == 'rate') {
                RateAppService().requestReviewDirectly(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'auto_wall',
                child: Row(
                  children: const [
                    Icon(Icons.wallpaper),
                    SizedBox(width: 8),
                    Text('Daily Darshan'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'rate',
                child: Row(
                  children: const [
                    Icon(Icons.star_rate_rounded),
                    SizedBox(width: 8),
                    Text('Rate App'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: const [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${_currentUser?.displayName ?? "User"}!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _authManager.isAdmin(_currentUser)
                      ? 'Admin Dashboard'
                      : 'Explore divine wallpapers',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
              ],
            ),
          ),
          // Daily Darshan Banner (Prominent placement)
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 24.0),
            child: _DailyDarshanBanner(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const AutoWallpaperSettingsScreen()),
                );
              },
              onLongPress: (kDebugMode || _authManager.isAdmin(_currentUser))
                  ? _triggerTestNotification
                  : null,
            ),
          ),
          // Banner Ad (edge-to-edge) for welcome/home screen
          AdBanner(
            isAdmin: _authManager.isAdmin(_currentUser),
            placement: BannerPlacement.welcome,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<CategoryModel>>(
              stream: _categoryService.getCategoriesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  final err = snapshot.error.toString();
                  final friendly = err.contains('permission-denied')
                      ? 'You do not have permission to view categories.'
                      : 'Error: $err';
                  return Center(child: Text(friendly));
                }

                final categories = snapshot.data ?? [];

                if (categories.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.category, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'No categories available',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        if (_authManager.isAdmin(_currentUser)) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Add categories from admin panel',
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey[600]),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return _CategoryCard(
                      category: category,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                WallpaperListScreen(category: category),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// [NEW] Prominent Banner for Daily Darshan
class _DailyDarshanBanner extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress; // For testing

  const _DailyDarshanBanner({required this.onTap, this.onLongPress});

  Future<void> _showDebugDialog(BuildContext context) async {
    // Default values
    int selectedDay = DateTime.now().weekday;
    TimeOfDay selectedTime =
        TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 1)));

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Debug Scheduler'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Mock Content Day:'),
                DropdownButton<int>(
                  value: selectedDay,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Monday (Shiva)')),
                    DropdownMenuItem(
                        value: 2, child: Text('Tuesday (Hanuman)')),
                    DropdownMenuItem(
                        value: 3, child: Text('Wednesday (Ganesha)')),
                    DropdownMenuItem(
                        value: 4, child: Text('Thursday (Vishnu)')),
                    DropdownMenuItem(value: 5, child: Text('Friday (Lakshmi)')),
                    DropdownMenuItem(
                        value: 6, child: Text('Saturday (Hanuman)')),
                    DropdownMenuItem(value: 7, child: Text('Sunday (Surya)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => selectedDay = v);
                  },
                ),
                const SizedBox(height: 16),
                const Text('Trigger Time (Today):'),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (t != null) {
                      setState(() => selectedTime = t);
                    }
                  },
                  child: Text(selectedTime.format(context)),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () {
                    NotificationService.instance.showImmediateDebugNotification(
                      mockDay: selectedDay,
                    );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Triggered Instant Notification!')),
                    );
                  },
                  child: const Text('Test Now',
                      style: TextStyle(color: Colors.red))),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await NativeService.instance.testExpiryNotification();
                },
                child: const Text('Test Expiry Notif (Native)'),
              ),
              TextButton(
                onPressed: () async {
                  await NotificationService.instance
                      .checkPendingNotifications();
                  Navigator.of(context).pop();
                },
                child: const Text('Check Pending'),
              ),
              ElevatedButton(
                  onPressed: () {
                    NotificationService.instance.scheduleDebugNotification(
                      mockDay: selectedDay,
                      time: selectedTime,
                    );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Scheduled for ${selectedTime.format(context)}!')),
                    );
                  },
                  child: const Text('Schedule')),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink(); // Hide on web

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade700, Colors.amber.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: () => _showDebugDialog(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Daily Darshan',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Refresh your soul every day automatically',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final CategoryModel category;
  final VoidCallback onTap;
  final WallpaperService _wallpaperService = WallpaperService();

  _CategoryCard({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background thumbnail (any image from this category)
            StreamBuilder<WallpaperModel?>(
              stream: _wallpaperService
                  .getAnyWallpaperInCategoryStream(category.id),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  final w = snapshot.data!;
                  final rawUrl = w.thumbnailUrl ?? w.imageUrl;
                  final safeUrl = ImageUrlUtils.sanitize(rawUrl);
                  return kIsWeb
                      ? Image.network(
                          WebImageProxy.displayUrl(safeUrl),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            color: Colors.grey[300],
                            child: Icon(Icons.broken_image,
                                color: Colors.grey[600]),
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: safeUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              Container(color: Colors.grey[300]),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[300],
                            child: Icon(Icons.broken_image,
                                color: Colors.grey[600]),
                          ),
                        );
                }
                // Fallback placeholder when no wallpapers yet
                return Container(
                  color: Colors.orange.withValues(alpha: 0.1),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.image,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
            ),
            // Gradient overlay for text legibility
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
            ),
            // Category name
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Text(
                category.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  shadows: [
                    Shadow(
                        color: Colors.black54,
                        blurRadius: 4,
                        offset: Offset(0, 1))
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
