import 'package:meta/meta.dart';

import 'json.dart';

enum AlertType { lowStock, outOfStock, newOrder, priceChange, unknown }

AlertType alertTypeFrom(String? v) => switch (v) {
      'low_stock' => AlertType.lowStock,
      'out_of_stock' => AlertType.outOfStock,
      'new_order' => AlertType.newOrder,
      'price_change' => AlertType.priceChange,
      _ => AlertType.unknown,
    };

@immutable
class AppAlert {
  const AppAlert({
    required this.id,
    required this.profileId,
    required this.type,
    this.productId,
    this.message,
    this.threshold,
    this.currentQty,
    this.isRead = false,
    this.createdAt,
  });

  final String id;
  final String profileId;
  final AlertType type;
  final String? productId;
  final String? message;
  final int? threshold;
  final int? currentQty;
  final bool isRead;
  final DateTime? createdAt;

  factory AppAlert.fromJson(Map<String, dynamic> json) => AppAlert(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        type: alertTypeFrom(json['type'] as String?),
        productId: json['product_id'] as String?,
        message: json['message'] as String?,
        threshold: asIntOrNull(json['threshold']),
        currentQty: asIntOrNull(json['current_qty']),
        isRead: asBool(json['is_read']),
        createdAt: asDateTime(json['created_at']),
      );
}
