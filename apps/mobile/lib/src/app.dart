import 'package:flutter/material.dart';

import 'config/env.dart';

/// Root widget. UI/views are intentionally minimal for now — the data layer,
/// models and backend are wired first; screens come next.
class StockForMlApp extends StatelessWidget {
  const StockForMlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'stock-for-ml',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFFFE600), // ML yellow
        useMaterial3: true,
      ),
      home: const _StatusScreen(),
    );
  }
}

class _StatusScreen extends StatelessWidget {
  const _StatusScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('stock-for-ml')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                'Backend conectado',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                Env.isLocal
                    ? 'Supabase local · ${Env.supabaseUrl}'
                    : 'Supabase cloud · ${Env.supabaseUrl}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              const Text(
                'Las vistas se definen en la próxima etapa.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
