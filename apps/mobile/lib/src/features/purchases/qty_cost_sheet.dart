import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../ui/errors.dart';

/// Un depósito elegible dentro del editor de una línea de venta, con su
/// disponible ya descontando lo que otras líneas del carrito le reservan.
class WarehouseChoice {
  const WarehouseChoice({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.available,
  });

  final String id;
  final String name;
  final bool isDefault;
  final int available;

  String get label => isDefault ? '$name · principal' : name;
}

/// Quantity + unit-price editor shared by the purchase AND local-sale flows
/// (search sheet, line editing and the continuous scanners).
///
/// - Los labels se adaptan vía [priceLabel]/[confirmLabel] (costo en compras,
///   precio en ventas).
/// - **Auto-guardado**: si el usuario cierra el sheet (swipe/atrás/tocar
///   afuera) habiendo cambiado algo, se guarda igual que con el botón.
/// - **Tope de stock**: con [warehouses] (ventas) la cantidad no puede superar
///   el disponible del depósito elegido; el stepper se clava en el máximo.
class QtyCostSheet extends StatefulWidget {
  const QtyCostSheet({
    super.key,
    required this.title,
    required this.initialQty,
    required this.initialCost,
    required this.onConfirm,
    this.confirmLabel = 'Agregar a la compra',
    this.priceLabel = 'Costo unitario',
    this.warehouses = const [],
    this.initialWarehouseId,
    this.onConfirmWithWarehouse,
    this.autoSaveNew = false,
    this.requirePrice = false,
  });

  final String title;
  final int initialQty;
  final double initialCost;
  final String confirmLabel;
  final String priceLabel;

  /// RF-43: en ventas locales el precio es obligatorio (> 0) — el producto
  /// puede haberse creado sin precio, pero no se puede vender sin él.
  final bool requirePrice;

  /// Depósitos elegibles para la línea (ventas). Vacío = sin selector ni tope.
  final List<WarehouseChoice> warehouses;
  final String? initialWarehouseId;

  /// Guardado sin depósito (compras). Ignorado si hay [onConfirmWithWarehouse].
  final Future<void> Function(int qty, double cost) onConfirm;

  /// Guardado con el depósito elegido (ventas multi-depósito).
  final Future<void> Function(int qty, double cost, String warehouseId)?
      onConfirmWithWarehouse;

  /// Si la línea es nueva (escaneo/búsqueda), guardar al salir aunque no se
  /// haya tocado nada (el gesto de abrirla ya expresa la intención de sumar).
  final bool autoSaveNew;

  @override
  State<QtyCostSheet> createState() => _QtyCostSheetState();
}

class _QtyCostSheetState extends State<QtyCostSheet> {
  late int _qty = widget.initialQty;
  late String? _warehouseId = widget.initialWarehouseId ??
      (widget.warehouses.isEmpty
          ? null
          : widget.warehouses
              .firstWhere((w) => w.isDefault, orElse: () => widget.warehouses.first)
              .id);
  late final TextEditingController _cost = TextEditingController(
    text: widget.initialCost > 0
        ? widget.initialCost.toString().replaceAll('.', ',')
        : '',
  );
  bool _busy = false;
  bool _canPop = false;

  @override
  void dispose() {
    _cost.dispose();
    super.dispose();
  }

  double get _costValue =>
      double.tryParse(_cost.text.trim().replaceAll(',', '.')) ?? 0;

  WarehouseChoice? get _warehouse {
    for (final w in widget.warehouses) {
      if (w.id == _warehouseId) return w;
    }
    return null;
  }

  /// Tope de unidades: el disponible del depósito elegido (null = sin tope).
  int? get _maxQty => widget.warehouses.isEmpty ? null : (_warehouse?.available ?? 0);

  bool get _changed =>
      _qty != widget.initialQty ||
      _costValue != widget.initialCost ||
      _warehouseId != widget.initialWarehouseId;

  bool get _valid =>
      _qty >= 1 &&
      (_maxQty == null || _qty <= _maxQty!) &&
      (!widget.requirePrice || _costValue > 0);

  Future<bool> _save() async {
    setState(() => _busy = true);
    try {
      if (widget.onConfirmWithWarehouse != null && _warehouseId != null) {
        await widget.onConfirmWithWarehouse!(_qty, _costValue, _warehouseId!);
      } else {
        await widget.onConfirm(_qty, _costValue);
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showAppError(context, e, title: 'No se pudo guardar');
      }
      return false;
    }
  }

  Future<void> _confirm() async {
    if (!_valid) return;
    if (await _save() && mounted) {
      setState(() => _canPop = true);
      Navigator.of(context).pop();
    }
  }

  /// Cierre por gesto: guarda si hay algo válido para guardar y recién ahí
  /// deja salir. Sin cambios (y sin [QtyCostSheet.autoSaveNew]) = solo cierra.
  Future<void> _autoSaveAndClose() async {
    if (_busy) return;
    final shouldSave = _valid && (_changed || widget.autoSaveNew);
    if (!shouldSave || await _save()) {
      if (mounted) {
        setState(() => _canPop = true);
        Navigator.of(context).pop();
      }
    }
  }

  void _setQty(int q) {
    final max = _maxQty;
    setState(() => _qty = max == null ? q.clamp(1, 9999) : q.clamp(1, max < 1 ? 1 : max));
  }

  void _pickWarehouse(String id) {
    setState(() {
      _warehouseId = id;
      final max = _maxQty;
      if (max != null && _qty > max) _qty = max < 1 ? 1 : max;
    });
  }

  @override
  Widget build(BuildContext context) {
    final max = _maxQty;
    final atMax = max != null && _qty >= max;
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _autoSaveAndClose();
      },
      child: Padding(
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
                if (widget.warehouses.length > 1) ...[
                  const SizedBox(height: 14),
                  _WarehousePicker(
                    warehouses: widget.warehouses,
                    selectedId: _warehouseId,
                    onChanged: _pickWarehouse,
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Cantidad',
                            style:
                                TextStyle(fontSize: 13, color: AppColors.textMuted)),
                        if (max != null)
                          Text(
                            max <= 0 ? 'sin stock acá' : 'disponible: $max',
                            style: TextStyle(
                                fontSize: 11,
                                color: max <= 0
                                    ? AppColors.danger
                                    : (atMax
                                        ? AppColors.warning
                                        : AppColors.textFaint)),
                          ),
                      ],
                    ),
                    const Spacer(),
                    _RoundBtn(icon: Icons.remove, onTap: () => _setQty(_qty - 1)),
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
                        filled: !atMax,
                        onTap: () => _setQty(_qty + 1)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(widget.priceLabel,
                    style:
                        const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                const SizedBox(height: 8),
                TextField(
                  controller: _cost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  style:
                      const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(hintText: '8,50'),
                ),
                if (widget.requirePrice && _costValue <= 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Ingresá el precio para poder vender (el producto no tiene uno cargado).',
                      style: TextStyle(fontSize: 12, color: AppColors.warning),
                    ),
                  ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy || !_valid ? null : _confirm,
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
      ),
    );
  }
}

class _WarehousePicker extends StatelessWidget {
  const _WarehousePicker({
    required this.warehouses,
    required this.selectedId,
    required this.onChanged,
  });

  final List<WarehouseChoice> warehouses;
  final String? selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Depósito de esta línea',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in warehouses)
              GestureDetector(
                onTap: () => onChanged(w.id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: w.id == selectedId
                        ? AppColors.primarySoft
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: w.id == selectedId
                            ? AppColors.primary
                            : AppColors.border),
                  ),
                  child: Text(
                    '${w.label} · ${w.available} disp.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: w.id == selectedId
                          ? AppColors.primary
                          : (w.available > 0
                              ? AppColors.textSecondary
                              : AppColors.textFaint),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
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
