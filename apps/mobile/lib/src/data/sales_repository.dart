import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sales: orders imported from ML plus local (direct) sales. RLS scopes rows
/// to the user.
class SalesRepository {
  SalesRepository(this._client);

  final SupabaseClient _client;

  /// Most recent sales first (for the Ventas screen and Inicio summary).
  Future<List<Sale>> recent({int limit = 60}) async {
    final rows = await _client
        .from('sales')
        .select()
        .order('sold_at', ascending: false)
        .limit(limit);
    return rows.map<Sale>((r) => Sale.fromJson(r)).toList();
  }

  /// Registers a sale outside ML (channel=local): creates the sale row and
  /// discounts on_hand stock; the backend pushes the new availability to ML.
  Future<String> createLocalSale({
    required String productId,
    required int quantity,
    required double unitPrice,
    String? customerId,
    String? warehouseId,
    String? note,
  }) async {
    final id = await _client.rpc('create_local_sale', params: {
      'p_product_id': productId,
      'p_quantity': quantity,
      'p_unit_price': unitPrice,
      'p_customer_id': customerId,
      'p_warehouse_id': warehouseId,
      'p_note': note,
    });
    return id as String;
  }
}
