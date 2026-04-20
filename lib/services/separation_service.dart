import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../api_config.dart';

/// Watches the distance between the driver's phone and the vehicle they're
/// assigned to. Fires a critical alert when the phone is >5 km from the
/// vehicle — used to catch cases where a driver wanders off or hands the
/// truck to someone else.
///
/// Runs while a job is active, including when the app is backgrounded:
///   - Android: an OS-required foreground service notification ("Drivara is
///     monitoring vehicle distance") keeps the process alive.
///   - iOS: background location mode in Info.plist keeps location updates
///     flowing; a periodic timer drives the distance check.
///
/// Stops completely when a job ends — no tracking off-duty.
///
/// Battery profile:
///   - One coarse location fix per 5 min (cell/WiFi triangulation, not GPS)
///   - One lightweight GET to fetch latest vehicle telemetry per tick
///   - Effectively <1% battery per hour of active tracking
class SeparationService {
  static final SeparationService _instance = SeparationService._internal();
  factory SeparationService() => _instance;
  SeparationService._internal();

  static const double _thresholdKm = 5.0;
  static const Duration _pollInterval = Duration(minutes: 5);
  static const Duration _escalationAfter = Duration(minutes: 2);
  static const Duration _breachCooldown = Duration(minutes: 30);

  String? _jobId;
  bool _isRunning = false;
  Timer? _pollTimer;
  StreamSubscription<Position>? _positionStream;

  // Latest vehicle position — seeded from SSE when the page is foreground,
  // refreshed from backend every tick so we still work when backgrounded.
  double? _vehicleLat;
  double? _vehicleLng;

  // Breach state machine
  DateTime? _breachStart;
  bool _breachReported = false;
  bool _escalationReported = false;
  DateTime? _lastResolvedAt;

  /// Start monitoring. Call when a job becomes active. Safe to call repeatedly.
  Future<void> start({required String jobId}) async {
    if (_isRunning) return;
    _isRunning = true;
    _jobId = jobId;
    _breachStart = null;
    _breachReported = false;
    _escalationReported = false;

    final granted = await _ensurePermissions();
    if (!granted) {
      debugPrint("[separation] Location permission not granted — service idle");
      _isRunning = false;
      return;
    }

    debugPrint("[separation] Service armed for job $jobId");

    // On Android, subscribe to getPositionStream with a ForegroundNotificationConfig
    // so the OS keeps the process alive while backgrounded. We ignore the
    // stream's own callbacks; our distance check is driven by the timer below.
    if (Platform.isAndroid) {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.low,
          distanceFilter: 500,
          intervalDuration: const Duration(minutes: 5),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: "Drivara",
            notificationText: "Monitoring distance from your assigned vehicle",
            notificationIcon: AndroidResource(name: 'launcher_icon', defType: 'mipmap'),
            enableWakeLock: false,
          ),
        ),
      ).listen((_) {}, onError: (e) => debugPrint("[separation] stream error: $e"));
    } else if (Platform.isIOS) {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: AppleSettings(
          accuracy: LocationAccuracy.low,
          distanceFilter: 500,
          pauseLocationUpdatesAutomatically: true,
          showBackgroundLocationIndicator: false,
        ),
      ).listen((_) {}, onError: (e) => debugPrint("[separation] stream error: $e"));
    }

    // Fire the first check immediately, then every 5 min thereafter.
    _tick();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _tick());
  }

  /// Tear down completely. Call when the job ends, the driver logs out, or the
  /// assigned page disposes permanently. Idempotent.
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _positionStream?.cancel();
    _positionStream = null;
    _breachStart = null;
    _breachReported = false;
    _escalationReported = false;
    _vehicleLat = null;
    _vehicleLng = null;
    _jobId = null;
    debugPrint("[separation] Service stopped");
  }

  bool get isRunning => _isRunning;

  /// Seed vehicle location from the SSE stream when available. Keeps the
  /// first-tick check accurate without waiting for a backend round-trip.
  void updateVehicleLocation({required double lat, required double lng}) {
    _vehicleLat = lat;
    _vehicleLng = lng;
  }

  Future<bool> _ensurePermissions() async {
    // Step 1: require whenInUse first.
    if (!(await Permission.locationWhenInUse.request()).isGranted) return false;
    // Step 2: escalate to always for background operation.
    final always = await Permission.locationAlways.request();
    return always.isGranted;
  }

  Future<void> _tick() async {
    if (!_isRunning || _jobId == null) return;

    // Always refresh vehicle location from the backend so we work when
    // backgrounded (SSE isn't running then).
    await _refreshVehicleLocation();
    if (_vehicleLat == null || _vehicleLng == null) {
      debugPrint("[separation] No vehicle location available, skipping check");
      return;
    }

    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (e) {
      debugPrint("[separation] getCurrentPosition failed: $e");
      return;
    }

    final distanceKm = _haversineKm(
      pos.latitude, pos.longitude, _vehicleLat!, _vehicleLng!,
    );
    debugPrint("[separation] driver↔vehicle = ${distanceKm.toStringAsFixed(2)} km");

    if (distanceKm <= _thresholdKm) {
      if (_breachReported) {
        _lastResolvedAt = DateTime.now();
        debugPrint("[separation] Breach resolved");
      }
      _breachStart = null;
      _breachReported = false;
      _escalationReported = false;
      return;
    }

    // Breach
    _breachStart ??= DateTime.now();
    if (_lastResolvedAt != null &&
        DateTime.now().difference(_lastResolvedAt!) < _breachCooldown &&
        !_breachReported) {
      debugPrint("[separation] Breach suppressed by cooldown");
      return;
    }
    final breachDuration = DateTime.now().difference(_breachStart!);

    if (!_breachReported) {
      await _post({
        'event': 'breach_start',
        'distanceKm': distanceKm,
        'driverLat': pos.latitude,
        'driverLng': pos.longitude,
        'vehicleLat': _vehicleLat!,
        'vehicleLng': _vehicleLng!,
        'breachStart': _breachStart!.toIso8601String(),
      });
      _breachReported = true;
      return;
    }

    if (!_escalationReported && breachDuration >= _escalationAfter) {
      await _post({
        'event': 'breach_escalate',
        'distanceKm': distanceKm,
        'driverLat': pos.latitude,
        'driverLng': pos.longitude,
        'vehicleLat': _vehicleLat!,
        'vehicleLng': _vehicleLng!,
        'breachStart': _breachStart!.toIso8601String(),
        'durationMin': breachDuration.inMinutes,
      });
      _escalationReported = true;
    }
  }

  Future<void> _refreshVehicleLocation() async {
    try {
      final res = await ApiConfig.dio.get('/driver/jobs/$_jobId/vehicle-location');
      final lat = (res.data?['lat'] as num?)?.toDouble();
      final lng = (res.data?['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        _vehicleLat = lat;
        _vehicleLng = lng;
      }
    } catch (e) {
      // Network failure — keep using cached vehicle location if we have one.
      debugPrint("[separation] vehicle-location fetch failed: $e");
    }
  }

  Future<void> _post(Map<String, dynamic> body) async {
    try {
      await ApiConfig.dio.post('/driver/jobs/$_jobId/separation', data: body);
      debugPrint("[separation] Posted ${body['event']}: ${body['distanceKm']}km");
    } catch (e) {
      debugPrint("[separation] POST failed: $e");
    }
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180.0);
}
