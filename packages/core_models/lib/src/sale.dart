import 'package:meta/meta.dart';

import 'json.dart';

/// Fulfillment lifecycle of an order line (derived from order + shipment state).
enum FulfillmentStatus { reserved, shipped, delivered, cancelled, bounced, lost }

extension FulfillmentStatusX on FulfillmentStatus {
  String get wire => switch (this) {
        FulfillmentStatus.reserved => 'reserved',
        FulfillmentStatus.shipped => 'shipped',
        FulfillmentStatus.delivered => 'delivered',
        FulfillmentStatus.cancelled => 'cancelled',
        FulfillmentStatus.bounced => 'bounced',
        FulfillmentStatus.lost => 'lost',
      };

  static FulfillmentStatus? fromWire(String? v) => switch (v) {
        'reserved' => FulfillmentStatus.reserved,
        'shipped' => FulfillmentStatus.shipped,
        'delivered' => FulfillmentStatus.delivered,
        'cancelled' => FulfillmentStatus.cancelled,
        'bounced' => FulfillmentStatus.bounced,
        'lost' => FulfillmentStatus.lost,
        _ => null,
      };
}

/// Where a sale happened: on MercadoLibre or directly ("venta local").
enum SaleChannel { ml, local }

extension SaleChannelX on SaleChannel {
  String get wire => switch (this) {
        SaleChannel.ml => 'ml',
        SaleChannel.local => 'local',
      };

  static SaleChannel fromWire(String? v) =>
      v == 'local' ? SaleChannel.local : SaleChannel.ml;
}

/// A sale: an order imported from MercadoLibre or a local (direct) sale
/// registered in the app, distinguished by [channel].
@immutable
class Sale {
  const Sale({
    required this.id,
    required this.profileId,
    this.mlOrderId,
    this.mlItemId,
    this.productId,
    this.channel = SaleChannel.ml,
    this.customerId,
    this.quantity = 1,
    this.unitPrice = 0,
    this.currencyId = 'ARS',
    this.saleFee = 0,
    this.shippingCost = 0,
    this.netAmount,
    this.status,
    this.fulfillmentStatus,
    this.soldAt,
    this.note,
  });

  final String id;
  final String profileId;

  /// ML order id; null for local sales.
  final String? mlOrderId;
  final String? mlItemId;
  final String? productId;
  final SaleChannel channel;

  /// Optional customer of a local sale.
  final String? customerId;
  final int quantity;
  final double unitPrice;
  final String currencyId;
  final double saleFee;
  final double shippingCost;
  final double? netAmount;
  final String? status;
  final FulfillmentStatus? fulfillmentStatus;
  final DateTime? soldAt;
  final String? note;

  bool get isLocal => channel == SaleChannel.local;

  double get gross => unitPrice * quantity;

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        mlOrderId: json['ml_order_id'] as String?,
        mlItemId: json['ml_item_id'] as String?,
        productId: json['product_id'] as String?,
        channel: SaleChannelX.fromWire(json['channel'] as String?),
        customerId: json['customer_id'] as String?,
        quantity: asInt(json['quantity'], 1),
        unitPrice: asDouble(json['unit_price']),
        currencyId: (json['currency_id'] as String?) ?? 'ARS',
        saleFee: asDouble(json['sale_fee']),
        shippingCost: asDouble(json['shipping_cost']),
        netAmount: asDoubleOrNull(json['net_amount']),
        status: json['status'] as String?,
        fulfillmentStatus:
            FulfillmentStatusX.fromWire(json['fulfillment_status'] as String?),
        soldAt: asDateTime(json['sold_at']),
        note: json['note'] as String?,
      );
}
