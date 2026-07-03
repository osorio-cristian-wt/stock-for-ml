import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/errors.dart';
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
  late final TextEditingController _salePrice;
  late final TextEditingController _brand;

  String _currency = 'USD';
  bool _busy = false;
  bool _suggesting = false;
  bool _enriching = false;
  String? _error;
  String? _gtin;
  String? _categoryId;
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
    _salePrice = TextEditingController(
      text: p?.salePrice != null && p!.salePrice! > 0
          ? p.salePrice!.toString().replaceAll('.', ',')
          : '',
    );
    _currency = p?.purchaseCurrency ?? 'USD';
    _gtin = p?.gtin ?? widget.initialGtin;
    _categoryId = p?.categoryId ?? widget.initialCategoryId;
    _brand = TextEditingController(text: p?.brand ?? widget.initialBrand ?? '');
    _imageUrl = p?.imageUrl ?? widget.initialImageUrl;

    // Flujo barcode-first para cualquier alta con GTIN: si nadie corrió ya
    // la cascada (no llegó título prellenado), buscar la ficha en el catálogo
    // de ML acá mismo — así el alta desde compra/venta/búsqueda autocompleta
    // igual que la del escáner de Productos.
    final title = _title.text.trim();
    if (!widget.isEdit && _gtin != null && title.isEmpty) {
      Future.microtask(_autoEnrich);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _sku.dispose();
    _threshold.dispose();
    _cost.dispose();
    _salePrice.dispose();
    _brand.dispose();
    super.dispose();
  }

  double get _costValue =>
      double.tryParse(_cost.text.trim().replaceAll(',', '.')) ?? 0;

  double get _salePriceValue =>
      double.tryParse(_salePrice.text.trim().replaceAll(',', '.')) ?? 0;

  /// Cascada de enriquecimiento (catálogo ML → predictor) sobre el GTIN.
  /// Solo rellena lo que el usuario todavía no tocó.
  Future<void> _autoEnrich() async {
    if (!mounted || _gtin == null) return;
    setState(() => _enriching = true);
    try {
      final enrichment = await ref
          .read(catalogRepositoryProvider)
          .lookup(ScannedCode.classify(_gtin!));
      if (!mounted || !enrichment.hasMatch) return;
      setState(() {
        if (_title.text.trim().isEmpty && enrichment.name != null) {
          _title.text = enrichment.name!;
        }
        if (_brand.text.trim().isEmpty && enrichment.brand != null) {
          _brand.text = enrichment.brand!;
        }
        _imageUrl ??= enrichment.imageUrl;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ficha encontrada en ML — revisá los datos y guardá.'),
      ));
    } catch (_) {
      // Silencioso: sin ficha se sigue con carga manual, como en el escáner.
    } finally {
      if (mounted) setState(() => _enriching = false);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'El título es obligatorio.');
      return;
    }
    // Ambos precios son obligatorios: sin costo no hay rentabilidad y sin
    // precio de venta la venta local no puede sugerir nada.
    if (_costValue <= 0) {
      setState(() => _error = 'Ingresá el costo de compra (mayor a 0).');
      return;
    }
    if (_salePriceValue <= 0) {
      setState(() => _error = 'Ingresá el precio de venta (mayor a 0).');
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
    final brand = _brand.text.trim().isEmpty ? null : _brand.text.trim();

    try {
      if (widget.isEdit) {
        final updated = widget.product!.copyWith(
          title: title,
          sku: sku,
          gtin: _gtin,
          categoryId: _categoryId,
          brand: brand,
          purchaseCost: _costValue,
          purchaseCurrency: _currency,
          salePrice: _salePriceValue,
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
          brand: brand,
          purchaseCost: _costValue,
          purchaseCurrency: _currency,
          salePrice: _salePriceValue,
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
      setState(() => _error = 'No se pudo guardar. ${AppErrors.friendly(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _short(Object e) => AppErrors.friendly(e);

  /// LLM last-fallback (§7.4): suggest category + brand from the title when the
  /// catalog/predictor couldn't resolve it. The user always confirms/overrides.
  Future<void> _suggest() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Ingresá un título para sugerir la categoría.');
      return;
    }
    final categories = ref.read(categoriesProvider).valueOrNull ?? const [];
    setState(() {
      _suggesting = true;
      _error = null;
    });
    try {
      final res = await ref.read(catalogRepositoryProvider).classify(
            title: title,
            categorySlugs: categories.map((c) => c.slug).toList(),
          );
      final slug = res?['category_slug'] as String?;
      final brand = (res?['brand'] as String?)?.trim();
      ProductCategory? match;
      for (final c in categories) {
        if (c.slug == slug) {
          match = c;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        if (match != null) _categoryId = match.id;
        if (brand != null && brand.isNotEmpty && _brand.text.trim().isEmpty) {
          _brand.text = brand;
        }
      });
      if (mounted) {
        final ok = match != null || (brand != null && brand.isNotEmpty);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? 'Sugerencia aplicada — revisá y confirmá.'
              : 'No se pudo clasificar automáticamente.'),
        ));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo sugerir. ${_short(e)}');
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  /// Inline creation so the user can build their taxonomy while loading a
  /// product (supermarket-style), without leaving the form.
  Future<void> _createCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Nueva categoría',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Ej. Auriculares'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final slug = _slugify(name);
    if (slug.isEmpty) {
      setState(() => _error = 'Nombre de categoría inválido.');
      return;
    }
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';
    try {
      final created = await ref.read(inventoryRepositoryProvider).createCategory(
            ProductCategory(id: '', profileId: userId, name: name, slug: slug),
          );
      ref.invalidate(categoriesProvider);
      if (mounted) setState(() => _categoryId = created.id);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo crear la categoría. ${_short(e)}');
      }
    }
  }

  String _slugify(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  @override
  Widget build(BuildContext context) {
    final fx = ref.watch(fxProvider).valueOrNull;
    final mlConnected = ref.watch(mlAccountProvider).valueOrNull != null;
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
          if (_enriching) ...[
            const _EnrichingBanner(),
            const SizedBox(height: 13),
          ],
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _Field(label: 'Marca', controller: _brand, hint: 'Genérica')),
              const SizedBox(width: 11),
              _SuggestButton(busy: _suggesting, onTap: _suggesting ? null : _suggest),
            ],
          ),
          const SizedBox(height: 13),
          _CategoryField(
            categories: ref.watch(categoriesProvider).valueOrNull ?? const [],
            selectedId: _categoryId,
            onChanged: (id) => setState(() => _categoryId = id),
            onCreate: _createCategory,
          ),
          const SizedBox(height: 13),
          _CostField(
            controller: _cost,
            currency: _currency,
            onCurrency: (c) => setState(() => _currency = c),
            fxRate: fx?.rate,
            costValue: _costValue,
          ),
          const SizedBox(height: 13),
          _Field(
            label: 'Precio de venta (ARS)',
            controller: _salePrice,
            hint: '25.000',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
          ),
          if (mlConnected) ...[
            const SizedBox(height: 16),
            const _LinkMlHint(),
          ],
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

/// Aviso mientras corre la cascada de enriquecimiento por GTIN.
class _EnrichingBanner extends StatelessWidget {
  const _EnrichingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text('Buscando la ficha en el catálogo de MercadoLibre…',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
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

/// After creating the product, the user links an ML publication from the
/// product detail screen ("Vincular publicación de ML"). This just signposts it.
class _LinkMlHint extends StatelessWidget {
  const _LinkMlHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.link_rounded, size: 18, color: AppColors.textMuted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Después de crear el producto vas a poder vincularlo a una '
              'publicación de ML desde su detalle.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Triggers the LLM classification fallback from the title.
class _SuggestButton extends StatelessWidget {
  const _SuggestButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Aligns with the field below its label.
      padding: const EdgeInsets.only(top: 22),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              )
            : const Icon(Icons.auto_awesome_outlined, size: 16),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        label: const Text('Sugerir'),
      ),
    );
  }
}

/// Category picker fed by the user's taxonomy. "Sin categoría" clears it.
class _CategoryField extends StatelessWidget {
  const _CategoryField({
    required this.categories,
    required this.selectedId,
    required this.onChanged,
    required this.onCreate,
  });

  final List<ProductCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    // Guard against a stale id (e.g. an AI-suggested category not yet loaded).
    final value =
        categories.any((c) => c.id == selectedId) ? selectedId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Categoría',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500)),
              GestureDetector(
                onTap: onCreate,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 14, color: AppColors.primary),
                    SizedBox(width: 2),
                    Text('Nueva',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        DropdownButtonFormField<String?>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          icon: const Icon(Icons.expand_more, color: AppColors.textFaint),
          decoration: InputDecoration(
            hintText: categories.isEmpty ? 'Sin categorías aún' : 'Sin categoría',
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Sin categoría',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
            for (final c in categories)
              DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
          ],
          onChanged: categories.isEmpty ? null : onChanged,
        ),
      ],
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
