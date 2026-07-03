import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Purchases (compras a proveedor) and their lines. RLS scopes rows to the user.
class PurchasesRepository {
  PurchasesRepository(this._client);

  final SupabaseClient _client;

  /// Live list of purchases, newest first.
  Stream<List<Purchase>> watchAll() {
    return _client
        .from('purchases')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows.map(Purchase.fromJson).toList());
  }

  Future<Purchase> byId(String id) async {
    final row = await _client.from('purchases').select().eq('id', id).single();
    return Purchase.fromJson(row);
  }

  /// Opens a new draft purchase and returns it.
  Future<Purchase> createDraft({
    required String profileId,
    String? supplierId,
    String? warehouseId,
    String currency = 'USD',
  }) async {
    final draft = Purchase(
      id: '',
      profileId: profileId,
      supplierId: supplierId,
      warehouseId: warehouseId,
      currency: currency,
    );
    final row =
        await _client.from('purchases').insert(draft.toInsert()).select().single();
    return Purchase.fromJson(row);
  }

  Future<void> updateHeader(
    String purchaseId, {
    String? supplierId,
    bool clearSupplier = false,
    String? warehouseId,
    String? reference,
    String? note,
  }) async {
    await _client.from('purchases').update({
      if (clearSupplier)
        'supplier_id': null
      else if (supplierId != null)
        'supplier_id': supplierId,
      if (warehouseId != null) 'warehouse_id': warehouseId,
      if (reference != null) 'reference': reference,
      if (note != null) 'note': note,
    }).eq('id', purchaseId);
  }

  /// Live lines of a purchase.
  Stream<List<PurchaseItem>> watchItems(String purchaseId) {
    return _client
        .from('purchase_items')
        .stream(primaryKey: ['id'])
        .eq('purchase_id', purchaseId)
        .map((rows) => rows.map(PurchaseItem.fromJson).toList());
  }

  Future<List<PurchaseItem>> itemsFor(String purchaseId) async {
    final rows = await _client
        .from('purchase_items')
        .select()
        .eq('purchase_id', purchaseId);
    return rows.map<PurchaseItem>((r) => PurchaseItem.fromJson(r)).toList();
  }

  /// Adds (or sums) a line. The scan flow calls this per scanned SKU.
  Future<void> addItem({
    required String purchaseId,
    required String productId,
    required int quantity,
    double? unitCost,
  }) async {
    await _client.rpc('add_purchase_item', params: {
      'p_purchase_id': purchaseId,
      'p_product_id': productId,
      'p_qty': quantity,
      'p_unit_cost': unitCost,
    });
  }

  Future<void> updateItem(
    String itemId, {
    int? quantity,
    double? unitCost,
  }) async {
    await _client.from('purchase_items').update({
      if (quantity != null) 'quantity': quantity,
      if (unitCost != null) 'unit_cost': unitCost,
    }).eq('id', itemId);
  }

  Future<void> removeItem(String itemId) async {
    await _client.from('purchase_items').delete().eq('id', itemId);
  }

  /// Closes the purchase: posts one on_hand movement per line and locks it.
  Future<void> close(String purchaseId) async {
    await _client.rpc('close_purchase', params: {'p_purchase_id': purchaseId});
  }

  Future<void> cancel(String purchaseId) async {
    await _client
        .from('purchases')
        .update({'status': PurchaseStatus.cancelled.wire})
        .eq('id', purchaseId);
  }

  /// Vision OCR of a supplier invoice via the `parse-invoice` Edge Function.
  /// Returns `{ supplier, date, currency, items: [{description, sku, quantity,
  /// unit_cost}] }` for the user to review/approve before creating items.
  Future<Map<String, dynamic>?> parseInvoice({
    required String imageBase64,
    required String mime,
  }) async {
    final res = await _client.functions.invoke('parse-invoice', body: {
      'image_base64': imageBase64,
      'mime': mime,
    });
    return res.data as Map<String, dynamic>?;
  }
}

/// Suppliers (proveedores). RLS scopes rows to the user.
class SuppliersRepository {
  SuppliersRepository(this._client);

  final SupabaseClient _client;

  Future<List<Supplier>> all() async {
    final rows = await _client.from('suppliers').select().order('name');
    return rows.map<Supplier>((r) => Supplier.fromJson(r)).toList();
  }

  Future<Supplier> create(Supplier s) async {
    final row =
        await _client.from('suppliers').insert(s.toInsert()).select().single();
    return Supplier.fromJson(row);
  }
}
