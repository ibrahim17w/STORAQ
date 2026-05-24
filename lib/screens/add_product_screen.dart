// lib/screens/add_product_screen.dart
// FIXED: No double setState, proper gallery integration, max 4 images

import 'dart:io';
import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api_service.dart';
import '../services/offline_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/barcode_field.dart';
import '../widgets/category_picker.dart';
import '../widgets/product_image_gallery.dart';
import '../utils/barcode_helper.dart';
import '../lang/translations.dart';

class AddProductScreen extends StatefulWidget {
  final Map<String, dynamic>? product;
  const AddProductScreen({super.key, this.product});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  List<File> _newImages = [];
  List<String> _existingImages = [];
  List<int> _categoryIds = [];
  bool _isLoading = false;
  bool _barcodeExists = false;
  Map<String, dynamic>? _existingBarcodeProduct;

  static const int _maxImagesPerProduct = 4;

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _nameCtrl.text = widget.product!['name'] ?? '';
      _priceCtrl.text = widget.product!['price']?.toString() ?? '';
      _qtyCtrl.text = widget.product!['quantity']?.toString() ?? '';
      _descCtrl.text = widget.product!['description'] ?? '';
      _barcodeCtrl.text = widget.product!['barcode'] ?? '';
      _existingImages = List<String>.from(widget.product!['image_urls'] ?? []);
      _categoryIds = List<int>.from(widget.product!['category_ids'] ?? []);
    }
  }

  Future<void> _checkBarcode(String code) async {
    if (code.isEmpty || !BarcodeHelper.isValidBarcode(code)) return;
    try {
      final result = await ApiService.validateBarcode(code);
      if (result != null && result['exists'] == true) {
        if (mounted) {
          setState(() {
            _barcodeExists = true;
            _existingBarcodeProduct = result['product'];
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _barcodeExists = false;
            _existingBarcodeProduct = null;
          });
        }
      }
    } catch (_) {
      // Silently fail validation; backend will enforce on save
    }
  }

  /// Called by gallery when new files are picked.
  /// Gallery now handles max enforcement internally, so we just accept.
  void _handleNewImages(List<File> files) {
    // Only update state — no validation needed here anymore
    setState(() => _newImages = files);
  }

  /// Called by gallery when existing images are removed.
  void _handleExistingRemoved(List<String> removed) {
    // If you need to track removed URLs for server deletion, do it here.
    // For now just let the gallery manage its own _urls list.
    setState(() {}); // rebuild to sync any parent-level counters if needed
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError(t('name_required'));
      return;
    }

    final priceText = _priceCtrl.text.trim();
    final price = double.tryParse(priceText.replaceAll(',', '.'));
    if (price == null || price < 0) {
      _showError(t('invalid_price'));
      return;
    }

    final qtyText = _qtyCtrl.text.trim();
    final qty = int.tryParse(qtyText);
    if (qty == null || qty < 0) {
      _showError(t('invalid_quantity'));
      return;
    }

    final barcode = _barcodeCtrl.text.trim();
    if (barcode.isNotEmpty && !BarcodeHelper.isValidBarcode(barcode)) {
      _showError(t('invalid_barcode_format'));
      return;
    }

    if (_barcodeExists && _existingBarcodeProduct != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(t('barcode_exists')),
          content: Text(
            '${t('product_with_barcode_exists')}: ${_existingBarcodeProduct!['name']}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('continue_anyway')),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = connectivity != ConnectivityResult.none;

    if (!isOnline) {
      await OfflineService.addPending({
        'name': name,
        'price': price,
        'quantity': qty,
        'description': _descCtrl.text.trim(),
        'barcode': barcode,
        'category_ids': _categoryIds,
        'image_paths': _newImages.map((f) => f.path).toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('offline_saved')),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(12),
          ),
        );
        Navigator.pop(context);
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> result;
      if (widget.product != null) {
        result = await ApiService.updateProduct(
          id: widget.product!['id'],
          name: name,
          price: price,
          quantity: qty,
          description: _descCtrl.text.trim(),
          barcode: barcode,
          categoryId: _categoryIds.isNotEmpty ? _categoryIds.first : null,
          image: _newImages.isNotEmpty ? _newImages.first : null,
          extraImages: _newImages.length > 1 ? _newImages.sublist(1) : null,
          existingImages: _existingImages,
        );
      } else {
        result = await ApiService.createProduct(
          name: name,
          price: price,
          quantity: qty,
          description: _descCtrl.text.trim(),
          barcode: barcode,
          categoryId: _categoryIds.isNotEmpty ? _categoryIds.first : null,
          image: _newImages.isNotEmpty ? _newImages.first : null,
          extraImages: _newImages.length > 1 ? _newImages.sublist(1) : null,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.product != null ? t('updated') : t('saved')),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(12),
          ),
        );
        Navigator.pop(context, result);
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    IconData icon,
    String title,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _modernInputDecoration(
    BuildContext context,
    String label, {
    IconData? icon,
    String? helper,
  }) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(14);
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: icon != null
          ? Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant)
          : null,
      filled: true,
      fillColor: theme.brightness == Brightness.light
          ? Colors.grey.shade50
          : Colors.grey.shade900.withOpacity(0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.product != null;
    final isRTL = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.light
          ? const Color(0xFFF8F9FA)
          : theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        title: Text(
          isEdit ? t('edit_product') : t('add_product'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Images Section ──
                    _buildSectionHeader(
                      context,
                      Icons.image_outlined,
                      t('product_images'),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: ProductImageGallery(
                        existingUrls: _existingImages,
                        newFiles: _newImages,
                        onNewFilesChanged: _handleNewImages,
                        onExistingRemoved: _handleExistingRemoved,
                        maxImages: _maxImagesPerProduct,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Basic Info Section ──
                    _buildSectionHeader(
                      context,
                      Icons.info_outline,
                      t('basic_info'),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Name
                          TextFormField(
                            controller: _nameCtrl,
                            textDirection: TextDirection.ltr,
                            textAlign: isRTL ? TextAlign.right : TextAlign.left,
                            decoration: _modernInputDecoration(
                              context,
                              '${t('product_name')} *',
                              icon: Icons.label_outline,
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return t('name_required');
                              if (v.trim().length < 2)
                                return t('name_too_short');
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Price & Quantity Row
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _priceCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]'),
                                    ),
                                  ],
                                  decoration: _modernInputDecoration(
                                    context,
                                    '${t('price')} *',
                                    icon: Icons.attach_money,
                                    helper: t('price_helper'),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty)
                                      return t('price_required');
                                    final parsed = double.tryParse(
                                      v.trim().replaceAll(',', '.'),
                                    );
                                    if (parsed == null)
                                      return t('invalid_price');
                                    if (parsed < 0)
                                      return t('negative_price_not_allowed');
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _qtyCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: _modernInputDecoration(
                                    context,
                                    t('quantity'),
                                    icon: Icons.format_list_numbered,
                                    helper: t('quantity_helper'),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty)
                                      return null;
                                    final parsed = int.tryParse(v.trim());
                                    if (parsed == null)
                                      return t('invalid_quantity');
                                    if (parsed < 0)
                                      return t('negative_quantity_not_allowed');
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Categorization Section ──
                    _buildSectionHeader(
                      context,
                      Icons.category_outlined,
                      t('categorization'),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CategoryPicker(
                            selectedIds: _categoryIds,
                            onChanged: (ids) =>
                                setState(() => _categoryIds = ids),
                            multiSelect: true,
                          ),
                          const SizedBox(height: 16),
                          BarcodeField(
                            initialValue: _barcodeCtrl.text,
                            onChanged: (code) {
                              _barcodeCtrl.text = code;
                              _checkBarcode(code);
                            },
                            validator: (v) {
                              if (v != null &&
                                  v.isNotEmpty &&
                                  !BarcodeHelper.isValidBarcode(v)) {
                                return t('invalid_barcode_format');
                              }
                              return null;
                            },
                          ),
                          if (_barcodeExists)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.orange.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: Colors.orange.shade800,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '${t('barcode_exists_warning')}: ${_existingBarcodeProduct?['name'] ?? ''}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.orange.shade900,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Description Section ──
                    _buildSectionHeader(
                      context,
                      Icons.description_outlined,
                      t('details'),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: TextFormField(
                        controller: _descCtrl,
                        maxLines: 5,
                        textDirection: TextDirection.ltr,
                        textAlign: isRTL ? TextAlign.right : TextAlign.left,
                        decoration: _modernInputDecoration(
                          context,
                          t('description'),
                          icon: Icons.notes,
                        ).copyWith(alignLabelWithHint: true),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Submit Button ──
                    GradientButton(
                      onPressed: _isLoading ? null : _save,
                      isLoading: _isLoading,
                      child: Text(
                        isEdit ? t('update_product') : t('add_product'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _descCtrl.dispose();
    _barcodeCtrl.dispose();
    super.dispose();
  }
}
