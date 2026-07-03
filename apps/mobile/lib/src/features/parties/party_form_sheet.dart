import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Datos capturados por el formulario compartido de proveedor/cliente.
/// Solo el nombre es obligatorio; el resto es opcional para más datos a
/// futuro (razón social, CUIT/CUIL, contacto).
class PartyFormData {
  const PartyFormData({
    required this.name,
    this.legalName,
    this.taxId,
    this.phone,
    this.email,
  });

  final String name;
  final String? legalName;
  final String? taxId;
  final String? phone;
  final String? email;
}

/// Ventana ÚNICA de alta para proveedores y clientes (mismo diseño para
/// ambos). Devuelve los datos; el caller decide en qué tabla los crea.
class PartyFormSheet extends StatefulWidget {
  const PartyFormSheet({super.key, required this.title, this.nameHint});

  /// 'Nuevo proveedor' | 'Nuevo cliente'.
  final String title;
  final String? nameHint;

  static Future<PartyFormData?> show(
    BuildContext context, {
    required String title,
    String? nameHint,
  }) {
    return showModalBottomSheet<PartyFormData>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PartyFormSheet(title: title, nameHint: nameHint),
    );
  }

  @override
  State<PartyFormSheet> createState() => _PartyFormSheetState();
}

class _PartyFormSheetState extends State<PartyFormSheet> {
  final _name = TextEditingController();
  final _legalName = TextEditingController();
  final _taxId = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _legalName.dispose();
    _taxId.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }
    Navigator.of(context).pop(PartyFormData(
      name: name,
      legalName: _opt(_legalName),
      taxId: _opt(_taxId),
      phone: _opt(_phone),
      email: _opt(_email),
    ));
  }

  @override
  Widget build(BuildContext context) {
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
              const SizedBox(height: 16),
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              const Text(
                'Solo el nombre es obligatorio. Los datos fiscales quedan '
                'guardados para más adelante.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              _Field(controller: _name, hint: widget.nameHint ?? 'Nombre *',
                  autofocus: true,
                  capitalization: TextCapitalization.words),
              const SizedBox(height: 10),
              _Field(controller: _legalName, hint: 'Razón social (opcional)'),
              const SizedBox(height: 10),
              _Field(controller: _taxId, hint: 'CUIT / CUIL (opcional)'),
              const SizedBox(height: 10),
              _Field(
                  controller: _phone,
                  hint: 'Teléfono (opcional)',
                  keyboard: TextInputType.phone),
              const SizedBox(height: 10),
              _Field(
                  controller: _email,
                  hint: 'Email (opcional)',
                  keyboard: TextInputType.emailAddress),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(fontSize: 12, color: AppColors.danger)),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: _submit, child: const Text('Guardar')),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.autofocus = false,
    this.keyboard,
    this.capitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String hint;
  final bool autofocus;
  final TextInputType? keyboard;
  final TextCapitalization capitalization;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboard,
      textCapitalization: capitalization,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(hintText: hint),
    );
  }
}
