import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../lang/translations.dart';
import '../utils/store_qr_helper.dart';

class StoreQrScreen extends ConsumerStatefulWidget {
  final int storeId;
  final String storeName;

  const StoreQrScreen({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  @override
  ConsumerState<StoreQrScreen> createState() => _StoreQrScreenState();
}

class _StoreQrScreenState extends ConsumerState<StoreQrScreen> {
  final GlobalKey _printKey = GlobalKey();

  String get _payload => StoreQrHelper.storeQrPayload(widget.storeId);

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t('link_copied') ?? 'Link copied')),
    );
  }

  Future<Uint8List> _captureImage() async {
    final context = _printKey.currentContext;
    if (context == null) {
      throw Exception('QR card not ready. Please wait and try again.');
    }
    await Future.delayed(const Duration(milliseconds: 100));
    final renderObject = context.findRenderObject();
    if (renderObject == null || renderObject is! RenderRepaintBoundary) {
      throw Exception('QR render object not found.');
    }
    final image = await renderObject.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('Failed to encode QR image.');
    return byteData.buffer.asUint8List();
  }

  Future<pw.Document> _buildPdf() async {
    final bytes = await _captureImage();
    final pdfImage = pw.MemoryImage(bytes);

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                boxShadow: const [
                  pw.BoxShadow(
                    color: PdfColors.grey300,
                    blurRadius: 6,
                    offset: PdfPoint(0, 3),
                  ),
                ],
              ),
              child: pw.ClipRRect(
                horizontalRadius: 8,
                verticalRadius: 8,
                child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
              ),
            ),
          );
        },
      ),
    );
    return pdf;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _exportPdf() async {
    try {
      final pdf = await _buildPdf();
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/store_qr_${widget.storeId}.pdf');
      await file.writeAsBytes(await pdf.save());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('pdf_saved') ?? 'PDF saved'),
          action: SnackBarAction(
            label: t('open') ?? 'Open',
            onPressed: () => OpenFilex.open(file.path),
          ),
        ),
      );
    } catch (e) {
      _showError('${t('export_failed') ?? 'Export failed'}: $e');
    }
  }

  Future<void> _printPdf() async {
    try {
      final pdf = await _buildPdf();
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e) {
      _showError('${t('print_failed') ?? 'Print failed'}: $e');
    }
  }

  Future<void> _sharePdf() async {
    try {
      final pdf = await _buildPdf();
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/store_qr_${widget.storeId}.pdf');
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${widget.storeName} — ${t('store_qr_code') ?? 'Store QR Code'}',
      );
    } catch (e) {
      _showError('${t('share_failed') ?? 'Share failed'}: $e');
    }
  }

  Widget _buildQrCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.storeName,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t('scan_to_visit_store'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: BarcodeWidget(
                barcode: Barcode.qrCode(),
                data: _payload,
                width: 220,
                height: 220,
                drawText: false,
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              _payload,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('store_qr_code') ?? 'Store QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: t('copy_link') ?? 'Copy link',
            onPressed: _copyLink,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: t('share'),
            onPressed: _sharePdf,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                RepaintBoundary(
                  key: _printKey,
                  child: _buildQrCard(theme),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _exportPdf,
                        icon: const Icon(Icons.picture_as_pdf),
                        label: Text(t('export_pdf') ?? 'Export PDF'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _printPdf,
                        icon: const Icon(Icons.print),
                        label: Text(t('print') ?? 'Print'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
