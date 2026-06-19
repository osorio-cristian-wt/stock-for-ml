import 'package:meta/meta.dart';

import 'json.dart';

enum StockReason {
  purchase,
  sale,
  adjustment,
  returned,
  initialSync,
  purchaseOrdered,
  purchaseReceived,
  reserve,
  dispatch,
  cancellation,
  bounce,
  loss,
  transfer,
}

extension StockReasonX on StockReason {
  String get wire => switch (this) {
        StockReason.purchase => 'purchase',
        StockReason.sale => 'sale',
        StockReason.adjustment => 'adjustment',
        StockReason.returned => 'return',
        StockReason.initialSync => 'initial_sync',
        StockReason.purchaseOrdered => 'purchase_ordered',
        StockReason.purchaseReceived => 'purchase_received',
        StockReason.reserve => 'reserve',
        StockReason.dispatch => 'dispatch',
        StockReason.cancellation => 'cancellation',
        StockReason.bounce => 'bounce',
        StockReason.loss => 'loss',
        StockReason.transfer => 'transfer',
      };

  static StockReason fromWire(String? v) => switch (v) {
        'purchase' => StockReason.purchase,
        'sale' => StockReason.sale,
        'adjustment' => StockReason.adjustment,
        'return' => StockReason.returned,
        'initial_sync' => StockReason.initialSync,
        'purchase_ordered' => StockReason.purchaseOrdered,
        'purchase_received' => StockReason.purchaseReceived,
        'reserve' => StockReason.reserve,
        'dispatch' => StockReason.dispatch,
        'cancellation' => StockReason.cancellation,
        'bounce' => StockReason.bounce,
        'loss' => StockReason.loss,
        'transfer' => StockReason.transfer,
        _ => StockReason.adjustment,
      };
}

/// Which quantity bucket a movement affects (two-phase, per-warehouse model).
enum StockBucket { incoming, onHand, reserved }

extension StockBucketX on StockBucket {
  String get wire => switch (this) {
        StockBucket.incoming => 'incoming',
        StockBucket.onHand => 'on_hand',
        StockBucket.reserved => 'reserved',
      };

  static StockBucket fromWire(String? v) => switch (v) {
        'incoming' => StockBucket.incoming,
        'reserved' => StockBucket.reserved,
        _ => StockBucket.onHand,
      };
}

/// Origin of a movement. Only [user]/[system] are pushed back to ML.
enum StockOrigin { ml, user, system }

extension StockOriginX on StockOrigin {
  String get wire => switch (this) {
        StockOrigin.ml => 'ml',
        StockOrigin.user => 'user',
        StockOrigin.system => 'system',
      };

  static StockOrigin fromWire(String? v) => switch (v) {
        'ml' => StockOrigin.ml,
        'system' => StockOrigin.system,
        _ => StockOrigin.user,
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
    this.warehouseId,
    this.bucket = StockBucket.onHand,
    this.origin = StockOrigin.user,
    this.reference,
    this.note,
    this.createdAt,
  });

  final String id;
  final String profileId;
  final String productId;
  final int delta;
  final StockReason reason;
  final String? warehouseId;
  final StockBucket bucket;
  final StockOrigin origin;
  final String? reference;
  final String? note;
  final DateTime? createdAt;

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        productId: json['product_id'] as String,
        delta: asInt(json['delta']),
        reason: StockReasonX.fromWire(json['reason'] as String?),
        warehouseId: json['warehouse_id'] as String?,
        bucket: StockBucketX.fromWire(json['bucket'] as String?),
        origin: StockOriginX.fromWire(json['origin'] as String?),
        reference: json['reference'] as String?,
        note: json['note'] as String?,
        createdAt: asDateTime(json['created_at']),
      );
}
