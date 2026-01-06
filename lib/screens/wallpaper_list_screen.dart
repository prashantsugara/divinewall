import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import 'package:deva_aura/auth/auth_manager.dart';
import 'package:deva_aura/models/category_model.dart';
import 'package:deva_aura/models/wallpaper_model.dart';
import 'package:deva_aura/models/user_model.dart';
import 'package:deva_aura/screens/wallpaper_viewer_screen.dart';
import 'package:deva_aura/services/wallpaper_service.dart';
import 'package:deva_aura/services/category_service.dart';
import 'package:deva_aura/utils/image_url_utils.dart';
import 'package:deva_aura/utils/web_image_proxy.dart';
import 'package:deva_aura/widgets/ad_banner.dart';
import 'package:deva_aura/widgets/native_ad_tile.dart';

class WallpaperListScreen extends StatefulWidget {
  final CategoryModel category;

  const WallpaperListScreen({super.key, required this.category});

  @override
  State<WallpaperListScreen> createState() => _WallpaperListScreenState();
}

class _WallpaperListScreenState extends State<WallpaperListScreen> {
  final WallpaperService _wallpaperService = WallpaperService();
  final AuthManager _authManager = AuthManager();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final CategoryService _categoryService = CategoryService();

  UserModel? _currentUser;

  ScrollController _scrollController = ScrollController();
  List<WallpaperModel> _wallpapers = [];
  DocumentSnapshot? _lastDocument;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isInitialLoad = true;
  WallpaperSortOption _currentSort = WallpaperSortOption.mostLiked;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadFirstPage();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

  Future<void> _loadFirstPage() async {
    if (!mounted) return;
    setState(() {
      _isInitialLoad = true;
      _error = null;
      _wallpapers.clear();
      _lastDocument = null;
      _hasMore = true;
    });

    try {
      final result = await _wallpaperService.getWallpapersPaginated(
        categoryId: widget.category.id,
        limit: 20,
        sort: _currentSort,
      );
      if (mounted) {
        setState(() {
          _wallpapers = result.wallpapers;
          _lastDocument = result.lastDoc;
          _hasMore = result.wallpapers.length >= 20;
          _isInitialLoad = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // Check for index error
        if (e.toString().contains('failed-precondition') ||
            e.toString().contains('requires an index')) {
          debugPrint('************************************************');
          debugPrint('FIRESTORE INDEX REQUIRED. Please create it here:');
          debugPrint(e.toString());
          debugPrint('************************************************');

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Sort by Likes requires a DB Index. Check logs. Defaulting to Newest.'),
              duration: Duration(seconds: 5),
            ),
          );

          // Fallback to Newest
          setState(() {
            _currentSort = WallpaperSortOption.newest;
          });
          _loadFirstPage(); // Retry with newest
          return;
        }

        setState(() {
          _error = e.toString();
          _isInitialLoad = false;
        });
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final result = await _wallpaperService.getWallpapersPaginated(
        categoryId: widget.category.id,
        startAfter: _lastDocument,
        limit: 20,
        sort: _currentSort,
      );
      if (mounted) {
        setState(() {
          _wallpapers.addAll(result.wallpapers);
          _lastDocument = result.lastDoc;
          _hasMore = result.wallpapers.length >= 20;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _loadUser() async {
    try {
      final user = await _authManager.getCurrentUserModel();
      if (mounted)
        setState(() {
          _currentUser = user;
        });
    } catch (e) {
      // ignore
    }
  }

  bool get _isAdmin => _authManager.isAdmin(_currentUser);

  Future<void> _confirmDeleteFromList(WallpaperModel wallpaper) async {
    // ... code truncated for brevity, same as original ...
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
    try {
      await _wallpaperService.deleteWallpaperWithStorage(wallpaper);
      if (!mounted) return;
      setState(() {
        _wallpapers.removeWhere((w) => w.id == wallpaper.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wallpaper deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<bool> _checkIfNewestHasData() async {
    try {
      final res = await _wallpaperService.getWallpapersPaginated(
          categoryId: widget.category.id,
          limit: 1,
          sort: WallpaperSortOption.newest);
      return res.wallpapers.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _runBackfill() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Fixing sort order (this may take a moment)...')),
    );
    try {
      final count = await _wallpaperService.backfillLikesCount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fixed $count items. Refreshing...')),
      );
      _loadFirstPage();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fix failed: $e')),
      );
    }
  }

  Future<void> _openUploadSheet() async {
    if (_currentUser == null) return;
    final titleController = TextEditingController();
    List<PlatformFile> selectedFiles = [];
    // Load categories so admin can choose destination or create new
    List<CategoryModel> categories = await _categoryService.getCategories();
    categories.sort((a, b) => a.order.compareTo(b.order));
    String selectedCategoryId = widget.category.id;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              return SafeArea(
                top: false,
                child: SingleChildScrollView(
                  // Makes the sheet scroll when content exceeds viewport
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upload wallpaper',
                          style: Theme.of(ctx).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(selectedCategoryId),
                              initialValue: selectedCategoryId,
                              items: [
                                for (final c in categories)
                                  DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setModalState(() {
                                  selectedCategoryId = v;
                                });
                              },
                              decoration: const InputDecoration(
                                labelText: 'Category',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () async {
                              final nameCtl = TextEditingController();
                              final created = await showDialog<String>(
                                context: ctx,
                                builder: (dctx) => AlertDialog(
                                  title: const Text('New category'),
                                  content: TextField(
                                    controller: nameCtl,
                                    decoration: const InputDecoration(
                                      labelText: 'Category name',
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(dctx).pop(),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () {
                                        final name = nameCtl.text.trim();
                                        if (name.isEmpty) return;
                                        Navigator.of(dctx).pop(name);
                                      },
                                      child: const Text('Create'),
                                    ),
                                  ],
                                ),
                              );
                              if (created != null &&
                                  created.trim().isNotEmpty) {
                                // Create category in Firestore
                                final now = DateTime.now();
                                final newCat = CategoryModel(
                                  id: 'temp',
                                  name: created.trim(),
                                  iconUrl: null,
                                  order: categories.isEmpty
                                      ? 1
                                      : (categories.last.order + 1),
                                  createdAt: now,
                                  updatedAt: now,
                                );
                                try {
                                  await _categoryService.addCategory(newCat);
                                  final refreshed =
                                      await _categoryService.getCategories();
                                  refreshed.sort(
                                      (a, b) => a.order.compareTo(b.order));
                                  setModalState(() {
                                    categories = refreshed;
                                    selectedCategoryId = refreshed.last.id;
                                  });
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Failed to create category: $e')),
                                    );
                                  }
                                }
                              }
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('New'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.file_upload),
                            label: const Text('Pick images'),
                            onPressed: () async {
                              final result =
                                  await FilePicker.platform.pickFiles(
                                type: kIsWeb ? FileType.custom : FileType.image,
                                allowedExtensions: kIsWeb
                                    ? const ['jpg', 'jpeg', 'png', 'webp']
                                    : null,
                                allowMultiple: true,
                                withData: true,
                              );
                              if (result != null && result.files.isNotEmpty) {
                                // Filter unsupported HEIC/HEIF on web
                                final files = result.files.where((f) {
                                  final name = f.name;
                                  final ext = name.contains('.')
                                      ? name.split('.').last.toLowerCase()
                                      : '';
                                  if (kIsWeb &&
                                      (ext == 'heic' || ext == 'heif')) {
                                    debugPrint(
                                        '[Upload] Skipping unsupported web format: $name');
                                    return false;
                                  }
                                  return f.bytes != null;
                                }).toList();
                                setModalState(() {
                                  selectedFiles = files;
                                });
                                if (files.isNotEmpty) {
                                  if (files.length == 1) {
                                    final f = files.first;
                                    debugPrint(
                                        '[Upload] Picked 1 file name=${f.name} bytes=${f.bytes?.length ?? 0}');
                                  } else {
                                    debugPrint(
                                        '[Upload] Picked ${files.length} files');
                                  }
                                }
                              }
                            },
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedFiles.isEmpty
                                  ? 'No files selected'
                                  : (selectedFiles.length == 1
                                      ? selectedFiles.first.name
                                      : '${selectedFiles.length} files selected'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (selectedFiles.isNotEmpty &&
                          selectedFiles.first.bytes != null)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final screenH = MediaQuery.of(ctx).size.height;
                            final maxH = screenH *
                                0.45; // Cap preview at 45% screen height
                            final width = constraints.maxWidth;
                            final naturalH =
                                width * 16 / 9; // Portrait preview tendency
                            final h = naturalH > maxH ? maxH : naturalH;
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: double.infinity,
                                height: h,
                                child: Image.memory(
                                  selectedFiles.first.bytes!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    debugPrint(
                                        '[Upload] Preview decode error for ${selectedFiles.first.name}: $error');
                                    return Container(
                                      color: Colors.grey[300],
                                      child: const Center(
                                        child:
                                            Text('Cannot preview this format'),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: () async {
                            if (selectedFiles.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                    content: Text('Pick at least one image')),
                              );
                              return;
                            }
                            // Build payload for upload: one map per file
                            final isSingle = selectedFiles.length == 1;
                            final typedTitle = titleController.text.trim();
                            final filesPayload = <Map<String, dynamic>>[];
                            for (final f in selectedFiles) {
                              final name = f.name;
                              final bytes = f.bytes;
                              if (bytes == null) continue;
                              String title = name;
                              if (isSingle && typedTitle.isNotEmpty) {
                                title = typedTitle;
                              } else {
                                // derive from filename without extension
                                final dot = name.lastIndexOf('.');
                                title = dot > 0 ? name.substring(0, dot) : name;
                              }
                              filesPayload.add({
                                'bytes': bytes,
                                'name': name,
                                'title': title,
                              });
                            }
                            Navigator.of(ctx).pop({
                              'files': filesPayload,
                              'categoryId': selectedCategoryId,
                            });
                          },
                          child: const Text('Upload'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    ).then((value) async {
      if (value is Map && value['files'] != null) {
        final files = (value['files'] as List).cast<Map>();
        final selectedId = value['categoryId'] as String? ?? widget.category.id;
        int successCount = 0;
        for (final f in files) {
          try {
            final bytes = f['bytes'] as Uint8List;
            final title = f['title'] as String? ?? 'Wallpaper';
            final fileName = f['name'] as String? ?? 'wallpaper.jpg';
            debugPrint(
                '[Upload] Begin upload title=$title to category=$selectedId file=$fileName');
            // Infer a sensible contentType if not provided
            String inferMime() {
              final lower = fileName.toLowerCase();
              if (lower.endsWith('.jpg') || lower.endsWith('.jpeg'))
                return 'image/jpeg';
              if (lower.endsWith('.png')) return 'image/png';
              if (lower.endsWith('.webp')) return 'image/webp';
              if (lower.endsWith('.heic') || lower.endsWith('.heif'))
                return 'image/heic';
              return 'application/octet-stream';
            }

            final path =
                'wallpapers/$selectedId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
            final ref = _storage.ref().child(path);
            final snapshot = await ref.putData(
              bytes,
              SettableMetadata(contentType: inferMime()),
            );
            final url = await snapshot.ref.getDownloadURL();
            debugPrint('[Upload] Storage success. path=$path url=$url');

            // Post-upload verification: check metadata and that the URL is fetchable
            bool metadataOk = false;
            bool headOk = false;
            bool getOk = false;
            bool prefetchOk = false;
            try {
              final meta = await ref.getMetadata();
              final size = meta.size;
              final ctype = meta.contentType;
              metadataOk = (size ?? 0) > 0 &&
                  (ctype != null && ctype.startsWith('image/'));
              debugPrint(
                  '[Upload] Verify: metadata size=${size ?? 'unknown'} contentType=${ctype ?? 'unknown'}');
            } catch (e) {
              debugPrint('[Upload] Verify: metadata fetch failed: $e');
            }

            // Try a HEAD request first; if OK, fetch first 128 bytes to ensure availability
            try {
              final safeUrl = ImageUrlUtils.sanitize(url);
              final head = await http
                  .head(Uri.parse(safeUrl))
                  .timeout(const Duration(seconds: 15));
              headOk = head.statusCode >= 200 && head.statusCode < 400;
              debugPrint('[Upload] Verify: HEAD status=${head.statusCode}');
              if (headOk) {
                final getResp = await http.get(Uri.parse(safeUrl),
                    headers: const {
                      'Range': 'bytes=0-127'
                    }).timeout(const Duration(seconds: 20));
                getOk = getResp.statusCode >= 200 &&
                    getResp.statusCode < 400 &&
                    getResp.bodyBytes.isNotEmpty;
                debugPrint(
                    '[Upload] Verify: GET status=${getResp.statusCode} bytes=${getResp.bodyBytes.length}');
              } else {
                debugPrint('[Upload] Verify: HEAD failed; won\'t GET');
              }
            } catch (e) {
              debugPrint('[Upload] Verify: URL fetch failed: $e');
            }

            // Prefetch into Flutter image cache so it shows instantly in UI
            try {
              final safeUrl = ImageUrlUtils.sanitize(url);
              await precacheImage(NetworkImage(safeUrl), context);
              prefetchOk = true;
              debugPrint('[Upload] Prefetch: success');
            } catch (e) {
              debugPrint('[Upload] Prefetch: failed: $e');
            }

            // Final post-upload summary log
            final available = metadataOk && headOk && getOk;
            if (available) {
              debugPrint(
                  '[Upload] Post-check: image available on Storage and fetched successfully. cached=$prefetchOk');
            } else {
              debugPrint(
                  '[Upload] Post-check: image NOT yet available. metadataOk=$metadataOk headOk=$headOk getOk=$getOk');
            }

            final now = DateTime.now();
            final newWallpaper = WallpaperModel(
              id: 'temp',
              categoryId: selectedId,
              title: title,
              imageUrl: url,
              thumbnailUrl: url,
              uploadedBy: _currentUser!.id,
              downloadCount: 0,
              tags: [title.toLowerCase()],
              createdAt: now,
              updatedAt: now,
            );
            await _wallpaperService.addWallpaper(newWallpaper);
            debugPrint(
                '[Upload] Firestore document created for category=$selectedId');
            successCount++;
          } catch (e, st) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Upload failed: $e')),
              );
            }
            // Provide detailed error diagnostics for Firebase Storage
            if (e is FirebaseException) {
              debugPrint('[Upload] Failed: code=' +
                  (e.code) +
                  ' message=' +
                  (e.message ?? '') +
                  ' plugin=' +
                  e.plugin);
            } else {
              debugPrint('[Upload] Failed: $e');
            }
            debugPrint('[Upload] Stack: $st');
          }
        }
        if (mounted) {
          final total = files.length;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Uploaded $successCount of $total image${total == 1 ? '' : 's'}')),
          );
        }
        // If uploaded to a different category, navigate there so the user sees it immediately
        if (selectedId != widget.category.id) {
          try {
            final dest = await _categoryService.getCategory(selectedId);
            if (dest != null && mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => WallpaperListScreen(category: dest),
                ),
              );
            }
          } catch (_) {}
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.name),
        actions: [
          PopupMenuButton<WallpaperSortOption?>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort by',
            initialValue: _currentSort,
            onSelected: (newValue) {
              if (newValue == null) {
                // Admin action: fix sort
                _runBackfill();
                return;
              }
              if (newValue != _currentSort) {
                setState(() => _currentSort = newValue);
                _loadFirstPage();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: WallpaperSortOption.mostLiked,
                child: Row(
                  children: [
                    Icon(Icons.favorite, size: 20, color: Colors.pink),
                    SizedBox(width: 8),
                    Text('Most Liked')
                  ],
                ),
              ),
              const PopupMenuItem(
                value: WallpaperSortOption.newest,
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 20),
                    SizedBox(width: 8),
                    Text('Newest')
                  ],
                ),
              ),
              if (_isAdmin)
                const PopupMenuItem(
                  value: null, // special value for action
                  child: Row(
                    children: [
                      Icon(Icons.build_circle, size: 20, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Fix Sort (Admin)'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _openUploadSheet,
              icon: const Icon(Icons.add),
              label: const Text('Upload'),
            )
          : null,
      body: Column(
        children: [
          // Banner at top, edge-to-edge for wallpapers screen
          AdBanner(isAdmin: _isAdmin, placement: BannerPlacement.wallpapers),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadFirstPage,
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isInitialLoad) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      final friendly = _error!.contains('permission-denied')
          ? 'You do not have permission to view these wallpapers.'
          : 'Error: $_error';
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(friendly, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _loadFirstPage, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_wallpapers.isEmpty) {
      return FutureBuilder<bool>(
        future: _checkIfNewestHasData(),
        builder: (context, snapshot) {
          final newestHasData = snapshot.data ?? false;
          // If "Newest" has data but "Most Liked" (current) doesn't, it's a data issue.
          if (newestHasData && _currentSort == WallpaperSortOption.mostLiked) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber,
                      size: 64, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text(
                    'Sorting requires a one-time database fix.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                    child: Text(
                      'Your old wallpapers are missing the "likes" data field, so they don\'t show up in this list.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      onPressed: _runBackfill,
                      icon: const Icon(Icons.build),
                      label: const Text('Fix Database Now')),
                ],
              ),
            );
          }

          return ListView(
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.3),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_not_supported,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      'No wallpapers in this category',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    }

    // Ad Logic
    const int kAdInterval = 8; // Show ad after every 8 wallpapers
    final int wallpaperCount = _wallpapers.length;
    final int adCount = (wallpaperCount / kAdInterval).floor();
    final int totalCount = wallpaperCount + adCount + (_isLoadingMore ? 1 : 0);

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.7,
      ),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        // Loading indicator at the very end
        if (index == totalCount - 1 && _isLoadingMore) {
          return const Center(child: CircularProgressIndicator());
        }

        // Check if this slot is for an ad
        // We want ads at positions: 8, 17, 26, ...
        // (index + 1) % (kAdInterval + 1) == 0
        if ((index + 1) % (kAdInterval + 1) == 0) {
          return NativeAdTile(isAdmin: _isAdmin);
        }

        // Calculate actual wallpaper index
        final int adjustedIndex = index - (index / (kAdInterval + 1)).floor();

        // Safety check
        if (adjustedIndex >= _wallpapers.length) {
          return const SizedBox.shrink();
        }

        final wallpaper = _wallpapers[adjustedIndex];
        final heroTag = 'wallpaper_${wallpaper.id}';
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              InkWell(
                onTap: () async {
                  final result = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WallpaperViewerScreen(
                        wallpaper: wallpaper,
                        wallpapers: _wallpapers,
                        initialIndex: adjustedIndex,
                      ),
                    ),
                  );
                  // Update local list if we got modified items back
                  if (result != null &&
                      result is List<WallpaperModel> &&
                      mounted) {
                    setState(() {
                      // We replace the visible wallpapers with the updated ones
                      for (var updated in result) {
                        final idx =
                            _wallpapers.indexWhere((w) => w.id == updated.id);
                        if (idx != -1) {
                          _wallpapers[idx] = updated;
                        }
                      }
                    });
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Hero(
                        tag: heroTag,
                        child: kIsWeb
                            ? Image.network(
                                WebImageProxy.displayUrl(
                                  ImageUrlUtils.sanitize(
                                      wallpaper.thumbnailUrl ??
                                          wallpaper.imageUrl),
                                ),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  color: Colors.grey[300],
                                  child: Icon(Icons.error,
                                      color: Colors.grey[600]),
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: ImageUrlUtils.sanitize(
                                    wallpaper.thumbnailUrl ??
                                        wallpaper.imageUrl),
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey[300],
                                  child: const Center(
                                      child: CircularProgressIndicator()),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey[300],
                                  child: Icon(Icons.error,
                                      color: Colors.grey[600]),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${wallpaper.likesCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isAdmin)
                Positioned(
                  right: 6,
                  top: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () => _confirmDeleteFromList(wallpaper),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
