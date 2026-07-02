/// Locale-aware-ish formatting for the AR market without pulling in `intl`:
/// ARS uses '.' thousands separators and no decimals; USD uses ',' decimals.
abstract final class Fmt {
  /// "148000" -> "148.000".
  static String _thousands(String digits) {
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  /// ARS, no decimals: 148000 -> "$148.000". Negatives -> "-$3.000".
  static String ars(num value) {
    final rounded = value.round();
    final sign = rounded < 0 ? '-' : '';
    return '$sign\$${_thousands(rounded.abs().toString())}';
  }

  /// Signed ARS for deltas: 23600 -> "+$23.600", -3000 -> "-$3.000".
  static String arsSigned(num value) {
    final sign = value < 0 ? '-' : '+';
    return '$sign\$${_thousands(value.abs().round().toString())}';
  }

  /// USD with 2 decimals and comma: 8.5 -> "USD 8,50".
  static String usd(num value) {
    final fixed = value.toStringAsFixed(2).replaceAll('.', ',');
    final parts = fixed.split(',');
    return 'USD ${_thousands(parts[0])},${parts[1]}';
  }

  /// Percentage, rounded: 47.3 -> "47%". Null -> "—".
  static String pct(num? value) => value == null ? '—' : '${value.round()}%';

  /// Whole quantity with the "u." unit suffix.
  static String units(int qty) => '$qty u.';

  /// Relative time in Spanish: "hace 8 min", "hace 2 h", "ayer".
  static String ago(DateTime? when) {
    if (when == null) return '';
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'recién';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    if (d.inDays == 1) return 'ayer';
    if (d.inDays < 7) return 'hace ${d.inDays} d';
    return '${when.day.toString().padLeft(2, '0')}/'
        '${when.month.toString().padLeft(2, '0')}';
  }

  /// "12/03" day/month for history rows.
  static String shortDate(DateTime? when) {
    if (when == null) return '—';
    final l = when.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}';
  }

  /// "14:20" clock for sale rows.
  static String clock(DateTime? when) {
    if (when == null) return '';
    final l = when.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }
}
