// lib/widgets/barcode_field.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/barcode_helper.dart';
import '../screens/barcode_scanner_screen.dart';
import '../lang/translations.dart';

class BarcodeField extends StatefulWidget {
  final String? initialValue;
  final ValueChanged<String> onChanged;
  final FormFieldValidator<String>? validator;
  final bool allowGenerate;
  final bool allowScan;
  final String? expectedFormat;

  const BarcodeField({
    super.key,
    this.initialValue,
    required this.onChanged,
    this.validator,
    this.allowGenerate = true,
    this.allowScan = true,
    this.expectedFormat,
  });

  @override
  State<BarcodeField> createState() => _BarcodeFieldState();
}

class _BarcodeFieldState extends State<BarcodeField> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _validate(String value) {
    if (value.isEmpty) {
      setState(() => _error = null);
      return;
    }
    final valid = BarcodeHelper.isValidBarcode(value);
    setState(() => _error = valid ? null : t('invalid_barcode_format'));
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => BarcodeScannerScreen(expectedFormat: widget.expectedFormat),
      ),
    );
    if (code != null && mounted) {
      _ctrl.text = code;
      widget.onChanged(code);
      _validate(code);
    }
  }

  void _generate() {
    final code = BarcodeHelper.generateEAN13();
    _ctrl.text = code;
    widget.onChanged(code);
    _validate(code);
  }

  void _copy() {
    if (_ctrl.text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _ctrl.text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('barcode_copied')), duration: const Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _ctrl,
          decoration: InputDecoration(
            labelText: t('barcode'),
            hintText: t('barcode_hint'),
            prefixIcon: const Icon(Icons.qr_code),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_ctrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: _copy,
                    tooltip: t('copy'),
                  ),
                if (widget.allowScan)
                  IconButton(
                    icon: const Icon(Icons.camera_alt, size: 20),
                    onPressed: _scan,
                    tooltip: t('scan_barcode'),
                  ),
                if (widget.allowGenerate)
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high, size: 20),
                    onPressed: _generate,
                    tooltip: t('generate_barcode'),
                  ),
              ],
            ),
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
          keyboardType: TextInputType.text,
          onChanged: (v) {
            widget.onChanged(v);
            _validate(v);
          },
          validator: widget.validator,
        ),
        if (_ctrl.text.isNotEmpty && _error == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${t('format')}: ${BarcodeHelper.isValidEAN13(_ctrl.text) ? 'EAN-13' : BarcodeHelper.isValidUPC(_ctrl.text) ? 'UPC-A' : 'Code128'}',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  Text(
                    BarcodeHelper.formatForDisplay(_ctrl.text),
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
