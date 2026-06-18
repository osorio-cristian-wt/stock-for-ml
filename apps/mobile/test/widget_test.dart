import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_for_ml/src/app.dart';

void main() {
  testWidgets('app renders the status placeholder', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: StockForMlApp()));
    await tester.pumpAndSettle();

    expect(find.text('Backend conectado'), findsOneWidget);
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
  });
}
