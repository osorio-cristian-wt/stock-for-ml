import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Customers (clientes) for local sales. RLS scopes rows to the user who
/// created them.
class CustomersRepository {
  CustomersRepository(this._client);

  final SupabaseClient _client;

  Future<List<Customer>> all() async {
    final rows = await _client.from('customers').select().order('name');
    return rows.map<Customer>((r) => Customer.fromJson(r)).toList();
  }

  Future<Customer> create(Customer c) async {
    final row =
        await _client.from('customers').insert(c.toInsert()).select().single();
    return Customer.fromJson(row);
  }
}
