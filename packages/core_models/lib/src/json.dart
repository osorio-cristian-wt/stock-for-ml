/// Small JSON parsing helpers shared by the models. Supabase returns numbers
/// as `int` or `double` and timestamps as ISO strings, so we normalize here.
library;

num? asNum(Object? v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

double asDouble(Object? v, [double fallback = 0]) =>
    asNum(v)?.toDouble() ?? fallback;

double? asDoubleOrNull(Object? v) => asNum(v)?.toDouble();

int asInt(Object? v, [int fallback = 0]) => asNum(v)?.toInt() ?? fallback;

int? asIntOrNull(Object? v) => asNum(v)?.toInt();

bool asBool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  return fallback;
}

DateTime? asDateTime(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
