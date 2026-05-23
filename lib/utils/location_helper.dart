//location_helper.dart
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';

class LocationHelper {
  /// Calculate distance between two coordinates using Haversine formula
  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Earth radius in km
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _rad(double deg) => deg * pi / 180.0;

  /// Get current GPS position
  static Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      return null;
    }
  }

  /// Reverse geocode to canonical city ID using backend API
  static Future<Map<String, dynamic>?> reverseGeocodeCanonical(
    double lat,
    double lng, {
    String lang = 'en',
  }) async {
    try {
      return await ApiService.reverseGeocode(lat, lng, lang);
    } catch (e) {
      return null;
    }
  }
}
