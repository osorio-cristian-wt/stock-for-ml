import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/queries.dart';
import 'data/supabase_providers.dart';
import 'features/auth/login_screen.dart';
import 'features/connect_ml/connect_ml_screen.dart';
import 'features/connect_ml/import_prompt.dart';
import 'features/shell/home_shell.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

/// Root widget. Dark "fintech" theme (Estilo B) with an auth-driven gate:
/// Login → Conectar ML → Home shell. Also listens for the ML OAuth deep-link
/// return (`stockforml://auth-callback`) to finish the connection hands-free.
class StockForMlApp extends ConsumerStatefulWidget {
  const StockForMlApp({super.key});

  @override
  ConsumerState<StockForMlApp> createState() => _StockForMlAppState();
}

class _StockForMlAppState extends ConsumerState<StockForMlApp> {
  final _navKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  String? _lastHandled;

  @override
  void initState() {
    super.initState();
    _sub = _appLinks.uriLinkStream.listen(_handleLink);
    // Cold start: the app may have been launched by the deep link.
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleLink(uri);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _handleLink(Uri uri) {
    if (uri.scheme != 'stockforml') return;
    final key = uri.toString();
    if (key == _lastHandled) return;
    _lastHandled = key;

    final status = uri.queryParameters['status'];
    if (status == 'success') {
      // Re-evaluate the gate and pop any pushed "Conectar ML" screen.
      ref.read(mlSetupDismissedProvider.notifier).state = false;
      ref.invalidate(mlAccountProvider);
      _navKey.currentState?.popUntil((r) => r.isFirst);
      _messengerKey.currentState
        ?..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('✓ Cuenta de MercadoLibre conectada'),
        ));
      // First ML login: take the user straight into importing publications.
      final ctx = _navKey.currentState?.context;
      if (ctx != null && ctx.mounted) {
        offerInitialImport(ctx, ref);
      }
    } else if (status == 'error') {
      final message = uri.queryParameters['message'] ?? 'No se pudo conectar.';
      _messengerKey.currentState
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Error de conexión: $message')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stock for ML',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      navigatorKey: _navKey,
      scaffoldMessengerKey: _messengerKey,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);

    return auth.when(
      loading: () => const _Splash(),
      error: (_, __) => const LoginScreen(),
      data: (_) {
        final session = ref.watch(supabaseClientProvider).auth.currentSession;
        if (session == null) return const LoginScreen();
        return const _PostLoginGate();
      },
    );
  }
}

/// Once signed in, route to "Conectar ML" until an account is linked (or the
/// user chooses "Más tarde"). Backend errors never block entry to the app.
class _PostLoginGate extends ConsumerWidget {
  const _PostLoginGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(mlSetupDismissedProvider);
    if (dismissed) return const HomeShell();

    final account = ref.watch(mlAccountProvider);
    return account.when(
      loading: () => const _Splash(),
      error: (_, __) => const HomeShell(),
      data: (acc) => acc != null ? const HomeShell() : const ConnectMlScreen(),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.6),
      ),
    );
  }
}
