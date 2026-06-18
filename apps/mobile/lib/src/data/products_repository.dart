import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Data access for products and stock. RLS scopes every query to the
/// authenticated user automatically, so no profile filter is needed here.
class ProductsRepository {
  ProductsRepository(this._client);

  final SupabaseClient _client;

  Future<List<Product>> fetchAll() async {
    final rows = await _client
        .from('products')
        .select()
        .order('title', ascending: true);
    return rows.map<Product>((r) => Product.fromJson(r)).toList();
  }

  Future<Product> create(Product product) async {
    final row =
        await _client.from('products').insert(product.toInsert()).select().single();
    return Product.fromJson(row);
  }

  Future<void> updatePurchaseCost(String productId, double cost) async {
    await _client.from('products').update({'purchase_cost': cost}).eq('id', productId);
  }

  /// Registers a stock movement via the SECURITY INVOKER RPC; the DB trigger
  /// recomputes current_stock and may raise a low-stock alert.
  Future<void> applyStockMovement({
    required String productId,
    required int delta,
    required StockReason reason,
    String? reference,
    String? note,
  }) async {
    await _client.rpc('apply_stock_movement', params: {
      'p_product_id': productId,
      'p_delta': delta,
      'p_reason': reason.wire,
      'p_reference': reference,
      'p_note': note,
    });
  }

  /// Realtime stream of products for live stock updates.
  Stream<List<Product>> watchAll() {
    return _client
        .from('products')
        .stream(primaryKey: ['id'])
        .order('title')
        .map((rows) => rows.map(Product.fromJson).toList());
  }
}
