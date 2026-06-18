import 'package:meta/meta.dart';

import 'json.dart';

enum ListingStatus { active, paused, closed, underReview, inactive, unknown }

ListingStatus listingStatusFrom(String? v) {
  switch (v) {
    case 'active':
      return ListingStatus.active;
    case 'paused':
      return ListingStatus.paused;
    case 'closed':
      return ListingStatus.closed;
    case 'under_review':
      return ListingStatus.underReview;
    case 'inactive':
      return ListingStatus.inactive;
    default:
      return ListingStatus.unknown;
  }
}

/// A MercadoLibre publication linked to an internal [Product].
@immutable
class MlListing {
  const MlListing({
    required this.id,
    required this.profileId,
    required this.mlItemId,
    this.productId,
    this.title,
    this.categoryId,
    this.listingTypeId,
    this.price,
    this.currencyId = 'ARS',
    this.availableQuantity = 0,
    this.soldQuantity = 0,
    this.estSaleFee,
    this.status = ListingStatus.unknown,
    this.permalink,
    this.thumbnail,
    this.hasVariations = false,
  });

  final String id;
  final String profileId;
  final String mlItemId;
  final String? productId;
  final String? title;
  final String? categoryId;
  final String? listingTypeId;
  final double? price;
  final String currencyId;
  final int availableQuantity;
  final int soldQuantity;
  final double? estSaleFee;
  final ListingStatus status;
  final String? permalink;
  final String? thumbnail;
  final bool hasVariations;

  factory MlListing.fromJson(Map<String, dynamic> json) => MlListing(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        mlItemId: json['ml_item_id'] as String,
        productId: json['product_id'] as String?,
        title: json['title'] as String?,
        categoryId: json['category_id'] as String?,
        listingTypeId: json['listing_type_id'] as String?,
        price: asDoubleOrNull(json['price']),
        currencyId: (json['currency_id'] as String?) ?? 'ARS',
        availableQuantity: asInt(json['available_quantity']),
        soldQuantity: asInt(json['sold_quantity']),
        estSaleFee: asDoubleOrNull(json['est_sale_fee']),
        status: listingStatusFrom(json['status'] as String?),
        permalink: json['permalink'] as String?,
        thumbnail: json['thumbnail'] as String?,
        hasVariations: asBool(json['has_variations']),
      );
}
