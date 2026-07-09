import 'package:meta/meta.dart';

import 'json.dart';
import 'ml_listing.dart';

/// Pure profit math — mirrors the SQL view `public.v_product_economics`
/// and the TS `computeEconomics`. Single source of truth on the client.
@immutable
class Economics {
  const Economics({
    required this.costInSaleCurrency,
    required this.netProfit,
    required this.markupPct,
    required this.marginPct,
  });

  /// Purchase cost expressed in the sale currency (via FX).
  final double costInSaleCurrency;

  /// price − fee − cost.
  final double netProfit;

  /// Profit over cost (%). Null when cost is 0.
  final double? markupPct;

  /// Profit over sale price (%). Null when price is 0.
  final double? marginPct;

  bool get isProfitable => netProfit > 0;
}

double _round2(double n) => (n * 100).round() / 100;

/// Computes economics for a listing.
///
/// - [salePrice] and [estSaleFee] are in the listing currency (e.g. ARS).
/// - [purchaseCost] is in its own currency (e.g. USD).
/// - [fxRate] converts purchaseCost into the sale currency.
Economics computeEconomics({
  required double salePrice,
  required double estSaleFee,
  required double purchaseCost,
  required double fxRate,
}) {
  final cost = _round2(purchaseCost * fxRate);
  final net = _round2(salePrice - estSaleFee - cost);
  return Economics(
    costInSaleCurrency: cost,
    netProfit: net,
    markupPct: cost > 0 ? _round2(net / cost * 100) : null,
    marginPct: salePrice > 0 ? _round2(net / salePrice * 100) : null,
  );
}

/// A row from the `v_product_economics` view (server-computed).
@immutable
class ProductEconomics {
  const ProductEconomics({
    required this.listingId,
    required this.productId,
    required this.title,
    required this.mlItemId,
    required this.salePrice,
    required this.currencyId,
    required this.costInSaleCurrency,
    required this.estSaleFee,
    required this.netProfit,
    required this.markupPct,
    required this.marginPct,
    required this.fxRate,
    this.hasCost = true,
    this.listingStatus = ListingStatus.unknown,
    this.subStatus = const [],
    this.logisticType,
    this.permalink,
  });

  final String listingId;
  final String? productId;
  final String title;
  final String? mlItemId;
  final double salePrice;
  final String currencyId;
  final double costInSaleCurrency;
  final double estSaleFee;

  /// Null when the product has no purchase cost loaded (RF-40): the view
  /// refuses to compute a fake profit instead of inflating it with cost 0.
  final double? netProfit;
  final double? markupPct;
  final double? marginPct;
  final double fxRate;

  /// Whether the product has a usable purchase cost (RF-40). Without it,
  /// profit/markup/margin are null and the product must stay out of stats.
  final bool hasCost;

  /// Estado de la publicación en ML (RF-37): chips y filtros en Productos.
  final ListingStatus listingStatus;

  /// sub_status de ML (out_of_stock, paused_by_seller, …). RF-37.
  final List<String> subStatus;

  /// fulfillment ⇒ stock administrado por ML Full (RF-38).
  final String? logisticType;

  /// Link a la publicación en ML (RF-42: el precio se modifica allá).
  final String? permalink;

  bool get isFulfillment => logisticType == 'fulfillment';
  bool get isPausedBySeller => subStatus.contains('paused_by_seller');
  bool get isOutOfStock => subStatus.contains('out_of_stock');

  factory ProductEconomics.fromJson(Map<String, dynamic> json) =>
      ProductEconomics(
        listingId: json['listing_id'] as String,
        productId: json['product_id'] as String?,
        title: (json['title'] as String?) ?? '',
        mlItemId: json['ml_item_id'] as String?,
        salePrice: asDouble(json['sale_price']),
        currencyId: (json['currency_id'] as String?) ?? 'ARS',
        costInSaleCurrency: asDouble(json['cost_in_sale_currency']),
        estSaleFee: asDouble(json['est_sale_fee']),
        netProfit: asDoubleOrNull(json['net_profit']),
        markupPct: asDoubleOrNull(json['markup_pct']),
        marginPct: asDoubleOrNull(json['margin_pct']),
        fxRate: asDouble(json['fx_rate']),
        hasCost: asBool(json['has_cost'], asDouble(json['cost_in_sale_currency']) > 0),
        listingStatus: listingStatusFrom(json['listing_status'] as String?),
        subStatus: [
          for (final s in (json['sub_status'] as List?) ?? const []) s as String,
        ],
        logisticType: json['logistic_type'] as String?,
        permalink: json['permalink'] as String?,
      );
}
