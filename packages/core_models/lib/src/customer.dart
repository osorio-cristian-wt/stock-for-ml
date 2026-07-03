import 'package:meta/meta.dart';

/// A customer ("cliente") a local sale can be attributed to. Scoped to the
/// creating user via `profile_id` (RLS). Only the name is required; the rest
/// is optional data for the future (razón social, CUIT/CUIL, contacto).
@immutable
class Customer {
  const Customer({
    required this.id,
    required this.profileId,
    required this.name,
    this.legalName,
    this.taxId,
    this.phone,
    this.email,
    this.notes,
  });

  final String id;
  final String profileId;
  final String name;
  final String? legalName;

  /// CUIT / CUIL / DNI.
  final String? taxId;
  final String? phone;
  final String? email;
  final String? notes;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        name: json['name'] as String,
        legalName: json['legal_name'] as String?,
        taxId: json['tax_id'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        'profile_id': profileId,
        'name': name,
        if (legalName != null) 'legal_name': legalName,
        if (taxId != null) 'tax_id': taxId,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (notes != null) 'notes': notes,
      };
}
