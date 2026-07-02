import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'alerts_repository.dart';
import 'catalog_repository.dart';
import 'connection_repository.dart';
import 'economics_repository.dart';
import 'inventory_repository.dart';
import 'price_comparison_repository.dart';
import 'products_repository.dart';
import 'purchases_repository.dart';
import 'sales_repository.dart';

/// The shared Supabase client (initialized in main()).
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Current auth session, reactive to sign-in/out.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(supabaseClientProvider).auth.currentUser;
});

final productsRepositoryProvider = Provider<ProductsRepository>((ref) {
  return ProductsRepository(ref.watch(supabaseClientProvider));
});

final economicsRepositoryProvider = Provider<EconomicsRepository>((ref) {
  return EconomicsRepository(ref.watch(supabaseClientProvider));
});

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(ref.watch(supabaseClientProvider));
});

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(ref.watch(supabaseClientProvider));
});

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepository(ref.watch(supabaseClientProvider));
});

final alertsRepositoryProvider = Provider<AlertsRepository>((ref) {
  return AlertsRepository(ref.watch(supabaseClientProvider));
});

final connectionRepositoryProvider = Provider<ConnectionRepository>((ref) {
  return ConnectionRepository(ref.watch(supabaseClientProvider));
});

final priceComparisonRepositoryProvider =
    Provider<PriceComparisonRepository>((ref) {
  return PriceComparisonRepository(ref.watch(supabaseClientProvider));
});

final purchasesRepositoryProvider = Provider<PurchasesRepository>((ref) {
  return PurchasesRepository(ref.watch(supabaseClientProvider));
});

final suppliersRepositoryProvider = Provider<SuppliersRepository>((ref) {
  return SuppliersRepository(ref.watch(supabaseClientProvider));
});
