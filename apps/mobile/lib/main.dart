import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    // resolvedSupabaseUrl maps localhost → 10.0.2.2 on the Android emulator.
    url: Env.resolvedSupabaseUrl,
    // Supabase's new key format ("sb_publishable_..."). Replaces the legacy
    // anon JWT key.
    publishableKey: Env.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: StockForMlApp()));
}
