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

  /// Updates the editable fields of an existing product (title, codes, cost,
  /// threshold, etc). Stock is never edited here — it flows through the ledger.
  Future<Product> update(Product product) async {
    final row = await _client
        .from('products')
        .update(product.toInsert())
        .eq('id', product.id)
        .select()
        .single();
    return Product.fromJson(row);
  }

  /// Barcode-first "already exists?" check: matches a scanned code against the
  /// global barcode (gtin) or the internal sku. Returns null if it's new.
  Future<Product?> findByCode(String code) async {
    final rows = await _client
        .from('products')
        .select()
        .or('gtin.eq.$code,sku.eq.$code')
        .limit(1);
    return rows.isEmpty ? null : Product.fromJson(rows.first);
  }

  /// Registers a stock movement via the SECURITY INVOKER RPC; the DB trigger
  /// updates product_stock buckets, recomputes current_stock (available) and —
  /// for user/system origin — enqueues an ML push.
  Future<void> applyStockMovement({
    required String productId,
    required int delta,
    required StockReason reason,
    String? reference,
    String? note,
    String? warehouseId,
    StockBucket bucket = StockBucket.onHand,
    StockOrigin origin = StockOrigin.user,
  }) async {
    await _client.rpc('apply_stock_movement', params: {
      'p_product_id': productId,
      'p_delta': delta,
      'p_reason': reason.wire,
      'p_reference': reference,
      'p_note': note,
      'p_warehouse_id': warehouseId,
      'p_bucket': bucket.wire,
      'p_origin': origin.wire,
    });
  }

  /// Stock ledger entries for a product (newest first) — drives the per-product
  /// history timeline together with sales.
  Future<List<StockMovement>> movementsFor(String productId, {int limit = 100}) async {
    final rows = await _client
        .from('stock_movements')
        .select()
        .eq('product_id', productId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map<StockMovement>((r) => StockMovement.fromJson(r)).toList();
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
