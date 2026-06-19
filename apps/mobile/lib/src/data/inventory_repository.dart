import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Warehouses, internal categories and per-warehouse stock. RLS scopes every
/// query to the authenticated user.
class InventoryRepository {
  InventoryRepository(this._client);

  final SupabaseClient _client;

  Future<List<Warehouse>> warehouses() async {
    final rows = await _client.from('warehouses').select().order('name');
    return rows.map<Warehouse>((r) => Warehouse.fromJson(r)).toList();
  }

  Future<Warehouse> createWarehouse(Warehouse w) async {
    final row = await _client.from('warehouses').insert(w.toInsert()).select().single();
    return Warehouse.fromJson(row);
  }

  Future<List<ProductCategory>> categories() async {
    final rows = await _client.from('product_categories').select().order('name');
    return rows.map<ProductCategory>((r) => ProductCategory.fromJson(r)).toList();
  }

  Future<ProductCategory> createCategory(ProductCategory c) async {
    final row =
        await _client.from('product_categories').insert(c.toInsert()).select().single();
    return ProductCategory.fromJson(row);
  }

  /// Per-warehouse stock buckets for a product (incoming / on_hand / reserved).
  Future<List<ProductStock>> stockFor(String productId) async {
    final rows =
        await _client.from('product_stock').select().eq('product_id', productId);
    return rows.map<ProductStock>((r) => ProductStock.fromJson(r)).toList();
  }
}
