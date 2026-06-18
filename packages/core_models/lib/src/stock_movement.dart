import 'package:meta/meta.dart';

import 'json.dart';

enum StockReason { purchase, sale, adjustment, returned, initialSync }

extension StockReasonX on StockReason {
  String get wire => switch (this) {
        StockReason.purchase => 'purchase',
        StockReason.sale => 'sale',
        StockReason.adjustment => 'adjustment',
        StockReason.returned => 'return',
        StockReason.initialSync => 'initial_sync',
      };

  static StockReason fromWire(String? v) => switch (v) {
        'purchase' => StockReason.purchase,
        'sale' => StockReason.sale,
        'adjustment' => StockReason.adjustment,
        'return' => StockReason.returned,
        'initial_sync' => StockReason.initialSync,
        _ => StockReason.adjustment,
      };
}

/// A single entry in the append-only stock ledger.
@immutable
class StockMovement {
  const StockMovement({
    required this.id,
    required this.profileId,
    required this.productId,
    required this.delta,
    required this.reason,
    this.reference,
    this.note,
    this.createdAt,
  });

  final String id;
  final String profileId;
  final String productId;
  final int delta;
  final StockReason reason;
  final String? reference;
  final String? note;
  final DateTime? createdAt;

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        productId: json['product_id'] as String,
        delta: asInt(json['delta']),
        reason: StockReasonX.fromWire(json['reason'] as String?),
        reference: json['reference'] as String?,
        note: json['note'] as String?,
        createdAt: asDateTime(json['created_at']),
      );
}
