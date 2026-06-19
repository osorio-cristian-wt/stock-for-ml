import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config/env.dart';
import 'src/theme/app_colors.dart';
import 'src/theme/app_theme.dart';

Future<void> main() async {
  // Run inside a guarded zone so any uncaught async error is logged instead of
  // silently leaving the app on a black screen.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = FlutterError.presentError;

    try {
      await Supabase.initialize(
        // resolvedSupabaseUrl maps localhost → 10.0.2.2 on the Android emulator.
        url: Env.resolvedSupabaseUrl,
        // Supabase's new key format ("sb_publishable_..."). Replaces the legacy
        // anon JWT key.
        publishableKey: Env.supabaseAnonKey,
      );
    } catch (e, st) {
      // A failed init must never leave a blank window — show what went wrong.
      debugPrint('Supabase.initialize failed: $e\n$st');
      runApp(_StartupErrorApp(message: '$e'));
      return;
    }

    runApp(const ProviderScope(child: StockForMlApp()));
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

/// Shown only when the app can't initialize (e.g. bad Supabase config). Replaces
/// the dreaded silent black screen with an actionable message.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textFaint),
                const SizedBox(height: 16),
                const Text(
                  'No se pudo iniciar la app',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Revisá la conexión con Supabase.\n$message',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
