import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/widgets/app_widgets.dart';

/// Depósitos. Manage warehouses: which one is the default (dispatch) warehouse
/// ML discounts from, and whether each one counts toward the published stock.
class WarehousesScreen extends ConsumerStatefulWidget {
  const WarehousesScreen({super.key});

  @override
  ConsumerState<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends ConsumerState<WarehousesScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    // Make sure the "Depósito principal" exists so the screen is never empty.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(inventoryRepositoryProvider).ensureDefaultWarehouse();
      } catch (_) {
        // Best-effort; the list still works if it already exists.
      }
    });
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _WarehouseFormSheet(),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Depósito creado')));
    }
  }

  Future<void> _setDefault(Warehouse w) async {
    if (w.isDefault) return;
    try {
      await ref.read(inventoryRepositoryProvider).setDefaultWarehouse(w.id);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo cambiar el principal. $e');
    }
  }

  Future<void> _toggleSellable(Warehouse w) async {
    try {
      await ref.read(inventoryRepositoryProvider).setSellable(w.id, !w.isSellable);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo actualizar. $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final warehousesAsync = ref.watch(warehousesStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Depósitos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: SafeArea(
        child: warehousesAsync.when(
          loading: () => const Loading(),
          error: (e, _) => InlineError(
            message: '$e',
            onRetry: () => ref.invalidate(warehousesStreamProvider),
          ),
          data: (warehouses) {
            if (warehouses.isEmpty) {
              return const EmptyState(
                icon: Icons.warehouse_outlined,
                title: 'Sin depósitos',
                message: 'Creá tu primer depósito con el botón "Nuevo".',
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 96),
              children: [
                const Text(
                  'El depósito principal es del que ML descuenta al despachar. '
                  'Los depósitos "vendibles" suman al stock publicado en ML.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
                const SizedBox(height: 14),
                for (final w in warehouses) ...[
                  _WarehouseCard(
                    warehouse: w,
                    onSetDefault: () => _setDefault(w),
                    onToggleSellable: () => _toggleSellable(w),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WarehouseCard extends StatelessWidget {
  const _WarehouseCard({
    required this.warehouse,
    required this.onSetDefault,
    required this.onToggleSellable,
  });

  final Warehouse warehouse;
  final VoidCallback onSetDefault;
  final VoidCallback onToggleSellable;

  @override
  Widget build(BuildContext context) {
    final w = warehouse;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                w.isDefault ? Icons.local_shipping_rounded : Icons.warehouse_outlined,
                color: w.isDefault ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w.name,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    Text(w.code,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (w.isDefault)
                TagChip('Principal · despacho',
                    color: AppColors.primary,
                    background: AppColors.primarySoft,
                    bold: true),
              if (w.isDefault) const SizedBox(width: 6),
              TagChip(w.isSellable ? 'Vendible' : 'No vendible'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (!w.isDefault)
                TextButton.icon(
                  onPressed: onSetDefault,
                  icon: const Icon(Icons.local_shipping_outlined, size: 16),
                  style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                  label: const Text('Hacer principal'),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: onToggleSellable,
                icon: Icon(
                  w.isSellable
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 16,
                ),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                label: Text(w.isSellable ? 'Marcar no vendible' : 'Marcar vendible'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet to create a warehouse (name + sellable; code derived from name).
class _WarehouseFormSheet extends ConsumerStatefulWidget {
  const _WarehouseFormSheet();

  @override
  ConsumerState<_WarehouseFormSheet> createState() => _WarehouseFormSheetState();
}

class _WarehouseFormSheetState extends ConsumerState<_WarehouseFormSheet> {
  final _name = TextEditingController();
  bool _sellable = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _codeFrom(String name) {
    final code = name
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return code.isEmpty ? 'DEP-${DateTime.now().millisecondsSinceEpoch % 100000}' : code;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';
    try {
      await ref.read(inventoryRepositoryProvider).createWarehouse(
            Warehouse(
              id: '',
              profileId: userId,
              code: _codeFrom(name),
              name: name,
              isSellable: _sellable,
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'No se pudo crear. ${e.toString().split('\n').first}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Nuevo depósito',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Ej. Depósito Centro',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text('Cuenta para el stock publicado en ML',
                        style: TextStyle(fontSize: 13, color: AppColors.textBody)),
                  ),
                  Switch(
                    value: _sellable,
                    onChanged: (v) => setState(() => _sellable = v),
                    activeColor: AppColors.onPrimary,
                    activeTrackColor: AppColors.primary,
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: AppColors.onPrimary),
                      )
                    : const Text('Crear depósito'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
