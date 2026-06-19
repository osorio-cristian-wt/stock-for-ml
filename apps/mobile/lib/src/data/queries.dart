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

/// Latest USD→ARS FX rate (blue dollar by default).
final fxProvider = FutureProvider<FxRate?>((ref) {
  return ref.watch(economicsRepositoryProvider).latestFx();
});

/// Recent sales (newest first).
final salesProvider = FutureProvider<List<Sale>>((ref) {
  return ref.watch(salesRepositoryProvider).recent();
});

/// Recent alerts (newest first).
final alertsProvider = FutureProvider<List<AppAlert>>((ref) {
  return ref.watch(alertsRepositoryProvider).recent();
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
  final fx = await economicsRepo.latestFx();

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
