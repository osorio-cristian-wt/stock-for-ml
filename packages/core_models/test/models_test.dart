import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  test('Product.fromJson handles string/num numeric fields', () {
    final p = Product.fromJson({
      'id': 'p1',
      'profile_id': 'u1',
      'title': 'Cargador',
      'sku': 'SKU-1',
      'purchase_cost': '4.00', // Supabase may send numeric as string
      'purchase_currency': 'USD',
      'current_stock': 3,
      'low_stock_threshold': 2,
      'is_active': true,
    });
    expect(p.purchaseCost, 4.0);
    expect(p.currentStock, 3);
    expect(p.isLowStock, isFalse); // 3 > 2
  });

  test('Product.isLowStock true at/below threshold', () {
    final p = Product.fromJson({
      'id': 'p1',
      'profile_id': 'u1',
      'title': 'X',
      'current_stock': 1,
      'low_stock_threshold': 1,
    });
    expect(p.isLowStock, isTrue);
  });

  test('Product.toInsert omits server-managed fields', () {
    const p = Product(id: 'x', profileId: 'u1', title: 'T', purchaseCost: 5);
    final ins = p.toInsert();
    expect(ins.containsKey('id'), isFalse);
    expect(ins.containsKey('current_stock'), isFalse);
    expect(ins['profile_id'], 'u1');
    expect(ins['purchase_cost'], 5);
  });

  test('MlListing.fromJson maps status enum', () {
    final l = MlListing.fromJson({
      'id': 'l1',
      'profile_id': 'u1',
      'ml_item_id': 'MLA1',
      'price': 25000,
      'available_quantity': 10,
      'status': 'active',
    });
    expect(l.status, ListingStatus.active);
    expect(l.price, 25000);
  });

  test('StockReason wire round-trips', () {
    expect(StockReason.sale.wire, 'sale');
    expect(StockReasonX.fromWire('initial_sync'), StockReason.initialSync);
    expect(StockReasonX.fromWire('return'), StockReason.returned);
  });

  test('StockMovement.fromJson parses negative delta', () {
    final m = StockMovement.fromJson({
      'id': 'm1',
      'profile_id': 'u1',
      'product_id': 'p1',
      'delta': -5,
      'reason': 'sale',
      'reference': 'ORDER-1',
    });
    expect(m.delta, -5);
    expect(m.reason, StockReason.sale);
  });

  test('AppAlert.fromJson maps out_of_stock', () {
    final a = AppAlert.fromJson({
      'id': 'a1',
      'profile_id': 'u1',
      'type': 'out_of_stock',
      'current_qty': 0,
    });
    expect(a.type, AlertType.outOfStock);
    expect(a.currentQty, 0);
  });

  test('ListingVariation.fromJson builds a label from attribute values', () {
    final v = ListingVariation.fromJson({
      'id': 'v1',
      'profile_id': 'u1',
      'ml_listing_id': 'l1',
      'ml_variation_id': '181234567',
      'attributes': [
        {'id': 'COLOR', 'name': 'Color', 'value_name': 'Rojo'},
        {'id': 'SIZE', 'name': 'Talle', 'value_name': 'XL'},
      ],
      'price': '15999.5',
      'available_quantity': 4,
    });
    expect(v.label, 'Rojo · XL');
    expect(v.price, 15999.5);
    expect(v.availableQuantity, 4);
  });

  test('ListingVariation.label falls back to the ML id', () {
    final v = ListingVariation.fromJson({
      'id': 'v1',
      'profile_id': 'u1',
      'ml_listing_id': 'l1',
      'ml_variation_id': '99',
    });
    expect(v.attributes, isEmpty);
    expect(v.label, 'Variación 99');
    expect(v.availableQuantity, 0);
  });
}
