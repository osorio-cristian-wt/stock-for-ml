import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../theme/app_colors.dart';
import '../alerts/alerts_screen.dart';
import '../home/home_screen.dart';
import '../movements/movements_screen.dart';
import '../products/products_screen.dart';
import '../purchases/purchases_screen.dart';
import '../sales/sales_screen.dart';
import '../settings/settings_screen.dart';

/// The signed-in app shell: six tabs (Inicio · Productos · Compras · Movim. ·
/// Ventas · Ajustes) over a persistent bottom navigation bar.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  void _goToTab(int i) => setState(() => _index = i);

  void _openAlerts() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AlertsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadAlertsCountProvider);

    final tabs = [
      HomeScreen(onSeeAllLowStock: () => _goToTab(1), onOpenAlerts: _openAlerts),
      const ProductsScreen(),
      const PurchasesScreen(),
      const MovementsScreen(),
      const SalesScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: _BottomNav(
        index: _index,
        unreadAlerts: unread,
        onTap: _goToTab,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.index,
    required this.onTap,
    required this.unreadAlerts,
  });

  final int index;
  final ValueChanged<int> onTap;
  final int unreadAlerts;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Inicio',
                selected: index == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.inventory_2_rounded,
                label: 'Productos',
                selected: index == 1,
                onTap: () => onTap(1),
              ),
              _NavItem(
                icon: Icons.receipt_long_rounded,
                label: 'Compras',
                selected: index == 2,
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: Icons.swap_horiz_rounded,
                label: 'Movim.',
                selected: index == 3,
                onTap: () => onTap(3),
              ),
              _NavItem(
                icon: Icons.bar_chart_rounded,
                label: 'Ventas',
                selected: index == 4,
                onTap: () => onTap(4),
              ),
              _NavItem(
                icon: Icons.settings_rounded,
                label: 'Ajustes',
                selected: index == 5,
                onTap: () => onTap(5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textFaint;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
