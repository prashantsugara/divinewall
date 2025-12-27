import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deva_aura/models/category_model.dart';

class CategoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<CategoryModel>> getCategoriesStream() {
    return _firestore
        .collection('categories')
        .orderBy('order')
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CategoryModel.fromJson(doc.data()))
            .toList());
  }

  Future<List<CategoryModel>> getCategories() async {
    final snapshot = await _firestore
        .collection('categories')
        .orderBy('order')
        .limit(100)
        .get();
    return snapshot.docs
        .map((doc) => CategoryModel.fromJson(doc.data()))
        .toList();
  }

  Future<CategoryModel?> getCategory(String categoryId) async {
    // 1. Try fetching by Document ID (Key)
    final doc = await _firestore.collection('categories').doc(categoryId).get();
    if (doc.exists && doc.data() != null) {
      return CategoryModel.fromJson(doc.data()!);
    }

    // 2. If not found, try Querying by 'id' field (Internal Data ID)
    // This handles cases where Key != Data.id (like cat_007)
    try {
      final query = await _firestore
          .collection('categories')
          .where('id', isEqualTo: categoryId)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return CategoryModel.fromJson(query.docs.first.data());
      }
    } catch (e) {
      // Ignore query errors
    }

    return null;
  }

  Future<void> addCategory(CategoryModel category) async {
    final docRef = _firestore.collection('categories').doc();
    final newCategory = category.copyWith(id: docRef.id);
    await docRef.set(newCategory.toJson());
  }

  Future<void> updateCategory(CategoryModel category) async {
    final updatedCategory = category.copyWith(updatedAt: DateTime.now());
    await _firestore
        .collection('categories')
        .doc(category.id)
        .update(updatedCategory.toJson());
  }

  Future<void> deleteCategory(String categoryId) async {
    await _firestore.collection('categories').doc(categoryId).delete();
  }
}
