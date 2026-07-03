import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One line of the local-sale cart (client side, before the RPC writes it).
typedef LocalSaleLine = ({String productId, int quantity, double unitPrice});

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

  /// Product lines of one sale (ML mirrors its order_items; local sales write
  /// one line per cart product). Fetched on demand for the detail view.
  Future<List<SaleItem>> itemsFor(String saleId) async {
    final rows =
        await _client.from('sale_items').select().eq('sale_id', saleId);
    return rows.map<SaleItem>((r) => SaleItem.fromJson(r)).toList();
  }

  /// Sale lines that include one product — lets the product history show
  /// multi-item sales too (indexed by product_id).
  Future<List<SaleItem>> itemsForProduct(String productId,
      {int limit = 100}) async {
    final rows = await _client
        .from('sale_items')
        .select()
        .eq('product_id', productId)
        .limit(limit);
    return rows.map<SaleItem>((r) => SaleItem.fromJson(r)).toList();
  }

  /// Sales by id (resolves the parents of [itemsForProduct] in one query).
  Future<List<Sale>> byIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _client.from('sales').select().inFilter('id', ids);
    return rows.map<Sale>((r) => Sale.fromJson(r)).toList();
  }

  /// Registers a multi-item sale outside ML (channel=local) via the
  /// `create_local_sale` RPC. Transactional: the backend validates that every
  /// line is covered by the chosen warehouse's available stock BEFORE writing
  /// anything, so either the sale AND its stock discount happen, or neither.
  Future<String> createLocalSale({
    required List<LocalSaleLine> items,
    String? customerId,
    String? warehouseId,
    String? note,
  }) async {
    final id = await _client.rpc('create_local_sale', params: {
      'p_items': [
        for (final l in items)
          {
            'product_id': l.productId,
            'quantity': l.quantity,
            'unit_price': l.unitPrice,
          },
      ],
      'p_customer_id': customerId,
      'p_warehouse_id': warehouseId,
      'p_note': note,
    });
    return id as String;
  }
}
