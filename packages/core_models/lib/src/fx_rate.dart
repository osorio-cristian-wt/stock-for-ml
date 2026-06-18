import 'package:meta/meta.dart';

import 'json.dart';

@immutable
class FxRate {
  const FxRate({
    required this.baseCurrency,
    required this.quoteCurrency,
    required this.kind,
    required this.rate,
    this.buy,
    this.sell,
    this.source,
    this.fetchedAt,
  });

  final String baseCurrency;
  final String quoteCurrency;
  final String kind;
  final double rate;
  final double? buy;
  final double? sell;
  final String? source;
  final DateTime? fetchedAt;

  factory FxRate.fromJson(Map<String, dynamic> json) => FxRate(
        baseCurrency: (json['base_currency'] as String?) ?? 'USD',
        quoteCurrency: (json['quote_currency'] as String?) ?? 'ARS',
        kind: (json['kind'] as String?) ?? 'blue',
        rate: asDouble(json['rate']),
        buy: asDoubleOrNull(json['buy']),
        sell: asDoubleOrNull(json['sell']),
        source: json['source'] as String?,
        fetchedAt: asDateTime(json['fetched_at']),
      );
}
