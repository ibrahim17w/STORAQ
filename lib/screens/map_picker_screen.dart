// map_picker_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/cached_tile_provider.dart';

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  LatLng? _selectedPoint;
  LatLng? _userLocation;
  double? _userAccuracy;
  final MapController _mapController = MapController();
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    _moveToCurrentLocation();
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

      _mapController.move(latLng, 15);
      setState(() {
        _selectedPoint = latLng;
        _userLocation = latLng;
        _userAccuracy = position.accuracy;
        _locating = false;
      });
    } catch (e) {
      setState(() => _locating = false);
    }
  }

  Future<void> _goToUserLocation() async {
    if (_userLocation == null) {
      setState(() => _locating = true);
      await _moveToCurrentLocation();
    }
    if (_userLocation != null) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Store Location'),
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
          if (_selectedPoint != null)
            TextButton(
              onPressed: () => Navigator.pop(context, _selectedPoint),
              child: const Text(
                'CONFIRM',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: const LatLng(33.510414, 36.278336),
          initialZoom: 13,
          minZoom: 2,
          maxZoom: 20,
          onTap: (tapPosition, point) {
            setState(() => _selectedPoint = point);
          },
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

          if (_selectedPoint != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _selectedPoint!,
                  width: 40,
                  height: 40,
                  alignment: Alignment.topCenter,
                  child: const Icon(
                    Icons.location_pin,
                    color: Colors.red,
                    size: 40,
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: null,
    );
  }
}
