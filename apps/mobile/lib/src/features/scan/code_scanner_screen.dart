import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'scanner_chrome.dart';

/// Full-screen "read one code" scanner: pops with the raw detected string
/// (or the manually typed one), without interpreting it. Used by flows that
/// just need a code, like adding purchase lines by SKU.
class CodeScannerScreen extends StatefulWidget {
  const CodeScannerScreen({
    super.key,
    this.title = 'Escanear código',
    this.hint = 'Apuntá al código de barras',
    this.subtitle = 'El código leído vuelve al formulario anterior.',
  });

  final String title;
  final String hint;
  final String subtitle;

  /// Pushes the scanner and resolves with the code, or null when dismissed.
  static Future<String?> scan(
    BuildContext context, {
    String title = 'Escanear código',
    String hint = 'Apuntá al código de barras',
    String subtitle = 'El código leído vuelve al formulario anterior.',
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            CodeScannerScreen(title: title, hint: hint, subtitle: subtitle),
      ),
    );
  }

  @override
  State<CodeScannerScreen> createState() => _CodeScannerScreenState();
}

class _CodeScannerScreenState extends State<CodeScannerScreen> {
  final _controller = buildScannerController();
  bool _handled = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    String? raw;
    for (final b in capture.barcodes) {
      if (b.rawValue != null && b.rawValue!.isNotEmpty) {
        raw = b.rawValue;
        break;
      }
    }
    if (raw == null) return;
    _handled = true;
    await HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop(raw);
  }

  Future<void> _manualEntry() async {
    final code = await promptManualCode(context);
    if (code == null || code.isEmpty || !mounted) return;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) =>
                ScannerCameraError(onManual: _manualEntry),
          ),
          const ScannerScrim(),
          SafeArea(
            child: Column(
              children: [
                ScannerTopBar(
                  title: widget.title,
                  torch: _torch,
                  onClose: () => Navigator.of(context).pop(),
                  onTorch: () async {
                    await _controller.toggleTorch();
                    setState(() => _torch = !_torch);
                  },
                ),
                const Spacer(),
                ScannerHint(title: widget.hint, subtitle: widget.subtitle),
                const SizedBox(height: 18),
                ScannerManualButton(onPressed: _manualEntry),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
