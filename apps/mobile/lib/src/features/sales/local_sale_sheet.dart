import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';

/// Registers a sale outside MercadoLibre (channel=local): quantity + price,
/// optional customer (from the user's own registry, with quick creation) and
/// warehouse. The backend discounts stock and pushes the new availability to
/// ML so it never oversells.
class LocalSaleSheet extends ConsumerStatefulWidget {
  const LocalSaleSheet({super.key, required this.product});

  final Product product;

  static Future<void> show(BuildContext context, {required Product product}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LocalSaleSheet(product: product),
    );
  }

  @override
  ConsumerState<LocalSaleSheet> createState() => _LocalSaleSheetState();
}

class _LocalSaleSheetState extends ConsumerState<LocalSaleSheet> {
  final _price = TextEditingController();
  int _qty = 1;
  String? _customerId; // null = sin cliente
  String? _warehouseId; // null = principal
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  double get _priceValue =>
      double.tryParse(_price.text.trim().replaceAll('.', '').replaceAll(',', '.')) ??
      double.tryParse(_price.text.trim()) ??
      0;

  Future<void> _newCustomer() async {
    final created = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewCustomerSheet(),
    );
    if (created != null && mounted) {
      ref.invalidate(customersProvider);
      setState(() => _customerId = created.id);
    }
  }

  Future<void> _confirm() async {
    if (_priceValue <= 0) {
      setState(() => _error = 'Ingresá el precio de venta.');
      return;
    }
    if (_qty > widget.product.currentStock) {
      setState(() => _error = 'No hay stock suficiente (${widget.product.currentStock} disp.).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(salesRepositoryProvider).createLocalSale(
            productId: widget.product.id,
            quantity: _qty,
            unitPrice: _priceValue,
            customerId: _customerId,
            warehouseId: _warehouseId,
          );
      ref.invalidate(salesProvider);
      ref.invalidate(dashboardProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Venta registrada · stock sincronizando con ML')),
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
    final customers =
        ref.watch(customersProvider).valueOrNull ?? const <Customer>[];
    final warehouses =
        ref.watch(warehousesStreamProvider).valueOrNull ?? const <Warehouse>[];
    final total = _priceValue * _qty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
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
              const Text('Vender (fuera de ML)',
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
              const Text('Precio unitario (ARS)',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              TextField(
                controller: _price,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(hintText: '15000'),
              ),
              const SizedBox(height: 16),
              const Text('Cliente (opcional)',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _customerId,
                      isExpanded: true,
                      dropdownColor: AppColors.surface,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14),
                      icon: const Icon(Icons.expand_more,
                          color: AppColors.textFaint),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Sin cliente'),
                        ),
                        for (final c in customers)
                          DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(c.name),
                          ),
                      ],
                      onChanged: (id) => setState(() => _customerId = id),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _newCustomer,
                    tooltip: 'Nuevo cliente',
                    icon: const Icon(Icons.person_add_alt_outlined,
                        color: AppColors.primary),
                  ),
                ],
              ),
              if (warehouses.length > 1) ...[
                const SizedBox(height: 16),
                const Text('Depósito',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: _warehouseId,
                  isExpanded: true,
                  dropdownColor: AppColors.surface,
                  style:
                      const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  icon: const Icon(Icons.expand_more, color: AppColors.textFaint),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Principal (despacho)'),
                    ),
                    for (final w in warehouses)
                      DropdownMenuItem<String?>(
                        value: w.id,
                        child: Text(w.isDefault ? '${w.name} · principal' : w.name),
                      ),
                  ],
                  onChanged: (id) => setState(() => _warehouseId = id),
                ),
              ],
              const SizedBox(height: 14),
              Center(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    children: [
                      const TextSpan(text: 'Total: '),
                      TextSpan(
                        text: '\$${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: AppColors.primary, fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                          text:
                              ' · stock ${widget.product.currentStock} → ${widget.product.currentStock - _qty}'),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(fontSize: 12, color: AppColors.danger)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed:
                    (_busy || widget.product.currentStock < _qty) ? null : _confirm,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: AppColors.onPrimary),
                      )
                    : const Text('Registrar venta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick customer creation: only the name is required; fiscal/contact data is
/// optional (expandable) for the future.
class _NewCustomerSheet extends ConsumerStatefulWidget {
  const _NewCustomerSheet();

  @override
  ConsumerState<_NewCustomerSheet> createState() => _NewCustomerSheetState();
}

class _NewCustomerSheetState extends ConsumerState<_NewCustomerSheet> {
  final _name = TextEditingController();
  final _legalName = TextEditingController();
  final _taxId = TextEditingController();
  final _phone = TextEditingController();
  bool _showExtra = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _legalName.dispose();
    _taxId.dispose();
    _phone.dispose();
    super.dispose();
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
      final created = await ref.read(customersRepositoryProvider).create(
            Customer(
              id: '',
              profileId: userId,
              name: name,
              legalName: _legalName.text.trim().isEmpty
                  ? null
                  : _legalName.text.trim(),
              taxId: _taxId.text.trim().isEmpty ? null : _taxId.text.trim(),
              phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            ),
          );
      if (mounted) Navigator.of(context).pop(created);
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Nuevo cliente',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(hintText: 'Nombre *'),
              ),
              const SizedBox(height: 10),
              if (!_showExtra)
                TextButton.icon(
                  onPressed: () => setState(() => _showExtra = true),
                  icon: const Icon(Icons.expand_more, size: 18),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary),
                  label: const Text('Datos extra (razón social, CUIT…)'),
                )
              else ...[
                TextField(
                  controller: _legalName,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(hintText: 'Razón social'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _taxId,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(hintText: 'CUIT / CUIL / DNI'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(hintText: 'Teléfono'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(fontSize: 12, color: AppColors.danger)),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: AppColors.onPrimary),
                      )
                    : const Text('Crear cliente'),
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
