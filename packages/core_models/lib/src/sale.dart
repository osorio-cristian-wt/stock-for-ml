import 'package:meta/meta.dart';

import 'json.dart';

/// A sale (order) imported from MercadoLibre.
@immutable
class Sale {
  const Sale({
    required this.id,
    required this.profileId,
    required this.mlOrderId,
    this.mlItemId,
    this.productId,
    this.quantity = 1,
    this.unitPrice = 0,
    this.currencyId = 'ARS',
    this.saleFee = 0,
    this.shippingCost = 0,
    this.netAmount,
    this.status,
    this.soldAt,
  });

  final String id;
  final String profileId;
  final String mlOrderId;
  final String? mlItemId;
  final String? productId;
  final int quantity;
  final double unitPrice;
  final String currencyId;
  final double saleFee;
  final double shippingCost;
  final double? netAmount;
  final String? status;
  final DateTime? soldAt;

  double get gross => unitPrice * quantity;

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        mlOrderId: json['ml_order_id'] as String,
        mlItemId: json['ml_item_id'] as String?,
        productId: json['product_id'] as String?,
        quantity: asInt(json['quantity'], 1),
        unitPrice: asDouble(json['unit_price']),
        currencyId: (json['currency_id'] as String?) ?? 'ARS',
        saleFee: asDouble(json['sale_fee']),
        shippingCost: asDouble(json['shipping_cost']),
        netAmount: asDoubleOrNull(json['net_amount']),
        status: json['status'] as String?,
        soldAt: asDateTime(json['sold_at']),
      );
}
