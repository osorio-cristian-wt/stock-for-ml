import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  group('computeEconomics', () {
    test('matches the seeded headphones figures', () {
      final e = computeEconomics(
        salePrice: 25000,
        estSaleFee: 3000,
        purchaseCost: 8.5,
        fxRate: 1200,
      );
      expect(e.costInSaleCurrency, 10200);
      expect(e.netProfit, 11800);
      expect(e.markupPct, 115.69);
      expect(e.marginPct, 47.2);
      expect(e.isProfitable, isTrue);
    });

    test('null ratios when cost/price are zero', () {
      final e = computeEconomics(
          salePrice: 0, estSaleFee: 0, purchaseCost: 0, fxRate: 1200);
      expect(e.markupPct, isNull);
      expect(e.marginPct, isNull);
    });

    test('detects a loss', () {
      final e = computeEconomics(
          salePrice: 1000, estSaleFee: 200, purchaseCost: 1, fxRate: 1200);
      expect(e.costInSaleCurrency, 1200);
      expect(e.netProfit, -400);
      expect(e.isProfitable, isFalse);
    });
  });

  test('ProductEconomics.fromJson parses the view row', () {
    final pe = ProductEconomics.fromJson({
      'listing_id': 'l1',
      'product_id': 'p1',
      'title': 'Auriculares',
      'ml_item_id': 'MLA1',
      'sale_price': 25000,
      'currency_id': 'ARS',
      'cost_in_sale_currency': 10200,
      'est_sale_fee': 3000,
      'net_profit': 11800,
      'markup_pct': 115.69,
      'margin_pct': 47.2,
      'fx_rate': 1200,
    });
    expect(pe.title, 'Auriculares');
    expect(pe.netProfit, 11800);
    expect(pe.markupPct, 115.69);
  });
}
