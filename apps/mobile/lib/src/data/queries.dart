import 'package:core_models/core_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_repository.dart';
import 'supabase_providers.dart';

/// Live products (realtime stream → drives stock badges instantly).
final productsStreamProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(productsRepositoryProvider).watchAll();
});

/// Server-computed profitability rows (one per published listing).
final economicsProvider = FutureProvider<List<ProductEconomics>>((ref) {
  return ref.watch(economicsRepositoryProvider).fetchAll();
});

/// Economics indexed by `productId` for quick lookups in lists/detail.
final economicsByProductProvider =
    Provider<Map<String, ProductEconomics>>((ref) {
  final rows = ref.watch(economicsProvider).valueOrNull ?? const [];
  return {
    for (final e in rows)
      if (e.productId != null) e.productId!: e,
  };
});

/// Current USD→ARS FX rate (blue dollar by default). Reads the Supabase cache
/// and refreshes it from the live API (via the `fx-rates` Edge Function) when
/// the cached value is missing, seeded or stale.
final fxProvider = FutureProvider<FxRate?>((ref) {
  return ref.watch(economicsRepositoryProvider).currentFx();
});

/// Recent sales (newest first).
final salesProvider = FutureProvider<List<Sale>>((ref) {
  return ref.watch(salesRepositoryProvider).recent();
});

/// Recent alerts (newest first).
final alertsProvider = FutureProvider<List<AppAlert>>((ref) {
  return ref.watch(alertsRepositoryProvider).recent();
});

/// The user's internal product categories (their taxonomy) — drives the
/// category filter in the list and the picker/AI suggestion in the form.
final categoriesProvider = FutureProvider<List<ProductCategory>>((ref) {
  return ref.watch(inventoryRepositoryProvider).categories();
});

/// Live list of warehouses (default/dispatch first, then by name).
final warehousesStreamProvider = StreamProvider<List<Warehouse>>((ref) {
  return ref.watch(inventoryRepositoryProvider).watchWarehouses();
});

/// Per-(product, warehouse) stock buckets for a product, realtime.
final stockByWarehouseProvider =
    StreamProvider.family<List<ProductStock>, String>((ref, productId) {
  return ref.watch(inventoryRepositoryProvider).watchStockFor(productId);
});

/// Stock rows inside one warehouse, realtime (per-warehouse view).
final stockInWarehouseProvider =
    StreamProvider.family<List<ProductStock>, String>((ref, warehouseId) {
  return ref
      .watch(inventoryRepositoryProvider)
      .watchStockInWarehouse(warehouseId);
});

/// Live movement ledger of one warehouse (newest first) — its history tab.
final warehouseMovementsProvider =
    StreamProvider.family<List<StockMovement>, String>((ref, warehouseId) {
  return ref
      .watch(inventoryRepositoryProvider)
      .watchMovementsInWarehouse(warehouseId);
});

/// Every stock row of the user, realtime — feeds the per-warehouse totals.
final allStockStreamProvider = StreamProvider<List<ProductStock>>((ref) {
  return ref.watch(inventoryRepositoryProvider).watchAllStock();
});

/// Totals per warehouse for the Depósitos list: how many products live there
/// and how many units are available (on_hand − reserved).
class WarehouseTotals {
  const WarehouseTotals({this.products = 0, this.available = 0});

  final int products;
  final int available;
}

final warehouseTotalsProvider = Provider<Map<String, WarehouseTotals>>((ref) {
  final rows =
      ref.watch(allStockStreamProvider).valueOrNull ?? const <ProductStock>[];
  final totals = <String, ({int products, int available})>{};
  for (final s in rows) {
    final hasAny = s.onHand != 0 || s.reserved != 0 || s.incoming != 0;
    final t = totals[s.warehouseId] ?? (products: 0, available: 0);
    totals[s.warehouseId] = (
      products: t.products + (hasAny ? 1 : 0),
      available: t.available + s.available,
    );
  }
  return {
    for (final e in totals.entries)
      e.key: WarehouseTotals(
        products: e.value.products,
        available: e.value.available,
      ),
  };
});

/// Live list of purchases (newest first).
final purchasesStreamProvider = StreamProvider<List<Purchase>>((ref) {
  return ref.watch(purchasesRepositoryProvider).watchAll();
});

/// Live lines of a single purchase (drives the edit screen).
final purchaseItemsProvider =
    StreamProvider.family<List<PurchaseItem>, String>((ref, purchaseId) {
  return ref.watch(purchasesRepositoryProvider).watchItems(purchaseId);
});

/// The user's suppliers (for the purchase header picker).
final suppliersProvider = FutureProvider<List<Supplier>>((ref) {
  return ref.watch(suppliersRepositoryProvider).all();
});

/// A single product's history: purchases, adjustments, transfers and ML sales,
/// merged into one newest-first timeline. ML-origin ledger entries are omitted
/// because the sale itself already represents them.
enum HistoryKind { sale, purchase, adjustment, transfer, returned, initial, other }

class ProductHistoryEntry {
  const ProductHistoryEntry({
    required this.date,
    required this.kind,
    required this.label,
    required this.signedQty,
    this.reference,
  });

  final DateTime? date;
  final HistoryKind kind;
  final String label;
  final int signedQty; // + into stock, − out of stock
  final String? reference;
}

/// Live stock ledger for one product; feeding the history from the realtime
/// stream keeps the timeline current when a purchase closes or stock moves
/// while the detail screen is open.
final productMovementsProvider =
    StreamProvider.family<List<StockMovement>, String>((ref, productId) {
  return ref.watch(productsRepositoryProvider).watchMovementsFor(productId);
});

final productHistoryProvider =
    FutureProvider.family<List<ProductHistoryEntry>, String>((ref, productId) async {
  final movements = await ref.watch(productMovementsProvider(productId).future);
  final sales = (await ref.watch(salesRepositoryProvider).recent(limit: 200))
      .where((s) => s.productId == productId)
      .toList();

  final entries = <ProductHistoryEntry>[
    for (final s in sales)
      ProductHistoryEntry(
        date: s.soldAt,
        kind: HistoryKind.sale,
        label: 'Venta ML',
        signedQty: -s.quantity,
        reference: s.mlOrderId,
      ),
  ];

  for (final m in movements) {
    if (m.origin == StockOrigin.ml) continue; // represented by the sale itself
    final (kind, label) = switch (m.reason) {
      StockReason.purchase ||
      StockReason.purchaseReceived =>
        (HistoryKind.purchase, 'Compra'),
      // User-origin sale = sold outside ML (the sheet's "Venta" reason).
      StockReason.sale => (HistoryKind.sale, 'Venta manual'),
      StockReason.adjustment => (HistoryKind.adjustment, 'Ajuste'),
      StockReason.transfer => (HistoryKind.transfer, 'Transferencia'),
      StockReason.returned => (HistoryKind.returned, 'Devolución'),
      StockReason.initialSync => (HistoryKind.initial, 'Stock inicial'),
      StockReason.loss => (HistoryKind.other, 'Pérdida'),
      _ => (HistoryKind.other, 'Movimiento'),
    };
    entries.add(ProductHistoryEntry(
      date: m.createdAt,
      kind: kind,
      label: label,
      signedQty: m.delta,
      reference: m.reference,
    ));
  }

  entries.sort((a, b) =>
      (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970)));
  return entries;
});

/// ML-side stock per variation of a listing (RF-07). Empty for simple
/// listings; the detail screen shows the breakdown when there are rows.
final listingVariationsProvider =
    StreamProvider.family<List<ListingVariation>, String>((ref, listingId) {
  return ref
      .watch(connectionRepositoryProvider)
      .watchListingVariations(listingId);
});

/// One row of the own-products comparison (RF-19): profitability, margin,
/// markup and rotation (units sold in the last 30 days).
class ProductComparisonRow {
  const ProductComparisonRow({
    required this.productId,
    required this.title,
    this.imageUrl,
    this.marginPct,
    this.markupPct,
    this.netProfit,
    required this.soldUnits30d,
    required this.currentStock,
  });

  final String productId;
  final String title;
  final String? imageUrl;
  final double? marginPct;
  final double? markupPct;
  final double? netProfit;
  final int soldUnits30d;
  final int currentStock;

  bool get published => marginPct != null || netProfit != null;
}

/// RF-19 — compares own products side by side. Economics come from the
/// server view (published products only); rotation counts non-cancelled ML
/// sale units over the last 30 days.
final productComparisonProvider =
    FutureProvider<List<ProductComparisonRow>>((ref) async {
  final products = await ref.watch(productsStreamProvider.future);
  final economics = ref.watch(economicsByProductProvider);
  final sales = await ref.watch(salesRepositoryProvider).recent(limit: 500);

  final cutoff = DateTime.now().subtract(const Duration(days: 30));
  final sold = <String, int>{};
  for (final s in sales) {
    final pid = s.productId;
    if (pid == null || s.status == 'cancelled') continue;
    final at = s.soldAt;
    if (at == null || at.isBefore(cutoff)) continue;
    sold[pid] = (sold[pid] ?? 0) + s.quantity;
  }

  return [
    for (final p in products)
      ProductComparisonRow(
        productId: p.id,
        title: p.title,
        imageUrl: p.imageUrl,
        marginPct: economics[p.id]?.marginPct,
        markupPct: economics[p.id]?.markupPct,
        netProfit: economics[p.id]?.netProfit,
        soldUnits30d: sold[p.id] ?? 0,
        currentStock: p.currentStock,
      ),
  ];
});

/// Unread alert count for the header bell badge.
final unreadAlertsCountProvider = Provider<int>((ref) {
  final alerts = ref.watch(alertsProvider).valueOrNull ?? const [];
  return alerts.where((a) => !a.isRead).length;
});

/// Whether a MercadoLibre account is linked (null = unknown/loading/error).
final mlAccountProvider = FutureProvider<MlAccount?>((ref) {
  return ref.watch(connectionRepositoryProvider).currentAccount();
});

/// Lets the user dismiss the "connect ML" step and enter the app anyway.
final mlSetupDismissedProvider = StateProvider<bool>((ref) => false);

/// Aggregated Inicio dashboard. A point-in-time snapshot computed from
/// products, profitability, sales and FX.
class DashboardData {
  const DashboardData({
    required this.todaySalesGross,
    required this.todaySalesCount,
    required this.todayNetProfit,
    required this.avgMarginPct,
    required this.listingsCount,
    required this.lowStock,
    required this.fx,
  });

  final double todaySalesGross;
  final int todaySalesCount;
  final double todayNetProfit;
  final double? avgMarginPct;
  final int listingsCount;

  /// Products at/under their low-stock threshold (worst first).
  final List<Product> lowStock;
  final FxRate? fx;

  int get lowStockCount => lowStock.length;
}

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  final productsRepo = ref.watch(productsRepositoryProvider);
  final economicsRepo = ref.watch(economicsRepositoryProvider);
  final salesRepo = ref.watch(salesRepositoryProvider);

  final products = await productsRepo.fetchAll();
  final economics = await economicsRepo.fetchAll();
  final sales = await salesRepo.recent(limit: 120);
  final fx = await economicsRepo.currentFx();

  final now = DateTime.now();
  bool isToday(DateTime? d) =>
      d != null &&
      d.toLocal().year == now.year &&
      d.toLocal().month == now.month &&
      d.toLocal().day == now.day;

  final today = sales.where((s) => isToday(s.soldAt)).toList();
  final todayGross = today.fold<double>(0, (sum, s) => sum + s.gross);
  final todayNet = today.fold<double>(
    0,
    (sum, s) => sum + (s.netAmount ?? (s.gross - s.saleFee - s.shippingCost)),
  );

  final margins = economics
      .map((e) => e.marginPct)
      .whereType<double>()
      .toList();
  final avgMargin = margins.isEmpty
      ? null
      : margins.reduce((a, b) => a + b) / margins.length;

  final lowStock = products.where((p) => p.isLowStock).toList()
    ..sort((a, b) => a.currentStock.compareTo(b.currentStock));

  return DashboardData(
    todaySalesGross: todayGross,
    todaySalesCount: today.length,
    todayNetProfit: todayNet,
    avgMarginPct: avgMargin,
    listingsCount: economics.length,
    lowStock: lowStock,
    fx: fx,
  );
});
