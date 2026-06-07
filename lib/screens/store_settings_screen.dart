import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../lang/translations.dart';
import '../providers/store_provider.dart';
import '../services/api_service.dart';
import '../services/store_service.dart';
import '../services/offline_service.dart';
import '../services/auth_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/cached_image.dart';
import 'map_picker_screen.dart';
import 'main_nav_screen.dart';

class StoreSettingsScreen extends ConsumerStatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  ConsumerState<StoreSettingsScreen> createState() =>
      _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends ConsumerState<StoreSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _isOwner = false;
  double? _lat;
  double? _lng;
  File? _newImage;
  String? _currentImageUrl;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _descriptionCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final isOwner = await ApiService.isStoreOwner();
    if (!mounted) return;

    if (!isOwner) {
      setState(() {
        _isOwner = false;
        _loading = false;
      });
      return;
    }

    try {
      final store = await StoreService.getMyStore();
      final cached = store.intId != null
          ? await OfflineService.getCachedStore(storeId: store.intId)
          : await OfflineService.getCachedStore();
      if (!mounted) return;
      setState(() {
        _isOwner = true;
        _nameCtrl.text = store.name ?? '';
        _phoneCtrl.text = store.phone ?? '';
        _cityCtrl.text = store.city ?? '';
        _descriptionCtrl.text =
            cached?['location_description']?.toString() ??
            store.village ??
            '';
        _countryCtrl.text = store.country ?? '';
        _lat = store.lat;
        _lng = store.lng;
        _currentImageUrl = store.imageUrl;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (file != null && mounted) {
      setState(() => _newImage = File(file.path));
    }
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerScreen()),
    );
    if (result != null && mounted) {
      setState(() {
        _lat = result.latitude;
        _lng = result.longitude;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await StoreService.updateMyStore(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        locationDescription: _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
        country: _countryCtrl.text.trim(),
        lat: _lat,
        lng: _lng,
        image: _newImage,
      );
      await ref.read(storeProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('settings_saved') ?? 'Settings saved'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(t('store_settings') ?? 'Store Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isOwner) {
      return Scaffold(
        appBar: AppBar(title: Text(t('store_settings') ?? 'Store Settings')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              t('owner_only') ?? 'Only store owners can change these settings.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t('store_settings') ?? 'Store Settings'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(t('save') ?? 'Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _newImage != null
                          ? Image.file(
                              _newImage!,
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                            )
                          : CachedAppImage(
                              imageUrl: _currentImageUrl,
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                              memCacheWidth: 240,
                              borderRadius: BorderRadius.circular(16),
                            ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 18,
                        child: Icon(Icons.camera_alt, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                t('tap_to_change_image') ?? 'Tap to change store image',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: '${t('store_name') ?? 'Store name'} *',
                prefixIcon: const Icon(Icons.store),
                border: const OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? t('required') ?? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: t('store_phone') ?? 'Store phone',
                prefixIcon: const Icon(Icons.phone),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cityCtrl,
              decoration: InputDecoration(
                labelText: '${t('city') ?? 'City'} *',
                prefixIcon: const Icon(Icons.location_city),
                border: const OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? t('required') ?? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText:
                    '${t('description') ?? 'Description'} (${t('optional') ?? 'optional'})',
                hintText:
                    t('location_hint') ??
                    'e.g. Next to Al-Fayhaa Market, Main Street',
                prefixIcon: const Icon(Icons.notes),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _countryCtrl,
              decoration: InputDecoration(
                labelText: '${t('country') ?? 'Country'} *',
                prefixIcon: const Icon(Icons.public),
                border: const OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? t('required') ?? 'Required' : null,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickLocation,
              icon: const Icon(Icons.map),
              label: Text(t('pick_store_location') ?? 'Pick store location'),
            ),
            if (_lat != null && _lng != null) ...[
              const SizedBox(height: 8),
              Text(
                '${t('location') ?? 'Location'}: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(t('save_settings') ?? 'Save Settings'),
              ),
            ),
            const SizedBox(height: 32),
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('danger_zone') ?? 'Danger Zone',
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t('delete_account_hint') ??
                          'Permanently delete your account and all associated data.',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _confirmDeleteAccount,
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      label: Text(
                        t('delete_account') ?? 'Delete Account',
                        style: const TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('delete_account') ?? 'Delete Account'),
        content: Text(
          t('delete_account_confirm') ??
              'Are you sure you want to delete your account? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('cancel') ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              t('confirm') ?? 'Confirm',
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await AuthService.deleteAccount();
      await ref.read(authProvider.notifier).logout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('account_deleted') ?? 'Account deleted'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainNavScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
}
