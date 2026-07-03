import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ganancia real de una venta (fila de `v_sale_profit`): bruto − comisión −
/// envío − costo de lo vendido según la política de costeo del perfil.
class SaleProfit {
  const SaleProfit({
    required this.saleId,
    required this.gross,
    required this.costArs,
    required this.netProfit,
  });

  final String saleId;
  final double gross;
  final double? costArs;
  final double netProfit;

  factory SaleProfit.fromJson(Map<String, dynamic> j) => SaleProfit(
        saleId: j['sale_id'] as String,
        gross: (j['gross'] as num?)?.toDouble() ?? 0,
        costArs: (j['cost_ars'] as num?)?.toDouble(),
        netProfit: (j['net_profit'] as num?)?.toDouble() ?? 0,
      );
}

/// Política de valuación del costo de lo vendido (espejo del enum SQL).
enum CostPolicy {
  fifo('fifo', 'FIFO', 'Primera compra que entró, primera que sale'),
  avg('avg', 'Promedio ponderado', 'Promedio de todas las compras cerradas'),
  last('last', 'Última compra', 'El costo de la compra más reciente'),
  manual('manual', 'Manual', 'El costo cargado a mano en cada producto');

  const CostPolicy(this.wire, this.label, this.description);

  final String wire;
  final String label;
  final String description;

  static CostPolicy fromWire(String? w) =>
      values.firstWhere((p) => p.wire == w, orElse: () => CostPolicy.fifo);
}

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

  /// Ganancia por venta desde `v_sale_profit` (últimas [limit]).
  Future<List<SaleProfit>> saleProfits({int limit = 300}) async {
    final rows = await _client
        .from('v_sale_profit')
        .select('sale_id, gross, cost_ars, net_profit')
        .order('sold_at', ascending: false)
        .limit(limit);
    return rows.map<SaleProfit>((r) => SaleProfit.fromJson(r)).toList();
  }

  /// Política de costeo del perfil (app_settings.cost_policy; FIFO default).
  Future<CostPolicy> costPolicy() async {
    final row = await _client
        .from('app_settings')
        .select('cost_policy')
        .maybeSingle();
    return CostPolicy.fromWire(row?['cost_policy'] as String?);
  }

  Future<void> setCostPolicy(CostPolicy policy, String profileId) async {
    await _client.from('app_settings').upsert({
      'profile_id': profileId,
      'cost_policy': policy.wire,
    });
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
