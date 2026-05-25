// lib/widgets/barcode_field.dart
// Safe barcode field with scanner fallback & MissingPluginException handling

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../lang/translations.dart';

class BarcodeField extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String> onChanged;
  final FormFieldValidator<String>? validator;

  const BarcodeField({
    super.key,
    this.initialValue,
    required this.onChanged,
    this.validator,
  });

  @override
  State<BarcodeField> createState() => _BarcodeFieldState();
}

class _BarcodeFieldState extends State<BarcodeField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  Future<void> _openScanner() async {
    try {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const _BarcodeScannerScreen()),
      );
      if (result != null && result.isNotEmpty) {
        _controller.text = result;
        widget.onChanged(result);
      }
    } on MissingPluginException catch (e) {
      debugPrint('Scanner plugin missing: $e');
      _showManualEntry();
    } catch (e) {
      debugPrint('Scanner error: $e');
      _showManualEntry();
    }
  }

  void _showManualEntry() {
    final manualCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('barcode_scanner_unavailable')),
        content: TextField(
          controller: manualCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: t('enter_barcode_manually'),
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('cancel')),
          ),
          TextButton(
            onPressed: () {
              final text = manualCtrl.text.trim();
              Navigator.pop(ctx);
              if (text.isNotEmpty) {
                _controller.text = text;
                widget.onChanged(text);
              }
            },
            child: Text(t('confirm')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: t('barcode'),
        prefixIcon: const Icon(Icons.qr_code_scanner),
        suffixIcon: IconButton(
          icon: const Icon(Icons.camera_alt_outlined),
          tooltip: t('scan_barcode'),
          onPressed: _openScanner,
        ),
        border: const OutlineInputBorder(),
      ),
      onChanged: widget.onChanged,
      validator: widget.validator,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// ------------------------------------------------------------------------
// Internal full-screen scanner with safe lifecycle & error handling
// ------------------------------------------------------------------------
class _BarcodeScannerScreen extends StatefulWidget {
  const _BarcodeScannerScreen();

  @override
  State<_BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<_BarcodeScannerScreen>
    with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _hasError = false;
  bool _isPopping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initController();
  }

  Future<void> _initController() async {
    try {
      _controller = MobileScannerController(
        formats: const [
          BarcodeFormat.code128,
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
          BarcodeFormat.qrCode,
        ],
      );
      await _controller!.start();
      if (mounted) setState(() {});
    } on MissingPluginException catch (e) {
      debugPrint('MissingPluginException in scanner: $e');
      if (mounted) setState(() => _hasError = true);
    } catch (e) {
      debugPrint('Scanner init error: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _controller!.stop();
        break;
      case AppLifecycleState.resumed:
      case AppLifecycleState.hidden:
        _controller!.start();
        break;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isPopping) return;
    if (capture.barcodes.isEmpty) return;
    final barcode = capture.barcodes.first.displayValue;
    if (barcode != null && barcode.isNotEmpty) {
      _isPopping = true;
      _controller?.stop();
      Navigator.pop(context, barcode);
    }
  }

  void _close() {
    if (_isPopping) return;
    _isPopping = true;
    _controller?.stop();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.qr_code_scanner,
                    color: Colors.white54, size: 64),
                const SizedBox(height: 16),
                Text(
                  t('scanner_not_available'),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  t('enter_barcode_manually'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _close,
                  icon: const Icon(Icons.keyboard),
                  label: Text(t('enter_manually')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller!,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              debugPrint('MobileScanner runtime error: $error');
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.white54, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      t('camera_error'),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _close,
                      child: Text(t('close'),
                          style: const TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            },
          ),
          // Close button
          Positioned(
            top: topPadding + 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close,
                  color: Colors.white, size: 28),
              onPressed: _close,
            ),
          ),
          // Scan frame overlay
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white60, width: 2),
                borderRadius: BorderRadius.circular(20),
                color: Colors.transparent,
              ),
            ),
          ),
          // Bottom hint
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  t('point_camera_at_barcode'),
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }
}
