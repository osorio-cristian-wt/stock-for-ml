import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_for_ml/src/features/auth/login_screen.dart';
import 'package:stock_for_ml/src/theme/app_theme.dart';

void main() {
  testWidgets('login screen renders without a live backend', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.dark, home: const LoginScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Stock for ML'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
    expect(find.text('Crear una cuenta nueva'), findsOneWidget);
  });
}
