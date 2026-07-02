import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads and acknowledges in-app alerts (low/out of stock, new orders, price).
class AlertsRepository {
  AlertsRepository(this._client);

  final SupabaseClient _client;

  Future<List<AppAlert>> recent({int limit = 50}) async {
    final rows = await _client
        .from('alerts')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map<AppAlert>((r) => AppAlert.fromJson(r)).toList();
  }

  Future<int> unreadCount() async {
    final rows = await _client.from('alerts').select('id').eq('is_read', false);
    return rows.length;
  }

  Future<void> markAllRead() async {
    await _client.from('alerts').update({'is_read': true}).eq('is_read', false);
  }

  Future<void> markRead(String id) async {
    await _client.from('alerts').update({'is_read': true}).eq('id', id);
  }
}
