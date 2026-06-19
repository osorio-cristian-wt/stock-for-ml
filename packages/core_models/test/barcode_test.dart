import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  group('Barcode', () {
    test('valid EAN-13 (real sample 6937541239382, China)', () {
      expect(Barcode.isValidGtin('6937541239382'), isTrue);
      expect(Barcode.gs1Prefix('6937541239382'), '693');
    });

    test('rejects a bad checksum', () {
      expect(Barcode.isValidGtin('6937541239383'), isFalse);
    });

    test('valid UPC-A normalizes to EAN-13', () {
      expect(Barcode.isValidGtin('036000291452'), isTrue);
      expect(Barcode.normalizeGtin('036000291452'), '0036000291452');
    });

    test('alphanumeric SKU is not a GTIN', () {
      expect(Barcode.isValidGtin('TPSLI20281'), isFalse);
      expect(Barcode.classify('TPSLI20281'), BarcodeKind.sku);
      expect(Barcode.gs1Prefix('TPSLI20281'), '');
    });

    test('ScannedCode.classify routes the two real samples', () {
      final gtin = ScannedCode.classify('6937541239382');
      expect(gtin.kind, BarcodeKind.gtin);
      expect(gtin.isGtin, isTrue);
      expect(gtin.gtin, '6937541239382');

      final sku = ScannedCode.classify('TPSLI20281');
      expect(sku.kind, BarcodeKind.sku);
      expect(sku.isGtin, isFalse);
      expect(sku.gtin, isNull);
    });
  });
}
