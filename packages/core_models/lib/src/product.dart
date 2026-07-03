import 'package:meta/meta.dart';

import 'json.dart';

/// An internal catalog product. May or may not be published on MercadoLibre.
@immutable
class Product {
  const Product({
    required this.id,
    required this.profileId,
    required this.title,
    this.sku,
    this.gtin,
    this.categoryId,
    this.brand,
    this.description,
    this.purchaseCost = 0,
    this.purchaseCurrency = 'USD',
    this.purchaseIncludesTaxes = false,
    this.salePrice,
    this.imageUrl,
    this.currentStock = 0,
    this.lowStockThreshold,
    this.isActive = true,
    this.notes,
  });

  final String id;
  final String profileId;
  final String title;
  final String? sku;

  /// Global barcode (EAN/UPC). Distinct from [sku] (internal code).
  final String? gtin;
  final String? categoryId;
  final String? brand;
  final String? description;
  final double purchaseCost;
  final String purchaseCurrency;
  final bool purchaseIncludesTaxes;

  /// Local sale price (ARS). For ML-published products the listing price wins.
  final double? salePrice;
  final String? imageUrl;
  final int currentStock;
  final int? lowStockThreshold;
  final bool isActive;
  final String? notes;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        title: json['title'] as String,
        sku: json['sku'] as String?,
        gtin: json['gtin'] as String?,
        categoryId: json['category_id'] as String?,
        brand: json['brand'] as String?,
        description: json['description'] as String?,
        purchaseCost: asDouble(json['purchase_cost']),
        purchaseCurrency: (json['purchase_currency'] as String?) ?? 'USD',
        purchaseIncludesTaxes: asBool(json['purchase_includes_taxes']),
        salePrice: asDoubleOrNull(json['sale_price']),
        imageUrl: json['image_url'] as String?,
        currentStock: asInt(json['current_stock']),
        lowStockThreshold: asIntOrNull(json['low_stock_threshold']),
        isActive: asBool(json['is_active'], true),
        notes: json['notes'] as String?,
      );

  /// Payload for insert/update (server-managed fields omitted).
  Map<String, dynamic> toInsert() => {
        'profile_id': profileId,
        'title': title,
        if (sku != null) 'sku': sku,
        if (gtin != null) 'gtin': gtin,
        if (categoryId != null) 'category_id': categoryId,
        if (brand != null) 'brand': brand,
        if (description != null) 'description': description,
        'purchase_cost': purchaseCost,
        'purchase_currency': purchaseCurrency,
        'purchase_includes_taxes': purchaseIncludesTaxes,
        'sale_price': salePrice,
        if (imageUrl != null) 'image_url': imageUrl,
        if (lowStockThreshold != null) 'low_stock_threshold': lowStockThreshold,
        'is_active': isActive,
        if (notes != null) 'notes': notes,
      };

  /// En o bajo el umbral. Sin umbral definido, un producto en 0 igual cuenta
  /// como "necesita reposición" (pedido del dueño: en 0 SIEMPRE se muestra).
  bool get isLowStock => currentStock <= (lowStockThreshold ?? 0);

  Product copyWith({
    String? title,
    String? sku,
    String? gtin,
    String? categoryId,
    String? brand,
    double? purchaseCost,
    String? purchaseCurrency,
    double? salePrice,
    int? currentStock,
    int? lowStockThreshold,
    bool? isActive,
  }) =>
      Product(
        id: id,
        profileId: profileId,
        title: title ?? this.title,
        sku: sku ?? this.sku,
        gtin: gtin ?? this.gtin,
        categoryId: categoryId ?? this.categoryId,
        brand: brand ?? this.brand,
        description: description,
        purchaseCost: purchaseCost ?? this.purchaseCost,
        purchaseCurrency: purchaseCurrency ?? this.purchaseCurrency,
        purchaseIncludesTaxes: purchaseIncludesTaxes,
        salePrice: salePrice ?? this.salePrice,
        imageUrl: imageUrl,
        currentStock: currentStock ?? this.currentStock,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
        isActive: isActive ?? this.isActive,
        notes: notes,
      );
}
