import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads sales (orders imported from ML). RLS scopes rows to the user.
class SalesRepository {
  SalesRepository(this._client);

  final SupabaseClient _client;

  /// Most recent sales first (for the Ventas screen and Inicio summary).
  Future<List<Sale>> recent({int limit = 60}) async {
    final rows = await _client
        .from('sales')
        .select()
        .order('sold_at', ascending: false)
        .limit(limit);
    return rows.map<Sale>((r) => Sale.fromJson(r)).toList();
  }
}
