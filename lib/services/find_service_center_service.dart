import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api_config.dart';

/// Finds nearby authorised service centers for the active vehicle.
///
/// Mirrors [FindFuelService] in shape but skips the on-route filter — service
/// centers don't have to lie on the trip polyline, the driver opens this on
/// purpose when something's wrong with the truck. Backend call is the same
/// /api/places/search proxy that fuel search uses, just with a brand-aware
/// textQuery built from the vehicle's make.
class FindServiceCenterService {
  late final Dio _dio;

  FindServiceCenterService() {
    _dio = Dio();
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await ApiConfig.getAuthToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
          final orgId = await ApiConfig.storage.read(key: 'org_id');
          if (orgId != null) {
            options.headers['x-org-id'] = orgId;
          }
        }
        return handler.next(options);
      },
    ));
    _dio.options.baseUrl = ApiConfig.baseUrl;
  }

  // 50 km radius — service centers can be sparse outside metros.
  static const int SEARCH_RADIUS_METERS = 50000;

  /// `make` is the vehicle's manufacturer (Tata, Mahindra, Ashok Leyland, …).
  /// When null/empty, falls back to a generic commercial-vehicle query so the
  /// driver still gets useful results.
  Future<List<Map<String, dynamic>>> findNearby(LatLng location, {String? make}) async {
    final brand = (make ?? '').trim();
    final query = brand.isNotEmpty
        ? '$brand commercial vehicle service center'
        : 'truck service center';

    try {
      final response = await _dio.post(
        '/places/search',
        data: {
          'textQuery': query,
          'locationBias': {
            'circle': {
              'center': {
                'latitude': location.latitude,
                'longitude': location.longitude,
              },
              'radius': SEARCH_RADIUS_METERS.toDouble(),
            },
          },
          'maxResultCount': 15,
        },
      );

      if (response.statusCode != 200 || response.data['places'] == null) {
        return [];
      }

      final results = response.data['places'] as List;
      final centers = results.map<Map<String, dynamic>>((p) {
        final lat = (p['location']?['latitude'] as num?)?.toDouble();
        final lng = (p['location']?['longitude'] as num?)?.toDouble();
        return {
          'name': p['displayName']?['text'] ?? 'Service centre',
          'address': p['formattedAddress'] ?? '',
          'latitude': lat,
          'longitude': lng,
          'place_id': p['id'] ?? '',
        };
      }).where((c) => c['latitude'] != null && c['longitude'] != null).toList();

      // Annotate straight-line distance + sort nearest-first.
      for (final c in centers) {
        c['distance_km'] = _haversineKm(
          location.latitude,
          location.longitude,
          c['latitude'] as double,
          c['longitude'] as double,
        );
      }
      centers.sort((a, b) => (a['distance_km'] as double).compareTo(b['distance_km'] as double));
      return centers.take(10).toList();
    } catch (e) {
      // Caller decides how to surface the error.
      rethrow;
    }
  }

  /// Hand off navigation to Google Maps / default maps app.
  Future<bool> navigateTo(double lat, double lng, {String? label}) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const earthR = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthR * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180);
}
