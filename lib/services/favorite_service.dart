import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deva_aura/models/favorite_model.dart';
import 'package:flutter/foundation.dart';

class FavoriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ---------------- Local (guest) favorites support ----------------
  static const String _prefsKeyIds = 'local_favorite_ids';
  static const String _prefsKeyMeta =
      'local_favorite_meta'; // map id -> iso createdAt

  final StreamController<void> _localChanges =
      StreamController<void>.broadcast();

  Future<Set<String>> _loadLocalIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKeyIds) ?? const <String>[];
    return list.toSet();
  }

  Future<Map<String, String>> _loadLocalMeta() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyMeta);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return map.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    } catch (_) {
      // sanitize invalid
      await prefs.remove(_prefsKeyMeta);
      return <String, String>{};
    }
  }

  Future<void> _saveLocal(Set<String> ids, Map<String, String> meta) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKeyIds, ids.toList());
    await prefs.setString(_prefsKeyMeta, jsonEncode(meta));
    try {
      _localChanges.add(null);
    } catch (_) {}
  }

  Stream<List<FavoriteModel>> getLocalFavoritesStream() async* {
    // emit immediately and whenever _localVersion changes
    Future<List<FavoriteModel>> buildList() async {
      final ids = await _loadLocalIds();
      final meta = await _loadLocalMeta();
      final nowIso = DateTime.now().toIso8601String();
      final list = ids.map((id) {
        final createdIso = meta[id] ?? nowIso;
        final created = DateTime.tryParse(createdIso) ?? DateTime.now();
        return FavoriteModel(
          id: 'guest_$id',
          userId: 'guest',
          wallpaperId: id,
          createdAt: created,
          updatedAt: created,
        );
      }).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    }

    yield await buildList();
    // Listen to changes
    yield* _localChanges.stream.asyncExpand((_) async* {
      yield await buildList();
    });
  }

  Future<List<FavoriteModel>> getLocalFavorites() async {
    return await getLocalFavoritesStream().first;
  }

  Future<bool> isLocalFavorite(String wallpaperId) async {
    final ids = await _loadLocalIds();
    return ids.contains(wallpaperId);
  }

  Future<void> addLocalFavorite(String wallpaperId) async {
    final ids = await _loadLocalIds();
    final meta = await _loadLocalMeta();
    ids.add(wallpaperId);
    meta[wallpaperId] = DateTime.now().toIso8601String();
    await _saveLocal(ids, meta);

    // [FIX] Try to increment global count even for guests
    try {
      await _firestore
          .collection('wallpapers')
          .doc(wallpaperId)
          .update({'likesCount': FieldValue.increment(1)});
    } catch (e) {
      debugPrint('[FavService] Guest increment failed: $e');
    }
  }

  Future<void> removeLocalFavorite(String wallpaperId) async {
    final ids = await _loadLocalIds();
    final meta = await _loadLocalMeta();
    ids.remove(wallpaperId);
    meta.remove(wallpaperId);
    await _saveLocal(ids, meta);

    // [FIX] Try to decrement global count even for guests
    try {
      await _firestore
          .collection('wallpapers')
          .doc(wallpaperId)
          .update({'likesCount': FieldValue.increment(-1)});
    } catch (e) {
      debugPrint('[FavService] Guest decrement failed: $e');
    }
  }

  // Convenience: user-or-guest bridges
  Stream<List<FavoriteModel>> getFavoritesStreamForUserOrGuest(String? userId) {
    if (userId == null || userId.isEmpty) {
      return getLocalFavoritesStream();
    }
    return getUserFavoritesStream(userId);
  }

  Future<List<FavoriteModel>> getFavoritesForUserOrGuest(String? userId) async {
    if (userId == null || userId.isEmpty) return getLocalFavorites();
    return getUserFavorites(userId);
  }

  Future<bool> isFavoriteForUserOrGuest(
      String? userId, String wallpaperId) async {
    if (userId == null || userId.isEmpty) return isLocalFavorite(wallpaperId);
    return isFavorite(userId, wallpaperId);
  }

  Future<void> addFavoriteForUserOrGuest(
      String? userId, String wallpaperId) async {
    if (userId == null || userId.isEmpty) return addLocalFavorite(wallpaperId);
    return addFavorite(userId, wallpaperId);
  }

  Future<void> removeFavoriteForUserOrGuest(
      String? userId, String wallpaperId) async {
    if (userId == null || userId.isEmpty)
      return removeLocalFavorite(wallpaperId);
    return removeFavorite(userId, wallpaperId);
  }

  Stream<List<FavoriteModel>> getUserFavoritesStream(String userId) {
    return _firestore
        .collection('favorites')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => FavoriteModel.fromJson(doc.data()))
            .toList());
  }

  Future<List<FavoriteModel>> getUserFavorites(String userId) async {
    final snapshot = await _firestore
        .collection('favorites')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    return snapshot.docs
        .map((doc) => FavoriteModel.fromJson(doc.data()))
        .toList();
  }

  Future<bool> isFavorite(String userId, String wallpaperId) async {
    final snapshot = await _firestore
        .collection('favorites')
        .where('userId', isEqualTo: userId)
        .where('wallpaperId', isEqualTo: wallpaperId)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  Future<void> addFavorite(String userId, String wallpaperId) async {
    // Use deterministic ID to avoid duplicates and simplify deletes
    final favId = '${userId}_${wallpaperId}';
    final docRef = _firestore.collection('favorites').doc(favId);
    final existing = await docRef.get();
    if (existing.exists) {
      // Already favorited; update timestamp for recency
      await docRef.update({'updatedAt': DateTime.now().toIso8601String()});
      return;
    }
    final favorite = FavoriteModel(
      id: favId,
      userId: userId,
      wallpaperId: wallpaperId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final batch = _firestore.batch();
    batch.set(docRef, favorite.toJson());
    // Increment likes count on the wallpaper
    final wallRef = _firestore.collection('wallpapers').doc(wallpaperId);
    batch.update(wallRef, {'likesCount': FieldValue.increment(1)});

    try {
      await batch.commit();
    } catch (e) {
      if (e.toString().contains('permission-denied')) {
        debugPrint(
            '[FavService] Permission denied for cloud like. Falling back to local.');
        await addLocalFavorite(wallpaperId);
        return;
      }
      rethrow;
    }
  }

  Future<void> removeFavorite(String userId, String wallpaperId) async {
    // Try deterministic ID first
    final favId = '${userId}_${wallpaperId}';
    final docRef = _firestore.collection('favorites').doc(favId);

    // Check existence first to avoid permission errors on non-existent docs if rules are strict
    DocumentSnapshot snap;
    try {
      snap = await docRef.get();
    } catch (e) {
      // If we can't read, we probably can't delete. Fallback.
      if (e.toString().contains('permission-denied')) {
        await removeLocalFavorite(wallpaperId);
        return;
      }
      rethrow;
    }

    if (snap.exists) {
      final batch = _firestore.batch();
      batch.delete(docRef);
      // Decrement likes count
      final wallRef = _firestore.collection('wallpapers').doc(wallpaperId);
      batch.update(wallRef, {'likesCount': FieldValue.increment(-1)});

      try {
        await batch.commit();
      } catch (e) {
        if (e.toString().contains('permission-denied')) {
          await removeLocalFavorite(wallpaperId);
          return;
        }
        rethrow;
      }
      return;
    }

    // Fallback: legacy docs without deterministic id
    final legacy = await _firestore
        .collection('favorites')
        .where('userId', isEqualTo: userId)
        .where('wallpaperId', isEqualTo: wallpaperId)
        .limit(5)
        .get();

    if (legacy.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (var d in legacy.docs) {
        batch.delete(d.reference);
      }
      // Decrement likes count (just once per logical removal)
      final wallRef = _firestore.collection('wallpapers').doc(wallpaperId);
      batch.update(wallRef, {'likesCount': FieldValue.increment(-1)});
      await batch.commit();
    }
  }
}
