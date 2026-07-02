import 'package:meta/meta.dart';

import 'json.dart';

/// Lifecycle of a purchase. `draft` while loading items; `closed` once it has
/// posted its stock movements; `cancelled` if discarded.
enum PurchaseStatus { draft, closed, cancelled }

extension PurchaseStatusX on PurchaseStatus {
  String get wire => switch (this) {
        PurchaseStatus.draft => 'draft',
        PurchaseStatus.closed => 'closed',
        PurchaseStatus.cancelled => 'cancelled',
      };

  static PurchaseStatus fromWire(String? v) => switch (v) {
        'closed' => PurchaseStatus.closed,
        'cancelled' => PurchaseStatus.cancelled,
        _ => PurchaseStatus.draft,
      };
}

/// A purchase to a supplier. The header; lines live in [PurchaseItem].
@immutable
class Purchase {
  const Purchase({
    required this.id,
    required this.profileId,
    this.supplierId,
    this.warehouseId,
    this.status = PurchaseStatus.draft,
    this.reference,
    this.note,
    this.currency = 'USD',
    this.total = 0,
    this.purchasedAt,
    this.createdAt,
  });

  final String id;
  final String profileId;
  final String? supplierId;
  final String? warehouseId;
  final PurchaseStatus status;

  /// Supplier invoice / remito number.
  final String? reference;
  final String? note;
  final String currency;
  final double total;
  final DateTime? purchasedAt;
  final DateTime? createdAt;

  bool get isDraft => status == PurchaseStatus.draft;

  factory Purchase.fromJson(Map<String, dynamic> json) => Purchase(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        supplierId: json['supplier_id'] as String?,
        warehouseId: json['warehouse_id'] as String?,
        status: PurchaseStatusX.fromWire(json['status'] as String?),
        reference: json['reference'] as String?,
        note: json['note'] as String?,
        currency: (json['currency'] as String?) ?? 'USD',
        total: asDouble(json['total']),
        purchasedAt: asDateTime(json['purchased_at']),
        createdAt: asDateTime(json['created_at']),
      );

  Map<String, dynamic> toInsert() => {
        'profile_id': profileId,
        if (supplierId != null) 'supplier_id': supplierId,
        if (warehouseId != null) 'warehouse_id': warehouseId,
        'status': status.wire,
        if (reference != null) 'reference': reference,
        if (note != null) 'note': note,
        'currency': currency,
      };

  Purchase copyWith({
    String? supplierId,
    String? warehouseId,
    PurchaseStatus? status,
    String? reference,
    String? note,
    String? currency,
  }) =>
      Purchase(
        id: id,
        profileId: profileId,
        supplierId: supplierId ?? this.supplierId,
        warehouseId: warehouseId ?? this.warehouseId,
        status: status ?? this.status,
        reference: reference ?? this.reference,
        note: note ?? this.note,
        currency: currency ?? this.currency,
        total: total,
        purchasedAt: purchasedAt,
        createdAt: createdAt,
      );
}

/// A single line of a [Purchase]: a product, a quantity and its unit cost.
@immutable
class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.profileId,
    required this.purchaseId,
    required this.productId,
    this.quantity = 1,
    this.unitCost = 0,
    this.currency = 'USD',
    this.createdAt,
  });

  final String id;
  final String profileId;
  final String purchaseId;
  final String productId;
  final int quantity;
  final double unitCost;
  final String currency;
  final DateTime? createdAt;

  double get lineTotal => quantity * unitCost;

  factory PurchaseItem.fromJson(Map<String, dynamic> json) => PurchaseItem(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        purchaseId: json['purchase_id'] as String,
        productId: json['product_id'] as String,
        quantity: asInt(json['quantity'], 1),
        unitCost: asDouble(json['unit_cost']),
        currency: (json['currency'] as String?) ?? 'USD',
        createdAt: asDateTime(json['created_at']),
      );

  Map<String, dynamic> toInsert() => {
        'profile_id': profileId,
        'purchase_id': purchaseId,
        'product_id': productId,
        'quantity': quantity,
        'unit_cost': unitCost,
        'currency': currency,
      };
}
