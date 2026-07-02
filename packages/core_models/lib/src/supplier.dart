import 'package:meta/meta.dart';

/// A reusable supplier ("proveedor") a purchase can be attributed to.
@immutable
class Supplier {
  const Supplier({
    required this.id,
    required this.profileId,
    required this.name,
    this.notes,
  });

  final String id;
  final String profileId;
  final String name;
  final String? notes;

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        name: json['name'] as String,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        'profile_id': profileId,
        'name': name,
        if (notes != null) 'notes': notes,
      };
}
