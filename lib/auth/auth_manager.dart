import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deva_aura/models/user_model.dart';

class AuthManager {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserModel> _ensureUserDocument(User firebaseUser, {String? displayNameOverride}) async {
    final docRef = _firestore.collection('users').doc(firebaseUser.uid);
    final snap = await docRef.get();
    final now = DateTime.now();

    // Build base fields from Firebase User
    final email = firebaseUser.email ?? '';
    final name = displayNameOverride ?? firebaseUser.displayName ?? 'User';
    final photo = firebaseUser.photoURL;

    if (!snap.exists) {
      final newUser = UserModel(
        id: firebaseUser.uid,
        email: email,
        displayName: name,
        photoUrl: photo,
        role: 'user',
        createdAt: now,
        updatedAt: now,
      );
      await docRef.set(newUser.toJson());
      debugPrint('[Auth] Created user document for uid=${firebaseUser.uid}');
      return newUser;
    }

    // Do not overwrite role or createdAt; only refresh profile fields and updatedAt
    await docRef.update({
      'email': email,
      'displayName': name,
      'photoUrl': photo,
      'updatedAt': now.toIso8601String(),
    });

    final updated = await docRef.get();
    return UserModel.fromJson(updated.data()!);
  }

  Future<UserModel?> signInWithGoogle() async {
    try {
      debugPrint('[Auth] Starting Google sign-in... (kIsWeb=$kIsWeb)');
      // Log origin and Firebase options to detect unauthorized domain root cause
      try {
        debugPrint('[Auth] Web origin: ${Uri.base.origin}');
        final opts = Firebase.app().options;
        debugPrint('[Auth] FirebaseOptions.authDomain=${opts.authDomain ?? 'null'}, projectId=${opts.projectId}');
      } catch (e) {
        debugPrint('[Auth][Warn] Could not log origin/options: $e');
      }
      final GoogleAuthProvider provider = GoogleAuthProvider();
      provider.setCustomParameters({'prompt': 'select_account'});

      UserCredential userCredential;
      if (kIsWeb) {
        debugPrint('[Auth] Using signInWithPopup on web');
        try {
          userCredential = await _auth.signInWithPopup(provider);
        } on FirebaseAuthException catch (e) {
          // In some embedded web preview contexts, popup may report unauthorized-domain
          // even when the domain is allowlisted. Fallback to redirect flow.
          if (e.code == 'unauthorized-domain' ||
              (e.message != null && e.message!.toLowerCase().contains('unauthorized-domain'))) {
            debugPrint('[Auth][Warn] signInWithPopup unauthorized-domain; falling back to signInWithRedirect');
            await _auth.signInWithRedirect(provider);
            // The above triggers a full page navigation; code after this is not expected to run.
            // Return null to satisfy the type in case runtime continues without redirect (unlikely).
            return null;
          }
          rethrow;
        }
      } else {
        debugPrint('[Auth] Using signInWithProvider on mobile');
        userCredential = await _auth.signInWithProvider(provider);
      }

      final user = userCredential.user;
      if (user == null) {
        debugPrint('[Auth] Google sign-in returned null user');
        return null;
      }

      debugPrint('[Auth] Signed in as: uid=${user.uid}, email=${user.email}');
      final ensured = await _ensureUserDocument(user);
      return ensured;
    } catch (e) {
      debugPrint('[Auth][Error] Google sign in failed: $e');
      throw Exception('Google sign in failed: $e');
    }
  }

  /// Sign in without creating any Firestore user document.
  /// This satisfies Firestore rules requiring `request.auth != null`,
  /// while the app continues to treat this session as a "guest" because
  /// we never create a users/{uid} document. Screens that call
  /// getCurrentUserModel() will receive null and thus use local favorites.
  Future<void> signInAnonymously() async {
    try {
      await _auth.signInAnonymously();
      debugPrint('[Auth] Signed in anonymously');
    } catch (e) {
      debugPrint('[Auth][Error] Anonymous sign-in failed: $e');
      rethrow;
    }
  }

  // Public helper to ensure Firestore user document for the currently signed-in user.
  Future<UserModel?> ensureCurrentUserDocument({String? displayNameOverride}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final ensured = await _ensureUserDocument(user, displayNameOverride: displayNameOverride);
      return ensured;
    } catch (e) {
      debugPrint('[Auth][Error] ensureCurrentUserDocument: $e');
      rethrow;
    }
  }


  Future<UserModel?> getCurrentUserModel() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return null;
      return UserModel.fromJson(userDoc.data()!);
    } catch (e) {
      throw Exception('Failed to get user data: $e');
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  bool isAdmin(UserModel? user) => user?.role == 'admin';
}
