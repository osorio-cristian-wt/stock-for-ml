import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';

/// Screen 06 · Alta / Editar producto. Creates a new product or updates an
/// existing one. Can be prefilled from the scan/catalog flow (gtin + enriched
/// title/brand/category).
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({
    super.key,
    this.product,
    this.initialGtin,
    this.initialSku,
    this.initialTitle,
    this.initialBrand,
    this.initialCategoryId,
    this.initialImageUrl,
  });

  final Product? product;
  final String? initialGtin;
  final String? initialSku;
  final String? initialTitle;
  final String? initialBrand;
  final String? initialCategoryId;
  final String? initialImageUrl;

  bool get isEdit => product != null;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _sku;
  late final TextEditingController _threshold;
  late final TextEditingController _cost;

  String _currency = 'USD';
  bool _linkMl = false;
  bool _busy = false;
  String? _error;
  String? _gtin;
  String? _categoryId;
  String? _brand;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _title = TextEditingController(text: p?.title ?? widget.initialTitle ?? '');
    _sku = TextEditingController(text: p?.sku ?? widget.initialSku ?? '');
    _threshold = TextEditingController(
      text: p?.lowStockThreshold?.toString() ?? '',
    );
    _cost = TextEditingController(
      text: p != null && p.purchaseCost > 0
          ? p.purchaseCost.toString().replaceAll('.', ',')
          : '',
    );
    _currency = p?.purchaseCurrency ?? 'USD';
    _gtin = p?.gtin ?? widget.initialGtin;
    _categoryId = p?.categoryId ?? widget.initialCategoryId;
    _brand = p?.brand ?? widget.initialBrand;
    _imageUrl = p?.imageUrl ?? widget.initialImageUrl;
  }

  @override
  void dispose() {
    _title.dispose();
    _sku.dispose();
    _threshold.dispose();
    _cost.dispose();
    super.dispose();
  }

  double get _costValue =>
      double.tryParse(_cost.text.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'El título es obligatorio.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final repo = ref.read(productsRepositoryProvider);
    final userId =
        ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';
    final threshold = int.tryParse(_threshold.text.trim());
    final sku = _sku.text.trim().isEmpty ? null : _sku.text.trim();

    try {
      if (widget.isEdit) {
        final updated = widget.product!.copyWith(
          title: title,
          sku: sku,
          gtin: _gtin,
          categoryId: _categoryId,
          brand: _brand,
          purchaseCost: _costValue,
          purchaseCurrency: _currency,
          lowStockThreshold: threshold,
        );
        await repo.update(updated);
      } else {
        await repo.create(Product(
          id: '',
          profileId: userId,
          title: title,
          sku: sku,
          gtin: _gtin,
          categoryId: _categoryId,
          brand: _brand,
          purchaseCost: _costValue,
          purchaseCurrency: _currency,
          lowStockThreshold: threshold,
          imageUrl: _imageUrl,
        ));
      }
      ref.invalidate(economicsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isEdit ? 'Producto actualizado' : 'Producto creado'),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _error = 'No se pudo guardar. ${_short(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _short(Object e) {
    final s = e.toString();
    return s.length > 90 ? '${s.substring(0, 90)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    final fx = ref.watch(fxProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar',
              style: TextStyle(color: AppColors.textMuted)),
        ),
        leadingWidth: 90,
        title: Text(widget.isEdit ? 'Editar producto' : 'Nuevo producto'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text(
              'Guardar',
              style: TextStyle(
                color: _busy ? AppColors.textFaint : AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Center(child: _PhotoPicker(imageUrl: _imageUrl)),
          const SizedBox(height: 20),
          if (_gtin != null) ...[
            _ReadonlyRow(label: 'GTIN (código escaneado)', value: _gtin!),
            const SizedBox(height: 13),
          ],
          _Field(label: 'Título', controller: _title, hint: 'Auriculares Bluetooth'),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _Field(label: 'SKU', controller: _sku, hint: 'SKU-001')),
              const SizedBox(width: 11),
              Expanded(
                child: _Field(
                  label: 'Umbral stock',
                  controller: _threshold,
                  hint: '5',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          _CostField(
            controller: _cost,
            currency: _currency,
            onCurrency: (c) => setState(() => _currency = c),
            fxRate: fx?.rate,
            costValue: _costValue,
          ),
          const SizedBox(height: 16),
          _LinkMlToggle(
            value: _linkMl,
            onChanged: (v) => setState(() => _linkMl = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: AppColors.onPrimary),
                  )
                : Text(widget.isEdit ? 'Guardar cambios' : 'Crear producto'),
          ),
        ],
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Carga de fotos: próximamente')),
      ),
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.borderStrong,
            style: BorderStyle.solid,
          ),
          image: imageUrl != null
              ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover)
              : null,
        ),
        child: imageUrl != null
            ? null
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined,
                      color: AppColors.textFaint, size: 22),
                  SizedBox(height: 5),
                  Text('Foto',
                      style: TextStyle(fontSize: 10, color: AppColors.textFaint)),
                ],
              ),
      ),
    );
  }
}

class _CostField extends StatelessWidget {
  const _CostField({
    required this.controller,
    required this.currency,
    required this.onCurrency,
    required this.costValue,
    this.fxRate,
  });

  final TextEditingController controller;
  final String currency;
  final ValueChanged<String> onCurrency;
  final double costValue;
  final double? fxRate;

  @override
  Widget build(BuildContext context) {
    final showHint = currency == 'USD' && fxRate != null && costValue > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6, left: 2),
          child: Text('Costo de compra',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500)),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(hintText: '8,50'),
              ),
            ),
            const SizedBox(width: 11),
            _CurrencyToggle(currency: currency, onChanged: onCurrency),
          ],
        ),
        if (showHint)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              '≈ ${Fmt.ars(costValue * fxRate!)} al dólar de hoy (${Fmt.ars(fxRate!)})',
              style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
            ),
          ),
      ],
    );
  }
}

class _CurrencyToggle extends StatelessWidget {
  const _CurrencyToggle({required this.currency, required this.onChanged});

  final String currency;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _seg('USD'),
          _seg('ARS'),
        ],
      ),
    );
  }

  Widget _seg(String code) {
    final selected = currency == code;
    return GestureDetector(
      onTap: () => onChanged(code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          code,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.onPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _LinkMlToggle extends StatelessWidget {
  const _LinkMlToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('Vincular a publicación de ML',
                style: TextStyle(fontSize: 13, color: AppColors.textBody)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.onPrimary,
            activeTrackColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _ReadonlyRow extends StatelessWidget {
  const _ReadonlyRow({required this.label, required this.value});

  final String label;
  final String value;

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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.surfaceDeep,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.qr_code_2, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textPrimary, letterSpacing: 0.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

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
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}
