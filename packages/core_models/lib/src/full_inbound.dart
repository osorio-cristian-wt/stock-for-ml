import 'package:meta/meta.dart';

import 'json.dart';

/// Stock increase detected in ML Full pending user attribution (RF-38):
/// the user says which local warehouse the merchandise left from (local-only
/// deduction, never pushed to ML) or dismisses it (e.g. bought straight
/// into Full).
@immutable
class FullInbound {
  const FullInbound({
    required this.id,
    required this.productId,
    required this.qty,
    required this.status,
    this.mlItemId,
    this.warehouseId,
    this.detectedAt,
    this.resolvedAt,
  });

  final String id;
  final String productId;
  final String? mlItemId;
  final int qty;

  /// pending | attributed | dismissed.
  final String status;

  /// Local warehouse the stock was attributed to (when resolved).
  final String? warehouseId;
  final DateTime? detectedAt;
  final DateTime? resolvedAt;

  bool get isPending => status == 'pending';

  factory FullInbound.fromJson(Map<String, dynamic> json) => FullInbound(
        id: json['id'] as String,
        productId: json['product_id'] as String,
        mlItemId: json['ml_item_id'] as String?,
        qty: asInt(json['qty']),
        status: (json['status'] as String?) ?? 'pending',
        warehouseId: json['warehouse_id'] as String?,
        detectedAt: asDateTime(json['detected_at']),
        resolvedAt: asDateTime(json['resolved_at']),
      );
}
