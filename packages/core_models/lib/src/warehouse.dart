import 'package:meta/meta.dart';

import 'json.dart';

/// A physical warehouse / stock location ("depósito").
@immutable
class Warehouse {
  const Warehouse({
    required this.id,
    required this.profileId,
    required this.code,
    required this.name,
    this.isDefault = false,
    this.isSellable = true,
  });

  final String id;
  final String profileId;
  final String code;
  final String name;

  /// Default dispatch warehouse for ML sales.
  final bool isDefault;

  /// Whether this warehouse counts toward the available quantity published to ML.
  final bool isSellable;

  factory Warehouse.fromJson(Map<String, dynamic> json) => Warehouse(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        isDefault: asBool(json['is_default']),
        isSellable: asBool(json['is_sellable'], true),
      );

  Map<String, dynamic> toInsert() => {
        'profile_id': profileId,
        'code': code,
        'name': name,
        'is_default': isDefault,
        'is_sellable': isSellable,
      };
}

/// Per-(product, warehouse) stock buckets. available = onHand − reserved.
@immutable
class ProductStock {
  const ProductStock({
    required this.productId,
    required this.warehouseId,
    this.incoming = 0,
    this.onHand = 0,
    this.reserved = 0,
  });

  final String productId;
  final String warehouseId;
  final int incoming;
  final int onHand;
  final int reserved;

  int get available => onHand - reserved;

  factory ProductStock.fromJson(Map<String, dynamic> json) => ProductStock(
        productId: json['product_id'] as String,
        warehouseId: json['warehouse_id'] as String,
        incoming: asInt(json['incoming']),
        onHand: asInt(json['on_hand']),
        reserved: asInt(json['reserved']),
      );
}
