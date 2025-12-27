import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:deva_aura/auth/auth_manager.dart';
import 'package:deva_aura/services/favorite_service.dart';
import 'package:deva_aura/services/wallpaper_service.dart';
import 'package:deva_aura/models/favorite_model.dart';
import 'package:deva_aura/models/wallpaper_model.dart';
import 'package:deva_aura/screens/wallpaper_viewer_screen.dart';
import 'package:deva_aura/utils/image_url_utils.dart';
import 'package:deva_aura/utils/web_image_proxy.dart';
import 'package:deva_aura/services/auto_wallpaper_service.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final AuthManager _authManager = AuthManager();
  final FavoriteService _favoriteService = FavoriteService();
  final WallpaperService _wallpaperService = WallpaperService();

  String? _userId;
  bool _loading = true;
  DateTime _lastPoolRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final user = await _authManager.getCurrentUserModel();
      if (!mounted) return;
      setState(() {
        _userId = user?.id;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<FavoriteModel>>(
              stream:
                  _favoriteService.getFavoritesStreamForUserOrGuest(_userId),
              builder: (context, favSnap) {
                if (favSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (favSnap.hasError) {
                  return Center(
                    child: Text('Error: ${favSnap.error}'),
                  );
                }

                final favorites = favSnap.data ?? [];
                // If auto-wallpaper is enabled from favorites, refresh pool on changes (debounced)
                () async {
                  try {
                    final settings = await AutoWallpaperSettings.load();
                    if (settings.enabled &&
                        settings.source == AutoWallpaperSource.favorites) {
                      final now = DateTime.now();
                      if (now.difference(_lastPoolRefresh).inSeconds > 30) {
                        _lastPoolRefresh = now;
                        await AutoWallpaperService.instance
                            .refreshPool(currentUserId: _userId);
                      }
                    }
                  } catch (_) {}
                }();
                final ids = favorites.map((f) => f.wallpaperId).toList();
                debugPrint('[Favorites] ids=${ids.join(',')}');

                if (ids.isEmpty) {
                  return const _EmptyState(
                    icon: Icons.favorite_border,
                    title: 'No favorites yet',
                    subtitle: 'Start adding wallpapers to your favorites',
                  );
                }

                // Fetch wallpapers for these IDs. Using FutureBuilder so the UI updates
                // whenever the favorites stream emits a new list.
                return FutureBuilder<List<WallpaperModel>>(
                  future: _wallpaperService.getWallpapersByIds(ids),
                  builder: (context, wSnap) {
                    if (wSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (wSnap.hasError) {
                      return Center(child: Text('Error: ${wSnap.error}'));
                    }
                    var wallpapers = wSnap.data ?? [];
                    // Keep same order as favorites (most recent first)
                    final order = {
                      for (int i = 0; i < ids.length; i++) ids[i]: i
                    };
                    wallpapers.sort((a, b) =>
                        (order[a.id] ?? 0).compareTo(order[b.id] ?? 0));

                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.7,
                      ),
                      itemCount: wallpapers.length,
                      itemBuilder: (context, index) {
                        final w = wallpapers[index];
                        final heroTag = 'fav_${w.id}';
                        final sanitized = ImageUrlUtils.sanitize(
                            w.thumbnailUrl ?? w.imageUrl);
                        final displayUrl = kIsWeb
                            ? WebImageProxy.displayUrl(sanitized)
                            : sanitized;
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => WallpaperViewerScreen(
                                    wallpaper: w,
                                    wallpapers: wallpapers,
                                    initialIndex: index,
                                  ),
                                ),
                              );
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: Hero(
                                    tag: heroTag,
                                    child: kIsWeb
                                        ? Image.network(
                                            displayUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stack) {
                                              debugPrint(
                                                  '[Favorites] image error url=$sanitized proxied=$displayUrl err=$error');
                                              return Container(
                                                color: Colors.grey[300],
                                                child: Icon(Icons.error,
                                                    color: Colors.grey[600]),
                                              );
                                            },
                                          )
                                        : CachedNetworkImage(
                                            imageUrl: displayUrl,
                                            fit: BoxFit.cover,
                                            placeholder: (context, url) =>
                                                Container(
                                              color: Colors.grey[300],
                                              child: const Center(
                                                  child:
                                                      CircularProgressIndicator()),
                                            ),
                                            errorWidget:
                                                (context, url, error) =>
                                                    Container(
                                              color: Colors.grey[300],
                                              child: Icon(Icons.error,
                                                  color: Colors.grey[600]),
                                            ),
                                          ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.favorite,
                                          size: 16, color: Colors.redAccent),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${w.likesCount}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        ],
      ),
    );
  }
}
