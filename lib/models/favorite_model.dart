import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/datetime_utils.dart';

class FavoriteModel {
  final String id;
  final String userId;
  final String wallpaperId;
  final DateTime createdAt;
  final DateTime updatedAt;

  FavoriteModel({
    required this.id,
    required this.userId,
    required this.wallpaperId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FavoriteModel.fromJson(Map<String, dynamic> json) {
    return FavoriteModel(
      id: json['id'] as String,
      userId: json['userId'] as String,
      wallpaperId: json['wallpaperId'] as String,
      createdAt: DateTimeUtils.fromFirestore(json['createdAt']),
      updatedAt: DateTimeUtils.fromFirestore(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'wallpaperId': wallpaperId,
      // Store as ISO8601 strings to avoid web Timestamp interop issues
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  FavoriteModel copyWith({
    String? id,
    String? userId,
    String? wallpaperId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FavoriteModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      wallpaperId: wallpaperId ?? this.wallpaperId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
