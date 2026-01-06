import '../utils/datetime_utils.dart';

class WallpaperModel {
  final String id;
  final String categoryId;
  final String title;
  final String imageUrl;
  final String? thumbnailUrl;
  final String uploadedBy;
  final int likesCount;
  final int downloadCount;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  WallpaperModel({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.imageUrl,
    this.thumbnailUrl,
    required this.uploadedBy,
    this.downloadCount = 0,
    this.likesCount = 0,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory WallpaperModel.fromJson(Map<String, dynamic> json) {
    return WallpaperModel(
      id: json['id'] as String,
      categoryId: json['categoryId'] as String,
      title: json['title'] as String,
      imageUrl: json['imageUrl'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      uploadedBy: json['uploadedBy'] as String,
      downloadCount: json['downloadCount'] as int? ?? 0,
      likesCount: json['likesCount'] as int? ?? 0,
      tags: List<String>.from(json['tags'] as List? ?? []),
      createdAt: DateTimeUtils.fromFirestore(json['createdAt']),
      updatedAt: DateTimeUtils.fromFirestore(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'categoryId': categoryId,
      'title': title,
      'imageUrl': imageUrl,
      'thumbnailUrl': thumbnailUrl,
      'uploadedBy': uploadedBy,
      'downloadCount': downloadCount,
      'likesCount': likesCount,
      'tags': tags,
      // Store as ISO8601 strings to avoid web Timestamp interop issues
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  WallpaperModel copyWith({
    String? id,
    String? categoryId,
    String? title,
    String? imageUrl,
    String? thumbnailUrl,
    String? uploadedBy,
    int? downloadCount,
    int? likesCount,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WallpaperModel(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      downloadCount: downloadCount ?? this.downloadCount,
      likesCount: likesCount ?? this.likesCount,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
