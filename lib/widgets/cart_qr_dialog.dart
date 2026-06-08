import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../lang/translations.dart';
import '../utils/cart_qr_helper.dart';

class CartQrDialog extends StatelessWidget {
  final String storeName;
  final String qrPayload;
  final int itemCount;

  const CartQrDialog({
    super.key,
    required this.storeName,
    required this.qrPayload,
    required this.itemCount,
  });

  static Future<void> show(
    BuildContext context, {
    required String storeName,
    required String qrPayload,
    required int itemCount,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => CartQrDialog(
        storeName: storeName,
        qrPayload: qrPayload,
        itemCount: itemCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(t('cart_qr_title') ?? 'Cart QR Code'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              storeName,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${t('items') ?? 'items'}: $itemCount',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: qrPayload,
                  width: 220,
                  height: 220,
                  drawText: false,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t('cart_qr_hint') ??
                  'Show this QR at checkout. The store will scan it and load your items with current prices and stock.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: qrPayload));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(t('copied') ?? 'Copied'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          child: Text(t('copy') ?? 'Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t('done') ?? 'Done'),
        ),
      ],
    );
  }
}
