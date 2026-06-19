import 'package:meta/meta.dart';

/// How a scanned code is treated by the product-loading flow.
///  - [gtin] = global product code (EAN/UPC) → ML catalog enrichment.
///  - [sku]  = alphanumeric internal/model code (e.g. "TPSLI20281") → manual/LLM.
enum BarcodeKind { gtin, sku }

/// Pure GTIN helpers (no Flutter dependency) used by the barcode-first flow.
abstract final class Barcode {
  static final _digits = RegExp(r'^\d+$');

  /// A GTIN is all-digits of length 8/12/13/14 with a valid GS1 mod-10 checksum.
  static bool isValidGtin(String code) {
    if (!_digits.hasMatch(code)) return false;
    if (!const {8, 12, 13, 14}.contains(code.length)) return false;
    final digits = code.split('').map(int.parse).toList();
    final check = digits.removeLast();
    var sum = 0;
    var weight = 3; // rightmost payload digit weighs 3, then alternates
    for (var i = digits.length - 1; i >= 0; i--) {
      sum += digits[i] * weight;
      weight = weight == 3 ? 1 : 3;
    }
    return (10 - (sum % 10)) % 10 == check;
  }

  /// Normalize UPC-A (12 digits) to EAN-13 by left-padding a 0; others pass through.
  static String normalizeGtin(String code) =>
      code.length == 12 ? '0$code' : code;

  /// GS1 prefix (first 3 digits) — e.g. "693" = China. Empty if not a GTIN.
  static String gs1Prefix(String code) =>
      isValidGtin(code) ? normalizeGtin(code).substring(0, 3) : '';

  static BarcodeKind classify(String code) =>
      isValidGtin(code) ? BarcodeKind.gtin : BarcodeKind.sku;
}

/// A scanned code, classified and normalized.
@immutable
class ScannedCode {
  const ScannedCode({required this.raw, required this.kind, this.gtin});

  final String raw;
  final BarcodeKind kind;

  /// Normalized GTIN (EAN-13/8/14) when [kind] == [BarcodeKind.gtin].
  final String? gtin;

  bool get isGtin => kind == BarcodeKind.gtin;

  factory ScannedCode.classify(String raw) {
    final code = raw.trim();
    if (Barcode.isValidGtin(code)) {
      return ScannedCode(
        raw: code,
        kind: BarcodeKind.gtin,
        gtin: Barcode.normalizeGtin(code),
      );
    }
    return ScannedCode(raw: code, kind: BarcodeKind.sku);
  }
}
