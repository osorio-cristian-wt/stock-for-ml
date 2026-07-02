import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads the server-computed profitability view and FX rates.
class EconomicsRepository {
  EconomicsRepository(this._client);

  final SupabaseClient _client;

  Future<List<ProductEconomics>> fetchAll() async {
    final rows = await _client
        .from('v_product_economics')
        .select()
        .order('net_profit', ascending: false);
    return rows.map<ProductEconomics>((r) => ProductEconomics.fromJson(r)).toList();
  }

  /// Latest cached USD→ARS rate from the `fx_rates` table (no network call).
  Future<FxRate?> latestFx({String kind = 'blue'}) async {
    final row = await _client
        .from('fx_rates')
        .select()
        .eq('base_currency', 'USD')
        .eq('quote_currency', 'ARS')
        .eq('kind', kind)
        .order('fetched_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : FxRate.fromJson(row);
  }

  /// Forces a live blue-dollar fetch via the `fx-rates` Edge Function, which
  /// queries dolarapi server-side and caches the result (the app never calls
  /// the FX provider directly). Returns the freshly cached rate.
  Future<FxRate?> refreshFx() async {
    final res = await _client.functions.invoke('fx-rates');
    final data = res.data as Map<String, dynamic>?;
    final row = data?['fx'] as Map<String, dynamic>?;
    return row == null ? null : FxRate.fromJson(row);
  }

  /// Cached rate, transparently refreshed from the live API when it is missing,
  /// still the seed value, or older than [maxAge]. Falls back to whatever is
  /// cached if the live fetch fails (offline, provider down, …) so the UI
  /// always has a value to show.
  Future<FxRate?> currentFx({
    String kind = 'blue',
    Duration maxAge = const Duration(hours: 2),
  }) async {
    final cached = await latestFx(kind: kind);
    final isStale = cached == null ||
        cached.source == 'seed' ||
        cached.fetchedAt == null ||
        DateTime.now().difference(cached.fetchedAt!) > maxAge;
    if (!isStale) return cached;
    try {
      return await refreshFx() ?? cached;
    } catch (_) {
      return cached;
    }
  }
}
