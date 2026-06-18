import 'package:meta/meta.dart';

import 'json.dart';

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
  });

  final String listingId;
  final String? productId;
  final String title;
  final String? mlItemId;
  final double salePrice;
  final String currencyId;
  final double costInSaleCurrency;
  final double estSaleFee;
  final double netProfit;
  final double? markupPct;
  final double? marginPct;
  final double fxRate;

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
        netProfit: asDouble(json['net_profit']),
        markupPct: asDoubleOrNull(json['markup_pct']),
        marginPct: asDoubleOrNull(json['margin_pct']),
        fxRate: asDouble(json['fx_rate']),
      );
}
