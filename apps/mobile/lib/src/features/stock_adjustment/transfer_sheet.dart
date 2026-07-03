import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/errors.dart';

/// Transfer stock between two warehouses (internal control). Writes two paired
/// on_hand movements via the `transfer_stock` RPC.
class TransferSheet extends ConsumerStatefulWidget {
  const TransferSheet({super.key, required this.product, this.fromWarehouseId});

  final Product product;

  /// Pre-selected origin (e.g. when launched from a warehouse's own view).
  final String? fromWarehouseId;

  static Future<void> show(
    BuildContext context, {
    required Product product,
    String? fromWarehouseId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          TransferSheet(product: product, fromWarehouseId: fromWarehouseId),
    );
  }

  @override
  ConsumerState<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<TransferSheet> {
  String? _fromId;
  String? _toId;
  int _qty = 1;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fromId = widget.fromWarehouseId;
  }

  Future<void> _confirm() async {
    if (_fromId == null || _toId == null) {
      setState(() => _error = 'Elegí depósito de origen y destino.');
      return;
    }
    if (_fromId == _toId) {
      setState(() => _error = 'Origen y destino deben ser distintos.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(inventoryRepositoryProvider).transferStock(
            productId: widget.product.id,
            fromWarehouseId: _fromId!,
            toWarehouseId: _toId!,
            qty: _qty,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transferencia registrada')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'No se pudo transferir. ${AppErrors.friendly(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final warehouses =
        ref.watch(warehousesStreamProvider).valueOrNull ?? const <Warehouse>[];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
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
              const Text('Transferir entre depósitos',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(widget.product.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 18),
              if (warehouses.length < 2)
                const Text(
                  'Necesitás al menos 2 depósitos para transferir. Creá otro desde '
                  'Ajustes → Depósitos.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                )
              else ...[
                _WarehousePicker(
                  label: 'Desde',
                  warehouses: warehouses,
                  selectedId: _fromId,
                  onChanged: (id) => setState(() => _fromId = id),
                ),
                const SizedBox(height: 12),
                _WarehousePicker(
                  label: 'Hacia',
                  warehouses: warehouses,
                  selectedId: _toId,
                  onChanged: (id) => setState(() => _toId = id),
                ),
                const SizedBox(height: 16),
                const Text('Cantidad',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted)),
                const SizedBox(height: 9),
                _QtyStepper(
                  value: _qty,
                  onMinus: () => setState(() {
                    if (_qty > 1) _qty--;
                  }),
                  onPlus: () => setState(() => _qty++),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _confirm,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: AppColors.onPrimary),
                        )
                      : const Text('Confirmar transferencia'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WarehousePicker extends StatelessWidget {
  const _WarehousePicker({
    required this.label,
    required this.warehouses,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final List<Warehouse> warehouses;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500)),
        ),
        DropdownButtonFormField<String?>(
          value: selectedId,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          icon: const Icon(Icons.expand_more, color: AppColors.textFaint),
          decoration: const InputDecoration(hintText: 'Elegí un depósito'),
          items: [
            for (final w in warehouses)
              DropdownMenuItem<String?>(
                value: w.id,
                child: Text(w.isDefault ? '${w.name} · principal' : w.name),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final int value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceDeep,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _RoundBtn(icon: Icons.remove, onTap: onMinus),
          Text('$value',
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          _RoundBtn(icon: Icons.add, filled: true, onTap: onPlus),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap, this.filled = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: filled ? null : Border.all(color: AppColors.borderStrong),
          ),
          child: Icon(icon,
              size: 22, color: filled ? AppColors.onPrimary : AppColors.textSecondary),
        ),
      ),
    );
  }
}
