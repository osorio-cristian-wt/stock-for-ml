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

  /// Edición desde el lápiz del picker (nombre y datos fiscales/contacto).
  Future<Customer> update(Customer c) async {
    final row = await _client
        .from('customers')
        .update({
          'name': c.name,
          'legal_name': c.legalName,
          'tax_id': c.taxId,
          'phone': c.phone,
          'email': c.email,
        })
        .eq('id', c.id)
        .select()
        .single();
    return Customer.fromJson(row);
  }
}
