import 'package:meta/meta.dart';

import 'json.dart';

enum ListingStatus {
  active,
  paused,
  closed,
  underReview,
  inactive,
  notYetActive,
  paymentRequired,
  unknown,
}

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
    case 'not_yet_active':
      return ListingStatus.notYetActive;
    case 'payment_required':
      return ListingStatus.paymentRequired;
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
    this.subStatus = const [],
    this.logisticType,
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

  /// ML sub_status values (out_of_stock, paused_by_seller, deleted, …). RF-37.
  final List<String> subStatus;

  /// ML shipping.logistic_type; `fulfillment` = stock managed by ML Full (RF-38).
  final String? logisticType;
  final String? permalink;
  final String? thumbnail;
  final bool hasVariations;

  /// Stock stored and dispatched by ML Full (RF-38).
  bool get isFulfillment => logisticType == 'fulfillment';

  /// Paused by the seller (needs explicit reactivation, RF-47) vs paused
  /// because it ran out of stock (reactivates alone with a stock push).
  bool get isPausedBySeller => subStatus.contains('paused_by_seller');
  bool get isOutOfStock => subStatus.contains('out_of_stock');

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
        subStatus: [
          for (final s in (json['sub_status'] as List?) ?? const []) s as String,
        ],
        logisticType: json['logistic_type'] as String?,
        permalink: json['permalink'] as String?,
        thumbnail: json['thumbnail'] as String?,
        hasVariations: asBool(json['has_variations']),
      );
}
