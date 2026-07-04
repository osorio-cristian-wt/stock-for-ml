import 'dart:math';

/// UUID v4 aleatorio (sin dependencia extra): identifica una operación ANTES
/// de mandarla al backend para que el reintento tras un corte de red sea
/// no-op en el RPC (p_sale_id, p_reference de transfer, p_movement_id, y el
/// id de las operaciones encoladas offline).
String newUuid() {
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // versión 4
  b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
