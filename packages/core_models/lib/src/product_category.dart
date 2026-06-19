import 'package:meta/meta.dart';

/// An internal product category (the user's own taxonomy, distinct from ML's
/// category). Optionally hierarchical via [parentId].
@immutable
class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.profileId,
    required this.name,
    required this.slug,
    this.parentId,
  });

  final String id;
  final String profileId;
  final String name;
  final String slug;
  final String? parentId;

  factory ProductCategory.fromJson(Map<String, dynamic> json) => ProductCategory(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        parentId: json['parent_id'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        'profile_id': profileId,
        'name': name,
        'slug': slug,
        if (parentId != null) 'parent_id': parentId,
      };
}
