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

  /// Realtime list of warehouses (default first, then by name).
  Stream<List<Warehouse>> watchWarehouses() {
    return _client
        .from('warehouses')
        .stream(primaryKey: ['id'])
        .order('name')
        .map((rows) {
      final list = rows.map(Warehouse.fromJson).toList()
        ..sort((a, b) {
          if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      return list;
    });
  }

  /// Lazily creates the "Depósito principal" for the user and returns its id.
  Future<String> ensureDefaultWarehouse() async {
    final id = await _client.rpc('ensure_default_warehouse_self');
    return id as String;
  }

  Future<Warehouse> createWarehouse(Warehouse w) async {
    final row = await _client.from('warehouses').insert(w.toInsert()).select().single();
    return Warehouse.fromJson(row);
  }

  /// Switches which warehouse is the default (dispatch) one.
  Future<void> setDefaultWarehouse(String warehouseId) async {
    await _client.rpc('set_default_warehouse', params: {'p_warehouse_id': warehouseId});
  }

  /// Toggles whether a warehouse counts toward the available published to ML.
  Future<void> setSellable(String warehouseId, bool sellable) async {
    await _client
        .from('warehouses')
        .update({'is_sellable': sellable}).eq('id', warehouseId);
  }

  /// Moves [qty] units of a product between two warehouses (internal control).
  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required int qty,
    String? note,
  }) async {
    await _client.rpc('transfer_stock', params: {
      'p_product_id': productId,
      'p_from_warehouse': fromWarehouseId,
      'p_to_warehouse': toWarehouseId,
      'p_qty': qty,
      'p_note': note,
    });
  }

  /// Realtime per-warehouse stock buckets for a product.
  Stream<List<ProductStock>> watchStockFor(String productId) {
    return _client
        .from('product_stock')
        .stream(primaryKey: ['product_id', 'warehouse_id'])
        .eq('product_id', productId)
        .map((rows) => rows.map(ProductStock.fromJson).toList());
  }

  /// Realtime stock rows of one warehouse (drives the per-warehouse view).
  Stream<List<ProductStock>> watchStockInWarehouse(String warehouseId) {
    return _client
        .from('product_stock')
        .stream(primaryKey: ['product_id', 'warehouse_id'])
        .eq('warehouse_id', warehouseId)
        .map((rows) => rows.map(ProductStock.fromJson).toList());
  }

  /// Realtime stock rows of every warehouse (totals in the warehouses list).
  Stream<List<ProductStock>> watchAllStock() {
    return _client
        .from('product_stock')
        .stream(primaryKey: ['product_id', 'warehouse_id'])
        .map((rows) => rows.map(ProductStock.fromJson).toList());
  }

  /// Realtime ledger of one warehouse (newest first) — the warehouse history.
  Stream<List<StockMovement>> watchMovementsInWarehouse(
    String warehouseId, {
    int limit = 50,
  }) {
    return _client
        .from('stock_movements')
        .stream(primaryKey: ['id'])
        .eq('warehouse_id', warehouseId)
        .order('created_at')
        .limit(limit)
        .map((rows) => rows.map(StockMovement.fromJson).toList());
  }

  /// Realtime transfer movements (both legs of every transfer, newest first)
  /// — feeds the unified Movimientos tab, which collapses each pair.
  Stream<List<StockMovement>> watchTransfers({int limit = 200}) {
    return _client
        .from('stock_movements')
        .stream(primaryKey: ['id'])
        .eq('reason', 'transfer')
        .order('created_at')
        .limit(limit)
        .map((rows) => rows.map(StockMovement.fromJson).toList());
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

  /// Renombra una categoría (el slug se regenera para mantener la unicidad).
  Future<void> renameCategory(String id, String name, String slug) async {
    await _client
        .from('product_categories')
        .update({'name': name, 'slug': slug}).eq('id', id);
  }

  /// Elimina la categoría; los productos que la usaban quedan "sin categoría"
  /// (FK con on delete set null).
  Future<void> deleteCategory(String id) async {
    await _client.from('product_categories').delete().eq('id', id);
  }

  /// Per-warehouse stock buckets for a product (incoming / on_hand / reserved).
  Future<List<ProductStock>> stockFor(String productId) async {
    final rows =
        await _client.from('product_stock').select().eq('product_id', productId);
    return rows.map<ProductStock>((r) => ProductStock.fromJson(r)).toList();
  }
}
