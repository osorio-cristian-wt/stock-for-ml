import 'package:supabase_flutter/supabase_flutter.dart';

/// One competing listing within ML for the same product/category.
class CompetitorPrice {
  const CompetitorPrice({
    required this.sellerName,
    required this.price,
    this.currencyId = 'ARS',
    this.reputation,
    this.isFull = false,
    this.diffPct,
    this.permalink,
  });

  final String sellerName;
  final double price;
  final String currencyId;

  /// 0..5 seller reputation, when available.
  final double? reputation;
  final bool isFull;

  /// Price difference vs. your listing (negative = cheaper than you).
  final double? diffPct;
  final String? permalink;

  factory CompetitorPrice.fromJson(Map<String, dynamic> j) => CompetitorPrice(
        sellerName: (j['seller_name'] as String?) ?? 'Vendedor',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        currencyId: (j['currency_id'] as String?) ?? 'ARS',
        reputation: (j['reputation'] as num?)?.toDouble(),
        isFull: j['is_full'] == true,
        diffPct: (j['diff_pct'] as num?)?.toDouble(),
        permalink: j['permalink'] as String?,
      );
}

/// Your listing + the competition, sorted cheapest-first.
class PriceComparison {
  const PriceComparison({
    required this.title,
    required this.yourPrice,
    required this.categoryId,
    required this.competitors,
    this.yourSold = 0,
    this.yourStock = 0,
  });

  final String title;
  final double yourPrice;
  final String? categoryId;
  final int yourSold;
  final int yourStock;
  final List<CompetitorPrice> competitors;

  /// Cheapest competitor, if any.
  CompetitorPrice? get cheapest =>
      competitors.isEmpty ? null : competitors.first;

  bool get youAreCheapest =>
      cheapest == null || yourPrice <= cheapest!.price;
}

/// Compares your published price against the competition **inside ML** (a
/// must-have of the MVP). Delegates to the `price-comparison` Edge Function,
/// which queries ML's search API server-side (the app never calls ML directly).
class PriceComparisonRepository {
  PriceComparisonRepository(this._client);

  final SupabaseClient _client;

  Future<PriceComparison> compare({
    required String listingId,
    String? mlItemId,
  }) async {
    final res = await _client.functions.invoke('price-comparison', body: {
      'listing_id': listingId,
      if (mlItemId != null) 'ml_item_id': mlItemId,
    });
    final data = res.data as Map<String, dynamic>?;
    if (data == null) {
      throw StateError('Sin datos de comparación.');
    }
    final competitors = (data['competitors'] as List<dynamic>? ?? [])
        .map((e) => CompetitorPrice.fromJson(e as Map<String, dynamic>))
        .toList();
    return PriceComparison(
      title: (data['title'] as String?) ?? '',
      yourPrice: (data['your_price'] as num?)?.toDouble() ?? 0,
      categoryId: data['category_id'] as String?,
      yourSold: (data['your_sold'] as num?)?.toInt() ?? 0,
      yourStock: (data['your_stock'] as num?)?.toInt() ?? 0,
      competitors: competitors,
    );
  }
}
