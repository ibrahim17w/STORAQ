//map_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../lang/translations.dart';
import '../widgets/cached_tile_provider.dart';
import 'store_products_screen.dart';

class MapScreen extends StatefulWidget {
  final LatLng? target;
  final int? targetStoreId;
  final String? targetName;
  final String? targetImageUrl;
  final List<dynamic>? stores; // CHANGED: accept pre-loaded stores

  const MapScreen({
    super.key,
    this.target,
    this.targetStoreId,
    this.targetName,
    this.targetImageUrl,
    this.stores, // CHANGED
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<dynamic> _stores = [];
  LatLng? _userLocation;
  double? _userAccuracy;
  bool _locating = true;

  @override
  void initState() {
    super.initState();

    // Use passed stores if available and non-empty
    if (widget.stores != null && widget.stores!.isNotEmpty) {
      _stores = widget.stores!
          .where((s) => s['lat'] != null && s['lng'] != null)
          .toList();
    }

    if (widget.target == null) {
      _moveToCurrentLocation();
    } else {
      setState(() => _locating = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.target != null) {
          _mapController.move(widget.target!, 16);
        }
      });
    }

    // ALWAYS fetch from network as fallback/refresh, even if stores were passed
    // This ensures we have data even if the passed list was empty
    _loadStores();
  }

  Future<void> _moveToCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locating = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _locating = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _locating = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final latLng = LatLng(position.latitude, position.longitude);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(latLng, 14);
      });

      setState(() {
        _userLocation = latLng;
        _userAccuracy = position.accuracy;
        _locating = false;
      });
    } catch (e) {
      setState(() => _locating = false);
    }
  }

  Future<void> _loadStores() async {
    try {
      final stores = await ApiService.fetchStores();
      if (mounted) {
        setState(() {
          _stores = stores
              .where((s) => s['lat'] != null && s['lng'] != null)
              .toList();
        });
      }
    } catch (e) {
      print('>>> MapScreen _loadStores error: $e');
      // Don't crash — just show empty state
      if (mounted) {
        setState(() {
          // Keep whatever we have, or empty if nothing
        });
      }
    }
  }

  Future<void> _goToUserLocation() async {
    if (_userLocation == null) {
      if (mounted) setState(() => _locating = true);
      await _moveToCurrentLocation();
    }
    if (_userLocation != null && mounted) {
      _mapController.move(_userLocation!, 16);
    }
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(
      _mapController.camera.center,
      (currentZoom + 1).clamp(2, 20),
    );
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(
      _mapController.camera.center,
      (currentZoom - 1).clamp(2, 20),
    );
  }

  // CHANGED: search the loaded list for the store we want to display
  dynamic _findTargetStore() {
    if (widget.target == null && widget.targetStoreId == null) return null;

    for (final store in _stores) {
      // 1) Match by ID (most reliable)
      if (widget.targetStoreId != null) {
        final rawId = store['id'];
        final sid = rawId is int ? rawId : int.tryParse(rawId.toString());
        if (sid == widget.targetStoreId) return store;
      }

      // 2) Match by coordinates (0.001° ≈ 111 m tolerance)
      if (widget.target != null) {
        final lat = double.tryParse(store['lat'].toString());
        final lng = double.tryParse(store['lng'].toString());
        if (lat != null && lng != null) {
          if ((lat - widget.target!.latitude).abs() <= 0.001 &&
              (lng - widget.target!.longitude).abs() <= 0.001) {
            return store;
          }
        }
      }
    }
    return null;
  }

  double _haversineKm(LatLng p1, LatLng p2) {
    const R = 6371.0;
    final dLat = _rad(p2.latitude - p1.latitude);
    final dLon = _rad(p2.longitude - p1.longitude);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(p1.latitude)) *
            cos(_rad(p2.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _rad(double deg) => deg * pi / 180.0;

  String? _getDistance(dynamic store) {
    if (_userLocation == null) return null;

    final storeLat = double.tryParse(store['lat'].toString());
    final storeLng = double.tryParse(store['lng'].toString());
    if (storeLat == null || storeLng == null) return null;

    final storePoint = LatLng(storeLat, storeLng);
    final distanceKm = _haversineKm(_userLocation!, storePoint);

    if (distanceKm < 0.01) {
      return '< 1 m';
    } else if (distanceKm < 1.0) {
      return '${(distanceKm * 1000).toStringAsFixed(0)} m';
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final bool isPushedForStore = widget.target != null;

    // CHANGED: find the real store from the list, extract name + image
    final matchedStore = _findTargetStore();

    final String displayName =
        (matchedStore != null &&
            matchedStore['name'] != null &&
            matchedStore['name'].toString().trim().isNotEmpty)
        ? matchedStore['name'].toString()
        : (widget.targetName?.trim().isNotEmpty == true
              ? widget.targetName!
              : t('store_location'));

    final String? displayImageUrl =
        (matchedStore != null &&
            matchedStore['image_url'] != null &&
            matchedStore['image_url'].toString().trim().isNotEmpty)
        ? matchedStore['image_url'].toString()
        : widget.targetImageUrl;

    final String? targetDistance = matchedStore != null
        ? _getDistance(matchedStore)
        : null;

    print(
      '>>> MapScreen BUILD: displayName="$displayName", matchedStore=${matchedStore != null}, storesCount=${_stores.length}',
    );

    return PopScope(
      canPop: isPushedForStore,
      child: Scaffold(
        appBar: AppBar(
          leading: isPushedForStore
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                )
              : null,
          automaticallyImplyLeading: false,
          title: Text(isPushedForStore ? displayName : t('explore')),
          actions: [
            if (_locating)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Zoom in',
                onPressed: _zoomIn,
              ),
              IconButton(
                icon: const Icon(Icons.remove),
                tooltip: 'Zoom out',
                onPressed: _zoomOut,
              ),
              IconButton(
                icon: const Icon(Icons.my_location),
                tooltip: 'My location',
                onPressed: _goToUserLocation,
              ),
            ],
          ],
        ),
        body: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.target ?? const LatLng(33.510414, 36.278336),
            initialZoom: widget.target != null ? 16 : 13,
            minZoom: 2,
            maxZoom: 20,
            cameraConstraint: CameraConstraint.contain(
              bounds: LatLngBounds(
                const LatLng(-85.05112877980659, -180),
                const LatLng(85.05112877980659, 180),
              ),
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              maxZoom: 20,
              tileProvider: CachedNetworkTileProvider(),
            ),

            if (_userLocation != null &&
                _userAccuracy != null &&
                _userAccuracy! > 0)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _userLocation!,
                    radius: _userAccuracy!,
                    useRadiusInMeter: true,
                    color: Colors.blue.withOpacity(0.15),
                    borderColor: Colors.blue.withOpacity(0.4),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),

            if (_userLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _userLocation!,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.4),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.navigation,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

            MarkerLayer(
              markers: _stores
                  .where((store) {
                    if (widget.targetStoreId != null &&
                        store['id'] == widget.targetStoreId) {
                      return false;
                    }
                    return true;
                  })
                  .map((store) {
                    final lat = double.tryParse(store['lat'].toString()) ?? 0;
                    final lng = double.tryParse(store['lng'].toString()) ?? 0;
                    final isTarget =
                        widget.target != null &&
                        (lat - widget.target!.latitude).abs() < 0.0001 &&
                        (lng - widget.target!.longitude).abs() < 0.0001;
                    final imageUrl = store['image_url'] as String?;
                    final distanceText = _getDistance(store);

                    return Marker(
                      point: LatLng(lat, lng),
                      width: 140,
                      height: 110,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                StoreProductsScreen(storeId: store['id']),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isTarget
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    store['name'] ?? t('store'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isTarget
                                          ? Colors.white
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                    ),
                                  ),
                                  if (distanceText != null)
                                    Text(
                                      distanceText,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: isTarget
                                            ? Colors.white70
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey.shade200,
                                border: Border.all(
                                  color: isTarget
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: imageUrl != null && imageUrl.isNotEmpty
                                    ? Image.network(
                                        imageUrl,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                              Icons.store,
                                              size: 24,
                                              color: Colors.grey,
                                            ),
                                      )
                                    : const Icon(
                                        Icons.store,
                                        size: 24,
                                        color: Colors.grey,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  })
                  .toList(),
            ),

            if (widget.target != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.target!,
                    width: 140,
                    height: 110,
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              if (targetDistance != null)
                                Text(
                                  targetDistance,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white70,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade200,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child:
                                displayImageUrl != null &&
                                    displayImageUrl.isNotEmpty
                                ? Image.network(
                                    displayImageUrl,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.store,
                                      size: 24,
                                      color: Colors.grey,
                                    ),
                                  )
                                : const Icon(
                                    Icons.store,
                                    size: 24,
                                    color: Colors.grey,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        floatingActionButton: null,
      ),
    );
  }
}
