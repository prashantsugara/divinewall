import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:deva_aura/models/wallpaper_model.dart';

enum WallpaperSortOption {
  newest,
  mostLiked,
}

class WallpaperService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Paginated fetch. Returns a tuple of [List<WallpaperModel>, DocumentSnapshot? lastDoc].
  /// If [startAfter] is null, fetches the first page.
  Future<({List<WallpaperModel> wallpapers, DocumentSnapshot? lastDoc})>
      getWallpapersPaginated({
    required String categoryId,
    DocumentSnapshot? startAfter,
    int limit = 20,
    WallpaperSortOption sort = WallpaperSortOption.mostLiked,
  }) async {
    Query query = _firestore
        .collection('wallpapers')
        .where('categoryId', isEqualTo: categoryId);

    if (sort == WallpaperSortOption.mostLiked) {
      // Primary sort by likes, secondary by createdAt for stability
      query = query
          .orderBy('likesCount', descending: true)
          .orderBy('createdAt', descending: true);
    } else {
      query = query.orderBy('createdAt', descending: true);
    }

    query = query.limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    final wallpapers = snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return WallpaperModel.fromJson({
        ...data,
        'id': doc.id,
      });
    }).toList();

    debugPrint(
        '[WallpaperService] Fetch category=$categoryId sort=$sort limit=$limit returned ${wallpapers.length} items.');
    if (wallpapers.isNotEmpty) {
      debugPrint(
          '[WallpaperService] First item: likesCount=${wallpapers.first.likesCount}');
    }

    return (
      wallpapers: wallpapers,
      lastDoc: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
    );
  }

  Future<WallpaperModel?> getWallpaper(String wallpaperId) async {
    final doc =
        await _firestore.collection('wallpapers').doc(wallpaperId).get();
    if (!doc.exists) return null;
    final data = doc.data()! as Map<String, dynamic>;
    return WallpaperModel.fromJson({
      ...data,
      'id': doc.id,
    });
  }

  Future<void> addWallpaper(WallpaperModel wallpaper) async {
    final docRef = _firestore.collection('wallpapers').doc();
    final newWallpaper = wallpaper.copyWith(id: docRef.id);
    await docRef.set(newWallpaper.toJson());
  }

  Future<void> updateWallpaper(WallpaperModel wallpaper) async {
    final updatedWallpaper = wallpaper.copyWith(updatedAt: DateTime.now());
    await _firestore
        .collection('wallpapers')
        .doc(wallpaper.id)
        .update(updatedWallpaper.toJson());
  }

  Future<void> deleteWallpaper(String wallpaperId) async {
    await _firestore.collection('wallpapers').doc(wallpaperId).delete();
  }

  /// Delete wallpaper document and associated storage files (image and thumbnail if different)
  Future<void> deleteWallpaperWithStorage(WallpaperModel wallpaper) async {
    final storage = FirebaseStorage.instance;
    // Attempt to delete associated storage objects; ignore failures so Firestore still cleans up
    final urls = <String>{};
    urls.add(wallpaper.imageUrl);
    if (wallpaper.thumbnailUrl != null) {
      urls.add(wallpaper.thumbnailUrl!);
    }

    for (final url in urls) {
      try {
        final ref = storage.refFromURL(url);
        await ref.delete();
      } catch (e) {
        // Non-fatal; could be already deleted or malformed URL
        //debugPrint('[WallpaperService] Storage delete failed for $url: $e');
      }
    }
    await _firestore.collection('wallpapers').doc(wallpaper.id).delete();
  }

  Future<void> incrementDownloadCount(String wallpaperId) async {
    await _firestore.collection('wallpapers').doc(wallpaperId).update({
      'downloadCount': FieldValue.increment(1),
    });
  }

  Future<List<WallpaperModel>> searchWallpapers(String query) async {
    if (query.isEmpty) return [];

    // Enhanced Search: Try multiple cases to be robust against data inconsistencies
    try {
      final q1 = _firestore
          .collection('wallpapers')
          .where('tags', arrayContains: query.toLowerCase())
          .limit(20)
          .get();

      // Also try capitalized (e.g. "Hanuman")
      // First char upper, rest lower
      String capitalized = query;
      if (query.isNotEmpty) {
        capitalized = query[0].toUpperCase() + query.substring(1).toLowerCase();
      }
      final q2 = _firestore
          .collection('wallpapers')
          .where('tags', arrayContains: capitalized)
          .limit(20)
          .get();

      // Original query as provided
      final q3 = _firestore
          .collection('wallpapers')
          .where('tags', arrayContains: query)
          .limit(20)
          .get();

      final results = await Future.wait([q1, q2, q3]);

      final Map<String, WallpaperModel> uniqueMap = {};

      for (final snap in results) {
        for (final doc in snap.docs) {
          if (!uniqueMap.containsKey(doc.id)) {
            final data = doc.data();
            uniqueMap[doc.id] = WallpaperModel.fromJson({
              ...data,
              'id': data['id'] ?? doc.id,
            });
          }
        }
      }
      return uniqueMap.values.toList();
    } catch (e) {
      debugPrint('[WallpaperService] Search failed: $e');
      return [];
    }
  }

  /// Fetch multiple wallpapers by their document IDs, batched to respect whereIn limits (<=10).
  Future<List<WallpaperModel>> getWallpapersByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final Map<String, WallpaperModel> byDocId = {};
    for (var i = 0; i < ids.length; i += 10) {
      final batch = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      final snap = await _firestore
          .collection('wallpapers')
          .where(FieldPath.documentId, whereIn: batch)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final model = WallpaperModel.fromJson({
          ...data,
          'id': doc.id,
        });
        byDocId[model.id] = model;
      }
    }
    // Fallback for legacy favorites that stored a custom 'id' instead of documentId
    final missing = ids.where((id) => !byDocId.containsKey(id)).toList();
    for (var i = 0; i < missing.length; i += 10) {
      final batch =
          missing.sublist(i, i + 10 > missing.length ? missing.length : i + 10);
      final snap = await _firestore
          .collection('wallpapers')
          .where('id', whereIn: batch)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final model = WallpaperModel.fromJson({
          ...data,
          'id': doc.id,
        });
        byDocId[model.id] = model;
      }
    }
    return byDocId.values.toList();
  }

  Stream<WallpaperModel?> getAnyWallpaperInCategoryStream(String categoryId) {
    return _firestore
        .collection('wallpapers')
        .where('categoryId', isEqualTo: categoryId)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      final data = doc.data();
      return WallpaperModel.fromJson({
        ...data,
        'id': doc.id,
      });
    });
  }

  /// One-time migration helper: sets likesCount=0 for documents that don't have it.
  /// Returns count of updated documents.
  Future<int> backfillLikesCount() async {
    int updated = 0;
    // We can't query for "missing field" easily, so we fetch all and check data
    // Warning: Only safe for moderate collection sizes. For huge collections, use cloud function.
    try {
      final snap = await _firestore.collection('wallpapers').get();
      // Use batch writes for better performance
      WriteBatch batch = _firestore.batch();
      int batchCount = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        if (!data.containsKey('likesCount') || data['likesCount'] == null) {
          batch.update(doc.reference, {'likesCount': 0});
          batchCount++;
          updated++;
          // helper limit for batch is 500
          if (batchCount >= 450) {
            await batch.commit();
            batch = _firestore.batch();
            batchCount = 0;
          }
        }
      }
      if (batchCount > 0) {
        await batch.commit();
      }
      //debugPrint('[Backfill] Scanned ${snap.size} docs, updated $updated');
    } catch (e) {
      debugPrint('[Backfill] Failed: $e');
      rethrow;
    }
    debugPrint('[Backfill] Completed. Updated $updated documents.');
    return updated;
  }

  /// Perform a dry run check to see if backfill is needed.
  Future<bool> needsBackfill() async {
    // Check first 10 docs to see if any are missing 'likesCount'
    final snap = await _firestore.collection('wallpapers').limit(10).get();
    for (final doc in snap.docs) {
      if (!doc.data().containsKey('likesCount')) return true;
    }
    return false;
  }
}
