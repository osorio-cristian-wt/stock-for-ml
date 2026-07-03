import 'package:meta/meta.dart';

import 'json.dart';

/// A variation of a MercadoLibre publication (talle/color/…), with the
/// ML-side stock per variation (row of `public.listing_variations`).
///
/// The app mirrors these for visibility (RF-07): stock per variation is still
/// managed in ML — push-stock skips item-level updates on variation listings.
@immutable
class ListingVariation {
  const ListingVariation({
    required this.id,
    required this.profileId,
    required this.mlListingId,
    required this.mlVariationId,
    this.attributes = const [],
    this.price,
    this.availableQuantity = 0,
  });

  final String id;
  final String profileId;
  final String mlListingId;
  final String mlVariationId;

  /// ML `attribute_combinations` (e.g. Color/Talle), as raw JSON maps.
  final List<Map<String, dynamic>> attributes;
  final double? price;
  final int availableQuantity;

  /// Human label built from the combination values, e.g. "Rojo · XL".
  String get label {
    final names = <String>[
      for (final a in attributes)
        if (a['value_name'] is String &&
            (a['value_name'] as String).trim().isNotEmpty)
          (a['value_name'] as String).trim(),
    ];
    return names.isEmpty ? 'Variación $mlVariationId' : names.join(' · ');
  }

  factory ListingVariation.fromJson(Map<String, dynamic> json) =>
      ListingVariation(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        mlListingId: json['ml_listing_id'] as String,
        mlVariationId: json['ml_variation_id'] as String,
        attributes: [
          if (json['attributes'] is List)
            for (final a in json['attributes'] as List)
              if (a is Map) Map<String, dynamic>.from(a),
        ],
        price: asDoubleOrNull(json['price']),
        availableQuantity: asInt(json['available_quantity']),
      );
}
