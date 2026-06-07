import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../lang/translations.dart';
import '../utils/store_qr_helper.dart';
import 'store_products_screen.dart';

/// Scans a store QR code and opens that store's product page.
class StoreQrScannerScreen extends ConsumerStatefulWidget {
  const StoreQrScannerScreen({super.key});

  @override
  ConsumerState<StoreQrScannerScreen> createState() =>
      _StoreQrScannerScreenState();
}

class _StoreQrScannerScreenState extends ConsumerState<StoreQrScannerScreen> {
  MobileScannerController? _controller;
  bool _torchOn = false;
  bool _isScanning = true;
  String? _lastCode;
  bool _isDesktopUnsupported = false;
  final TextEditingController _manualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      _isDesktopUnsupported = true;
      return;
    }
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _openStore(int storeId) {
    _isScanning = false;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => StoreProductsScreen(storeId: storeId),
      ),
    );
  }

  void _handleRawCode(String raw) {
    final storeId = StoreQrHelper.parseStoreId(raw);
    if (storeId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('invalid_store_qr') ?? 'Not a valid store QR code',
          ),
        ),
      );
      return;
    }
    _openStore(storeId);
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;
    final code = barcode.rawValue!;
    if (code == _lastCode) return;
    _lastCode = code;
    _handleRawCode(code);
  }

  void _submitManual() {
    final code = _manualController.text.trim();
    if (code.isEmpty) return;
    _handleRawCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isDesktopUnsupported) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t('scan_store_qr') ?? 'Scan Store QR'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.qr_code_scanner, size: 72, color: Colors.grey),
              const SizedBox(height: 20),
              Text(
                t('scanner_not_available') ?? 'Camera scanner not available',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                t('paste_store_qr_hint') ??
                    'Paste a store link or enter the store ID',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _manualController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: t('store_link_or_id') ?? 'Store link or ID',
                  hintText: 'storaq://store/123',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.qr_code_2),
                ),
                onSubmitted: (_) => _submitManual(),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _submitManual,
                icon: const Icon(Icons.store),
                label: Text(t('open_store') ?? 'Open Store'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_controller != null)
            MobileScanner(
              controller: _controller!,
              onDetect: _onDetect,
              fit: BoxFit.cover,
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      t('scan_store_qr') ?? 'Scan Store QR',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: Icon(
                        _torchOn ? Icons.flash_on : Icons.flash_off,
                        color: Colors.white,
                      ),
                      onPressed: () async {
                        await _controller?.toggleTorch();
                        setState(() => _torchOn = !_torchOn);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  t('align_qr_in_frame') ?? 'Align the store QR code in the frame',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
