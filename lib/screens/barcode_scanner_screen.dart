// lib/screens/barcode_scanner_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../lang/translations.dart';

class BarcodeScannerScreen extends StatefulWidget {
  final bool continuous;
  final String? expectedFormat;
  const BarcodeScannerScreen({
    super.key,
    this.continuous = false,
    this.expectedFormat,
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  MobileScannerController? _controller;
  bool _torchOn = false;
  bool _isScanning = true;
  String? _lastCode;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;
    final code = barcode.rawValue!;
    if (code == _lastCode) return; // debounce
    _lastCode = code;

    // Validate format if requested
    if (widget.expectedFormat != null) {
      final format = barcode.format?.name ?? '';
      if (!format.toLowerCase().contains(widget.expectedFormat!.toLowerCase())) {
        return;
      }
    }

    if (!widget.continuous) {
      _isScanning = false;
      Navigator.pop(context, code);
      return;
    }

    // Continuous mode: return each scan immediately
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          if (_controller != null)
            MobileScanner(
              controller: _controller!,
              onDetect: _onDetect,
              fit: BoxFit.cover,
            ),

          // Overlay
          CustomPaint(
            size: Size.infinite,
            painter: _ScannerOverlayPainter(
              borderColor: theme.colorScheme.primary,
              borderRadius: 16,
              borderLength: 40,
              borderWidth: 4,
              overlayColor: Colors.black.withOpacity(0.5),
            ),
          ),

          // Header
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      t('scan_barcode'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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

          // Bottom hint
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  t('align_barcode_in_frame'),
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

class _ScannerOverlayPainter extends CustomPainter {
  final Color borderColor;
  final double borderRadius;
  final double borderLength;
  final double borderWidth;
  final Color overlayColor;

  _ScannerOverlayPainter({
    required this.borderColor,
    required this.borderRadius,
    required this.borderLength,
    required this.borderWidth,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scanAreaSize = size.width * 0.75;
    final left = (size.width - scanAreaSize) / 2;
    final top = (size.height - scanAreaSize) / 2.5;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize * 0.6),
      Radius.circular(borderRadius),
    );

    // Dark overlay
    final overlayPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addRRect(rect);
    final finalPath = Path.combine(PathOperation.difference, overlayPath, cutoutPath);
    canvas.drawPath(finalPath, Paint()..color = overlayColor);

    // Corner borders
    final paint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final r = rect;
    const gap = 0.0;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(r.left + gap, r.top + borderLength)
        ..lineTo(r.left + gap, r.top + gap)
        ..lineTo(r.left + borderLength, r.top + gap),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(r.right - borderLength, r.top + gap)
        ..lineTo(r.right - gap, r.top + gap)
        ..lineTo(r.right - gap, r.top + borderLength),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(r.left + gap, r.bottom - borderLength)
        ..lineTo(r.left + gap, r.bottom - gap)
        ..lineTo(r.left + borderLength, r.bottom - gap),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(r.right - borderLength, r.bottom - gap)
        ..lineTo(r.right - gap, r.bottom - gap)
        ..lineTo(r.right - gap, r.bottom - borderLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
