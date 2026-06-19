import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of a barcode/catalog lookup (mirror of the Edge function response).
class ProductEnrichment {
  const ProductEnrichment({
    required this.source,
    this.catalogProductId,
    this.name,
    this.brand,
    this.domainId,
    this.categoryId,
    this.categoryName,
    this.imageUrl,
  });

  /// One of: ml_catalog | ml_domain | llm | none.
  final String source;
  final String? catalogProductId;
  final String? name;
  final String? brand;
  final String? domainId;
  final String? categoryId;
  final String? categoryName;
  final String? imageUrl;

  bool get hasMatch => source != 'none';

  factory ProductEnrichment.fromJson(Map<String, dynamic> j) => ProductEnrichment(
        source: (j['source'] as String?) ?? 'none',
        catalogProductId: j['catalogProductId'] as String?,
        name: j['name'] as String?,
        brand: j['brand'] as String?,
        domainId: j['domainId'] as String?,
        categoryId: j['categoryId'] as String?,
        categoryName: j['categoryName'] as String?,
        imageUrl: j['imageUrl'] as String?,
      );
}

/// Barcode-first enrichment + classification. Primary source is the ML catalog
/// (by GTIN) then ML's category predictor; the LLM is the LAST fallback.
class CatalogRepository {
  CatalogRepository(this._client);

  final SupabaseClient _client;

  /// Enrich a scanned code: GTIN → ML catalog → ML category predictor.
  Future<ProductEnrichment> lookup(ScannedCode code, {String? title}) async {
    final res = await _client.functions.invoke('lookup-product', body: {
      if (code.isGtin) 'gtin': code.gtin,
      if (title != null && title.isNotEmpty) 'title': title,
    });
    final data = res.data as Map<String, dynamic>?;
    final result = data?['result'] as Map<String, dynamic>?;
    return result == null
        ? const ProductEnrichment(source: 'none')
        : ProductEnrichment.fromJson(result);
  }

  /// LLM fallback (last resort): suggests { category_slug, brand, confidence }.
  Future<Map<String, dynamic>?> classify({
    required String title,
    String? description,
    required List<String> categorySlugs,
  }) async {
    final res = await _client.functions.invoke('classify-product', body: {
      'title': title,
      if (description != null) 'description': description,
      'category_slugs': categorySlugs,
    });
    return res.data as Map<String, dynamic>?;
  }
}
