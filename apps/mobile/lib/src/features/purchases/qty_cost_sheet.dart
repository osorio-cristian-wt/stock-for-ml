import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';

/// Quantity + unit-price editor shared by the purchase AND local-sale flows
/// (search sheet, line editing and the continuous scanners). The labels adapt
/// via [priceLabel]/[confirmLabel] (costo en compras, precio en ventas).
class QtyCostSheet extends StatefulWidget {
  const QtyCostSheet({
    super.key,
    required this.title,
    required this.initialQty,
    required this.initialCost,
    required this.onConfirm,
    this.confirmLabel = 'Agregar a la compra',
    this.priceLabel = 'Costo unitario',
  });

  final String title;
  final int initialQty;
  final double initialCost;
  final String confirmLabel;
  final String priceLabel;
  final Future<void> Function(int qty, double cost) onConfirm;

  @override
  State<QtyCostSheet> createState() => _QtyCostSheetState();
}

class _QtyCostSheetState extends State<QtyCostSheet> {
  late int _qty = widget.initialQty;
  late final TextEditingController _cost = TextEditingController(
    text: widget.initialCost > 0
        ? widget.initialCost.toString().replaceAll('.', ',')
        : '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _cost.dispose();
    super.dispose();
  }

  double get _costValue =>
      double.tryParse(_cost.text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await widget.onConfirm(_qty, _costValue);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar. $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
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
              const SizedBox(height: 16),
              Text(widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text('Cantidad',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  const Spacer(),
                  _RoundBtn(
                      icon: Icons.remove,
                      onTap: () => setState(() {
                            if (_qty > 1) _qty--;
                          })),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('$_qty',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  _RoundBtn(
                      icon: Icons.add,
                      filled: true,
                      onTap: () => setState(() => _qty++)),
                ],
              ),
              const SizedBox(height: 16),
              Text(widget.priceLabel,
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              TextField(
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(hintText: '8,50'),
              ),
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
                    : Text(widget.confirmLabel),
              ),
            ],
          ),
        ),
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
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: filled ? null : Border.all(color: AppColors.borderStrong),
          ),
          child: Icon(icon,
              size: 20, color: filled ? AppColors.onPrimary : AppColors.textSecondary),
        ),
      ),
    );
  }
}
