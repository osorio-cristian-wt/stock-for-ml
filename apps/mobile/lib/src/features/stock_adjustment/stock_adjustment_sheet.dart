import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';

/// Screen 07 · Ajuste de stock (bottom sheet). Registers a stock movement.
/// Supabase is the source of truth; user-origin movements are pushed to ML by
/// the backend trigger.
class StockAdjustmentSheet extends ConsumerStatefulWidget {
  const StockAdjustmentSheet({super.key, required this.product});

  final Product product;

  static Future<void> show(BuildContext context, {required Product product}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StockAdjustmentSheet(product: product),
    );
  }

  @override
  ConsumerState<StockAdjustmentSheet> createState() => _StockAdjustmentSheetState();
}

class _StockAdjustmentSheetState extends ConsumerState<StockAdjustmentSheet> {
  StockReason _reason = StockReason.purchase;
  int _amount = 1;
  int _adjustSign = 1; // only used when reason == adjustment
  bool _busy = false;
  String? _error;

  static const _reasons = [
    (StockReason.purchase, 'Compra'),
    (StockReason.sale, 'Venta'),
    (StockReason.adjustment, 'Ajuste'),
    (StockReason.returned, 'Devolución'),
  ];

  int get _sign {
    switch (_reason) {
      case StockReason.sale:
        return -1;
      case StockReason.adjustment:
        return _adjustSign;
      default:
        return 1; // purchase, returned
    }
  }

  int get _delta => _amount * _sign;
  int get _newStock => widget.product.currentStock + _delta;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(productsRepositoryProvider).applyStockMovement(
            productId: widget.product.id,
            delta: _delta,
            reason: _reason,
            origin: StockOrigin.user,
          );
      ref.invalidate(dashboardProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Movimiento registrado · sincronizando con ML')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'No se pudo registrar. ${e.toString().split('\n').first}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              const Text('Registrar movimiento',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(
                widget.product.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              const Text(
                'Supabase es la fuente de verdad. El cambio se empuja a ML.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              _ReasonGrid(
                selected: _reason,
                reasons: _reasons,
                onSelect: (r) => setState(() => _reason = r),
              ),
              const SizedBox(height: 18),
              if (_reason == StockReason.adjustment) ...[
                _SignToggle(
                  sign: _adjustSign,
                  onChanged: (s) => setState(() => _adjustSign = s),
                ),
                const SizedBox(height: 14),
              ],
              const Text('Cantidad',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted)),
              const SizedBox(height: 9),
              _Stepper(
                value: _amount,
                signedLabel: _delta >= 0 ? '+$_delta' : '$_delta',
                onMinus: () => setState(() {
                  if (_amount > 1) _amount--;
                }),
                onPlus: () => setState(() => _amount++),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    children: [
                      TextSpan(text: 'Stock: ${widget.product.currentStock} → '),
                      TextSpan(
                        text: '$_newStock u.',
                        style: TextStyle(
                          color: _newStock < 0 ? AppColors.danger : AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_newStock < 0) ...[
                const SizedBox(height: 6),
                const Center(
                  child: Text('El stock no puede quedar negativo.',
                      style: TextStyle(fontSize: 12, color: AppColors.danger)),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(fontSize: 12, color: AppColors.danger)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: (_busy || _newStock < 0 || _delta == 0) ? null : _confirm,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: AppColors.onPrimary),
                      )
                    : const Text('Confirmar movimiento'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonGrid extends StatelessWidget {
  const _ReasonGrid({
    required this.selected,
    required this.reasons,
    required this.onSelect,
  });

  final StockReason selected;
  final List<(StockReason, String)> reasons;
  final ValueChanged<StockReason> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 3.4,
      children: [
        for (final (reason, label) in reasons)
          GestureDetector(
            onTap: () => onSelect(reason),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: reason == selected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: reason == selected ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: reason == selected
                      ? AppColors.onPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SignToggle extends StatelessWidget {
  const _SignToggle({required this.sign, required this.onChanged});

  final int sign;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _seg('Sumar', 1)),
        const SizedBox(width: 9),
        Expanded(child: _seg('Restar', -1)),
      ],
    );
  }

  Widget _seg(String label, int value) {
    final selected = sign == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.signedLabel,
    required this.onMinus,
    required this.onPlus,
  });

  final int value;
  final String signedLabel;
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
          Text(
            signedLabel,
            style: const TextStyle(
                fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
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
          child: Icon(
            icon,
            size: 22,
            color: filled ? AppColors.onPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
