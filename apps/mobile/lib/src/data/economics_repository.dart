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
}
