import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import 'package:deva_aura/models/wallpaper_model.dart';
import 'package:deva_aura/services/wallpaper_service.dart';
import 'package:deva_aura/utils/share_download_utils.dart';
import 'package:deva_aura/utils/wallpaper_setter.dart';
import 'package:deva_aura/utils/image_url_utils.dart';
import 'package:deva_aura/utils/web_image_proxy.dart';
import 'package:deva_aura/services/favorite_service.dart';
import 'package:deva_aura/auth/auth_manager.dart';
import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:deva_aura/screens/wallpaper_edit_screen.dart';
import 'package:deva_aura/screens/status_maker_screen.dart'; // [NEW]
import 'package:deva_aura/screens/auto_wallpaper_settings_screen.dart'; // [NEW]
import 'package:deva_aura/services/interstitial_ad_service.dart'; // [NEW]
import 'package:deva_aura/services/rewarded_ad_service.dart'; // [NEW]
import 'package:deva_aura/services/rate_app_service.dart'; // [NEW]
import 'package:deva_aura/widgets/ad_banner.dart'; // [NEW]
import 'package:shared_preferences/shared_preferences.dart'; // [NEW]

class WallpaperViewerScreen extends StatefulWidget {
  final WallpaperModel wallpaper;
  // Optional list of wallpapers to enable left/right swipe navigation
  final List<WallpaperModel>? wallpapers;
  // Optional initial index in the provided list
  final int? initialIndex;

  const WallpaperViewerScreen({
    super.key,
    required this.wallpaper,
    this.wallpapers,
    this.initialIndex,
  });

  @override
  State<WallpaperViewerScreen> createState() => _WallpaperViewerScreenState();
}

class _WallpaperViewerScreenState extends State<WallpaperViewerScreen> {
  final WallpaperService _wallpaperService = WallpaperService();
  final FavoriteService _favoriteService = FavoriteService();
  final AuthManager _authManager = AuthManager();
  bool _busy = false;
  bool _isFavorite = false;
  String? _userId;
  bool _isAdmin = false;
  WallpaperScreenTarget _lastTarget = WallpaperScreenTarget.home;
  WallpaperColorTone _lastLockTone = WallpaperColorTone.normal;
  late List<WallpaperModel> _pages;
  late int _index;
  bool _showHeart = false;
  PageController? _pageController;
  final Map<String, File> _localOverrides = {};

  WallpaperModel get _current => _pages[_index];

  @override
  void initState() {
    super.initState();
    _pages = (widget.wallpapers != null && widget.wallpapers!.isNotEmpty)
        ? List<WallpaperModel>.from(widget.wallpapers!)
        : <WallpaperModel>[widget.wallpaper];
    _index = (widget.initialIndex != null &&
            widget.initialIndex! >= 0 &&
            widget.initialIndex! < _pages.length)
        ? widget.initialIndex!
        : (_pages.indexWhere((w) => w.id == widget.wallpaper.id) >= 0
            ? _pages.indexWhere((w) => w.id == widget.wallpaper.id)
            : 0);
    if (_pages.length > 1) {
      _pageController = PageController(initialPage: _index);
    }
    _loadFavoriteState();
    // [NEW] Preload rewarded ad when opening viewer to improve match rate
    RewardedAdService.instance.load(debugReason: 'viewer_open');
  }

  Future<void> _loadFavoriteState() async {
    try {
      final user = await _authManager.getCurrentUserModel();
      if (!mounted) return;
      // [FIX] Use raw auth ID if model is missing (Anonymous users)
      _userId = user?.id ?? _authManager.currentUser?.uid;
      _isAdmin = _authManager.isAdmin(user);
      final fav =
          await _favoriteService.isFavoriteForUserOrGuest(_userId, _current.id);
      if (mounted) setState(() => _isFavorite = fav);
    } catch (e) {
      // ignore; non-blocking
    }
  }

  Future<void> _share() async {
    await ShareDownloadUtils.shareImageFileWithAppLink(
      imageUrl: _current.imageUrl,
      // Do not include filename/title in the share text; only app link
      title: null,
      appLink:
          'https://play.google.com/store/apps/details?id=com.bittruth.gwallpaper',
      context: context,
    );
  }

  Future<void> _confirmAndDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete wallpaper?'),
        content: const Text(
            'This will permanently remove the image and its record.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      final toDelete = _current;
      await _wallpaperService.deleteWallpaperWithStorage(toDelete);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wallpaper deleted')),
      );
      // If we have a pager with more items, remove the page locally and stay
      if (_pages.length > 1) {
        setState(() {
          _pages.removeAt(_index);
          if (_index >= _pages.length) {
            _index = _pages.length - 1;
          }
        });
        // Refresh favorite state for the new current item
        await _loadFavoriteState();
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final ok = await ShareDownloadUtils.downloadImage(
        imageUrl: _current.imageUrl,
        suggestedName: _current.title.replaceAll(' ', '_'),
        context: context,
      );
      if (ok) {
        // [NEW] Show interstitial after successful download
        if (mounted) {
          InterstitialAdService()
              .showAfterTap(isAdmin: _isAdmin, onComplete: () {});
        }

        try {
          await _wallpaperService.incrementDownloadCount(_current.id);
        } catch (e) {
          debugPrint('[Viewer] incrementDownloadCount failed: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAsWallpaper() async {
    final selection = await showModalBottomSheet<WallpaperApplyOptions>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => WallpaperApplySheet(
        initialTarget: _lastTarget,
        initialLockTone: _lastLockTone,
      ),
    );
    if (selection == null) return;

    // [NEW] Logic for Rewarded Ad vs Rating Prompt (Mutual Exclusion)
    final prefs = await SharedPreferences.getInstance();
    final hasUsedBefore = prefs.getBool('manual_wall_has_used_before') ?? false;

    // Check if we plan to rate this user
    final rateService = RateAppService();
    // [DEBUG/ADMIN] If admin, we ignore cooldown to allow testing the "Rate vs Ad" flow repeatedly
    final willPromptRating =
        await rateService.shouldPrompt(ignoreCooldown: _isAdmin);

    // Determine if we should show ad:
    // 1. Not if admin
    // 2. Not if first time
    // 3. Not if we are planning to ask for a rating (Give them a "rating bonus")
    final shouldShowAd = !_isAdmin && hasUsedBefore && !willPromptRating;

    if (shouldShowAd) {
      setState(() => _busy = true);
      try {
        final ok = await RewardedAdService.instance
            .showReward(debugReason: 'manual_set_wallpaper');
        if (!ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Watch full ad to apply wallpaper')),
            );
          }
          return;
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    } else {
      if (!hasUsedBefore) debugPrint('[Viewer] First time apply - skipping ad');
      if (willPromptRating)
        debugPrint(
            '[Viewer] Rate prompt due - skipping ad for rating opportunity');
    }

    setState(() {
      _busy = true;
      _lastTarget = selection.target;
      _lastLockTone = selection.lockColorTone;
    });
    try {
      final success = await wallpaperSetter.setFromUrl(
        _current.imageUrl,
        options: selection,
      );
      if (success) {
        if (mounted) {
          // [UPDATED] Mark first time as done after successful applying
          if (!hasUsedBefore) {
            await prefs.setBool('manual_wall_has_used_before', true);
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Wallpaper applied'),
              duration: Duration(milliseconds: 1500),
            ),
          );

          // Trigger rating prompt ONLY if we agreed to it (and skipped ad accordingly)
          if (willPromptRating) {
            await rateService.promptAfterAction(context, isAdmin: _isAdmin);
          }
        }
        try {
          await _wallpaperService.incrementDownloadCount(_current.id);
        } catch (e) {
          debugPrint('[Viewer] incrementDownloadCount failed: $e');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(kIsWeb
                  ? 'Setting wallpaper is not supported on web. Please download the Android app.'
                  : 'Unable to set wallpaper on this platform.'),
              duration: const Duration(milliseconds: 1500),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFavorite() async {
    final currentModel = _current;
    final oldFav = _isFavorite;
    final oldCount = currentModel.likesCount;

    // Optimistically update UI
    setState(() {
      if (_isFavorite) {
        _isFavorite = false;
        // Decrement
        _pages[_index] = currentModel.copyWith(
            likesCount: (currentModel.likesCount - 1).clamp(0, 9999999));
      } else {
        _isFavorite = true;
        _showHeart = true; // Show animation
        // Increment
        _pages[_index] =
            currentModel.copyWith(likesCount: currentModel.likesCount + 1);

        // Hide heart after delay
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) setState(() => _showHeart = false);
        });
      }
    });

    try {
      if (oldFav) {
        await _favoriteService.removeFavoriteForUserOrGuest(
            _userId, currentModel.id);
      } else {
        await _favoriteService.addFavoriteForUserOrGuest(
            _userId, currentModel.id);
      }
    } catch (e) {
      // Revert if failed
      if (!mounted) return;
      setState(() {
        _isFavorite = oldFav;
        _pages[_index] = currentModel.copyWith(likesCount: oldCount);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update favorite: $e')),
      );
    }
  }

  Future<void> _openEditor() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Editing not supported on web')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      // 1. Download/Cache file
      final file = await DefaultCacheManager().getSingleFile(_current.imageUrl);
      if (!mounted) return;

      // 2. Open Editor
      final resultFile = await Navigator.push<File>(
        context,
        MaterialPageRoute(
          builder: (_) => WallpaperEditScreen(originalFile: file),
        ),
      );

      if (resultFile != null && mounted) {
        // 3. If saved, prompt to set as wallpaper immediately
        // We don't replace the original in the list/server, just use it for setting.
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Apply edits?'),
            content: Image.file(resultFile, height: 200),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Set as Wallpaper')),
            ],
          ),
        );

        if (confirm == true && mounted) {
          final selection = await showModalBottomSheet<WallpaperApplyOptions>(
            context: context,
            useSafeArea: true,
            isScrollControlled: true,
            builder: (_) => WallpaperApplySheet(
              initialTarget: _lastTarget,
              initialLockTone: _lastLockTone,
            ),
          );
          if (selection != null) {
            setState(() {
              _busy = true;
              _lastTarget = selection.target;
              _lastLockTone = selection.lockColorTone;
            });

            final success = await wallpaperSetter.setFromFile(resultFile.path,
                options: selection);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        success ? 'Wallpaper applied' : 'Failed to apply')),
              );
              if (success) {
                // Update local override to show the edited version in the viewer
                setState(() {
                  _localOverrides[_current.id] = resultFile;
                });
              }
            }
            setState(() => _busy =
                false); // explicitly here because we skip finally block for this flow
            return;
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Edit failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openStatusMaker() async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatusMakerScreen(wallpaper: _current),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heroTag = 'wallpaper_${_current.id}';
    final imgUrl = ImageUrlUtils.sanitize(_current.imageUrl);
    final displayUrl = WebImageProxy.displayUrl(imgUrl);

    // Determine provider for Single View
    ImageProvider? singleProvider;
    if (_localOverrides.containsKey(_current.id)) {
      singleProvider = FileImage(_localOverrides[_current.id]!);
    } else {
      singleProvider = kIsWeb
          ? NetworkImage(displayUrl)
          : CachedNetworkImageProvider(imgUrl);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (img, result) async {
        if (img) return;
        Navigator.of(context).pop(_pages);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            // [UX] Banner Ad moved to TOP to avoid conflict with "Set Wallpaper" button
            AdBanner(isAdmin: _isAdmin, placement: BannerPlacement.viewer),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Main Image Layer
                  _pages.length <= 1
                      ? Center(
                          child: GestureDetector(
                            onDoubleTap: _toggleFavorite,
                            child: PhotoView(
                              heroAttributes:
                                  PhotoViewHeroAttributes(tag: heroTag),
                              imageProvider: singleProvider!,
                              backgroundDecoration:
                                  const BoxDecoration(color: Colors.black),
                              minScale: PhotoViewComputedScale.contained,
                              maxScale: PhotoViewComputedScale.covered * 3.0,
                              loadingBuilder: (context, event) {
                                if (_localOverrides.containsKey(_current.id)) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                return Center(
                                  child: CachedNetworkImage(
                                    imageUrl: ImageUrlUtils.sanitize(
                                        _current.thumbnailUrl ??
                                            _current.imageUrl),
                                    fit: BoxFit.contain,
                                    placeholder: (context, url) => const Center(
                                        child: CircularProgressIndicator()),
                                    errorWidget: (context, url, error) =>
                                        const Icon(Icons.broken_image,
                                            color: Colors.white),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Icon(Icons.broken_image,
                                      color: Colors.white, size: 48),
                                );
                              },
                            ),
                          ),
                        )
                      : PageView.builder(
                          controller: _pageController,
                          onPageChanged: (i) async {
                            setState(() {
                              _index = i;
                            });
                            await _loadFavoriteState();
                          },
                          itemCount: _pages.length,
                          itemBuilder: (context, i) {
                            final w = _pages[i];
                            final u = ImageUrlUtils.sanitize(w.imageUrl);
                            final d = WebImageProxy.displayUrl(u);

                            ImageProvider itemProvider;
                            if (_localOverrides.containsKey(w.id)) {
                              itemProvider = FileImage(_localOverrides[w.id]!);
                            } else {
                              itemProvider = kIsWeb
                                  ? NetworkImage(d)
                                  : CachedNetworkImageProvider(u);
                            }

                            return Center(
                              child: GestureDetector(
                                onDoubleTap: _toggleFavorite,
                                child: PhotoView(
                                  heroAttributes: PhotoViewHeroAttributes(
                                      tag: 'wallpaper_${w.id}'),
                                  imageProvider: itemProvider,
                                  backgroundDecoration:
                                      const BoxDecoration(color: Colors.black),
                                  minScale: PhotoViewComputedScale.contained,
                                  maxScale:
                                      PhotoViewComputedScale.covered * 3.0,
                                  loadingBuilder: (context, event) {
                                    if (_localOverrides.containsKey(w.id)) {
                                      return const Center(
                                          child: CircularProgressIndicator());
                                    }
                                    return Center(
                                      child: CachedNetworkImage(
                                        imageUrl: ImageUrlUtils.sanitize(
                                            w.thumbnailUrl ?? w.imageUrl),
                                        fit: BoxFit.contain,
                                        placeholder: (context, url) =>
                                            const Center(
                                                child:
                                                    CircularProgressIndicator()),
                                        errorWidget: (context, url, error) =>
                                            const Icon(Icons.broken_image,
                                                color: Colors.white),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Center(
                                    child: Icon(Icons.broken_image,
                                        color: Colors.white, size: 48),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                  // Heart Animation Overlay
                  if (_showHeart)
                    const Center(
                      child: Icon(Icons.favorite,
                          color: Colors.white,
                          size: 100,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 20)
                          ]),
                    ),

                  // 2. Top Gradient Overlay (AppBar replacement)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 120,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.7),
                            Colors.transparent
                          ],
                        ),
                      ),
                      child: SafeArea(
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back,
                                  color: Colors.white),
                              onPressed: () =>
                                  Navigator.of(context).pop(_pages),
                            ),
                            Expanded(
                              child: Text(
                                _current.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 4)
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_isAdmin)
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete,
                                    color: Colors.redAccent),
                                onPressed: _busy ? null : _confirmAndDelete,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 3. Bottom Gradient Overlay & Controls
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.9),
                            Colors.transparent
                          ],
                          stops: const [0.0, 1.0],
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.only(
                              left: 20, right: 20, bottom: 20, top: 40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Action Row (Likes, Dl, Share, AutoSettings)
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  // Like Button
                                  InkWell(
                                    onTap: _busy ? null : _toggleFavorite,
                                    borderRadius: BorderRadius.circular(24),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _isFavorite
                                                ? Icons.favorite
                                                : Icons.favorite_border,
                                            color: _isFavorite
                                                ? Colors.redAccent
                                                : Colors.white,
                                            size: 28,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${_current.likesCount}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  _ActionIcon(
                                      icon: Icons.share_rounded,
                                      tooltip: 'Share',
                                      onPressed: _share,
                                      busy: _busy),
                                  _ActionIcon(
                                      icon: Icons.edit,
                                      tooltip: 'Edit',
                                      onPressed: _openEditor,
                                      busy: _busy),
                                  _ActionIcon(
                                      icon: Icons.download_rounded,
                                      tooltip: 'Download',
                                      onPressed: _download,
                                      busy: _busy),
                                  _ActionIcon(
                                      icon: Icons.auto_awesome_motion,
                                      tooltip: 'Create Status',
                                      onPressed: _openStatusMaker,
                                      busy: _busy),
                                  _ActionIcon(
                                      icon: Icons.wallpaper,
                                      tooltip: 'Daily Darshan',
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  const AutoWallpaperSettingsScreen()),
                                        );
                                      },
                                      busy: _busy),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Set Wallpaper Button
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: FilledButton(
                                  onPressed: _busy ? null : _setAsWallpaper,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(28)),
                                    elevation: 0,
                                  ),
                                  child: _busy
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Text('Set as Wallpaper',
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool busy;
  final String tooltip;

  const _ActionIcon(
      {required this.icon,
      required this.onPressed,
      required this.busy,
      required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: Colors.white, size: 26),
      onPressed: busy ? null : onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.1),
        padding: const EdgeInsets.all(12),
      ),
    );
  }
}

class WallpaperApplySheet extends StatefulWidget {
  const WallpaperApplySheet({
    super.key,
    required this.initialTarget,
    required this.initialLockTone,
  });

  final WallpaperScreenTarget initialTarget;
  final WallpaperColorTone initialLockTone;

  @override
  State<WallpaperApplySheet> createState() => _WallpaperApplySheetState();
}

class _WallpaperApplySheetState extends State<WallpaperApplySheet> {
  late WallpaperScreenTarget _target;
  late WallpaperColorTone _lockTone;

  bool get _includesLockScreen => _target != WallpaperScreenTarget.home;

  @override
  void initState() {
    super.initState();
    _target = widget.initialTarget;
    _lockTone = widget.initialLockTone;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text('Set wallpaper',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Choose where to apply this wallpaper.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TargetChip(
                    icon: Icons.home,
                    label: 'Home screen',
                    description: 'Unlocked screen',
                    target: WallpaperScreenTarget.home,
                    selected: _target == WallpaperScreenTarget.home,
                    onSelected: () =>
                        setState(() => _target = WallpaperScreenTarget.home),
                  ),
                  _TargetChip(
                    icon: Icons.lock,
                    label: 'Lock screen',
                    description: 'Shown when locked',
                    target: WallpaperScreenTarget.lock,
                    selected: _target == WallpaperScreenTarget.lock,
                    onSelected: () =>
                        setState(() => _target = WallpaperScreenTarget.lock),
                  ),
                  _TargetChip(
                    icon: Icons.mobile_friendly,
                    label: 'Both',
                    description: 'Home + lock',
                    target: WallpaperScreenTarget.both,
                    selected: _target == WallpaperScreenTarget.both,
                    onSelected: () =>
                        setState(() => _target = WallpaperScreenTarget.both),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _includesLockScreen
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Lock screen style',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                avatar: const Icon(Icons.palette, size: 18),
                                label: const Text('Normal color'),
                                selected:
                                    _lockTone == WallpaperColorTone.normal,
                                onSelected: (_) => setState(() =>
                                    _lockTone = WallpaperColorTone.normal),
                              ),
                              ChoiceChip(
                                avatar:
                                    const Icon(Icons.invert_colors, size: 18),
                                label: const Text('Black & white'),
                                selected: _lockTone ==
                                    WallpaperColorTone.blackAndWhite,
                                onSelected: (_) => setState(() => _lockTone =
                                    WallpaperColorTone.blackAndWhite),
                              ),
                            ],
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(
                  WallpaperApplyOptions(
                      target: _target, lockColorTone: _lockTone),
                ),
                icon: const Icon(Icons.check),
                label: const Text('Apply wallpaper'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.icon,
    required this.label,
    required this.description,
    required this.target,
    required this.selected,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final String description;
  final WallpaperScreenTarget target;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected ? cs.primaryContainer : cs.surfaceContainerHighest;
    final border = selected ? cs.primary : cs.outlineVariant;
    final textColor = selected ? cs.onPrimaryContainer : cs.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        constraints: const BoxConstraints(minWidth: 120),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border.withValues(alpha: 0.6), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: textColor),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600, color: textColor),
            ),
            Text(
              description,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: textColor.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}
