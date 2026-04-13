import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:dio/dio.dart';
import '../api_config.dart';

/// Detects harsh driving events using phone accelerometer.
/// Events are batched and sent to the backend every 60 seconds.
/// Battery-friendly: ~1-2% per hour, runs only when ignition is ON.
class BehaviorService {
  static final BehaviorService _instance = BehaviorService._internal();
  factory BehaviorService() => _instance;
  BehaviorService._internal();

  StreamSubscription? _accelSubscription;
  Timer? _batchTimer;
  bool _isRunning = false;

  // Current job context
  String? _jobId;
  double _currentSpeedKmh = 0;
  double _currentLat = 0;
  double _currentLng = 0;

  // Event buffer (batched, sent every 60s)
  final List<Map<String, dynamic>> _eventBuffer = [];

  // Thresholds (tuned for Indian roads)
  static const double _harshBrakeThresholdG = 0.35;   // -0.35g
  static const double _harshAccelThresholdG = 0.30;    // +0.30g
  static const double _sharpTurnThresholdG = 0.35;     // lateral 0.35g

  // Cooldown: ignore events within 3s of last event (same type)
  final Map<String, DateTime> _lastEventTime = {};
  static const Duration _cooldown = Duration(seconds: 3);

  // Gravity baseline (calibrated from first few readings)
  double _gravityX = 0, _gravityY = 0, _gravityZ = 9.81;
  bool _calibrated = false;
  int _calibrationSamples = 0;
  double _calSumX = 0, _calSumY = 0, _calSumZ = 0;
  static const int _calibrationCount = 50; // ~1 second at 50Hz

  /// Start listening to accelerometer. Call when ignition turns ON.
  void start({required String jobId}) {
    if (_isRunning) return;
    _isRunning = true;
    _jobId = jobId;
    _calibrated = false;
    _calibrationSamples = 0;
    _calSumX = 0;
    _calSumY = 0;
    _calSumZ = 0;
    _eventBuffer.clear();
    _lastEventTime.clear();

    debugPrint("[behavior] Starting accelerometer for job $jobId");

    _accelSubscription = userAccelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 40), // 25Hz
    ).listen(_onAccelData);

    // Batch send every 60 seconds
    _batchTimer = Timer.periodic(const Duration(seconds: 60), (_) => _flushEvents());
  }

  /// Stop listening. Call when ignition turns OFF or app backgrounds.
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    debugPrint("[behavior] Stopping accelerometer");

    _accelSubscription?.cancel();
    _accelSubscription = null;
    _batchTimer?.cancel();
    _batchTimer = null;

    // Flush remaining events
    _flushEvents();
  }

  /// Update vehicle state from SSE stream (call on every SSE update)
  void updateVehicleState({
    required double speedKmh,
    required double lat,
    required double lng,
  }) {
    _currentSpeedKmh = speedKmh;
    _currentLat = lat;
    _currentLng = lng;
  }

  void _onAccelData(UserAccelerometerEvent event) {
    // userAccelerometerEvent already has gravity removed
    // x = lateral (left/right), y = longitudinal (forward/back), z = vertical

    final double ax = event.x; // lateral
    final double ay = event.y; // longitudinal
    final double az = event.z; // vertical

    // Use magnitude to be orientation-independent
    // total = sqrt(x^2 + y^2 + z^2) — but we also check individual axes
    // For orientation-independent detection, use total magnitude
    final double totalG = math.sqrt(ax * ax + ay * ay + az * az) / 9.81;

    // Only detect events when vehicle is actually moving (> 5 km/h)
    if (_currentSpeedKmh < 5) return;

    final now = DateTime.now();

    // Longitudinal deceleration (harsh braking)
    // userAccelerometerEvent: positive y = device moves forward, negative y = deceleration
    // But since phone orientation varies, use total magnitude for reliability
    if (totalG > _harshBrakeThresholdG) {
      // Determine event type based on the dominant axis
      final absX = ax.abs();
      final absY = ay.abs();

      String eventType;
      double gForce;

      if (absX > absY && absX / 9.81 > _sharpTurnThresholdG) {
        // Lateral dominant → sharp turn
        eventType = 'sharp_turn';
        gForce = absX / 9.81;
      } else if (ay < 0 && absY / 9.81 > _harshBrakeThresholdG) {
        // Negative longitudinal → harsh brake
        eventType = 'harsh_brake';
        gForce = absY / 9.81;
      } else if (ay > 0 && absY / 9.81 > _harshAccelThresholdG) {
        // Positive longitudinal → harsh acceleration
        eventType = 'harsh_accel';
        gForce = absY / 9.81;
      } else if (totalG > _harshBrakeThresholdG) {
        // Can't determine axis confidently, classify by magnitude
        eventType = 'harsh_brake'; // default to brake (most safety-critical)
        gForce = totalG;
      } else {
        return; // Below all thresholds
      }

      // Cooldown check
      final lastTime = _lastEventTime[eventType];
      if (lastTime != null && now.difference(lastTime) < _cooldown) return;

      _lastEventTime[eventType] = now;

      // Severity: 0.0 to 1.0 scale
      double severity;
      if (eventType == 'harsh_brake') {
        severity = ((gForce - _harshBrakeThresholdG) / (1.0 - _harshBrakeThresholdG)).clamp(0.0, 1.0);
      } else if (eventType == 'harsh_accel') {
        severity = ((gForce - _harshAccelThresholdG) / (0.8 - _harshAccelThresholdG)).clamp(0.0, 1.0);
      } else {
        severity = ((gForce - _sharpTurnThresholdG) / (0.8 - _sharpTurnThresholdG)).clamp(0.0, 1.0);
      }

      _eventBuffer.add({
        'event_type': eventType,
        'g_force': double.parse(gForce.toStringAsFixed(3)),
        'severity': double.parse(severity.toStringAsFixed(2)),
        'speed_kmh': _currentSpeedKmh,
        'latitude': _currentLat,
        'longitude': _currentLng,
        'confidence': 'single',
        'event_time': now.toIso8601String(),
      });

      debugPrint("[behavior] Detected $eventType: ${gForce.toStringAsFixed(2)}g at ${_currentSpeedKmh.toStringAsFixed(0)} km/h");
    }
  }

  /// Send buffered events to backend
  Future<void> _flushEvents() async {
    if (_eventBuffer.isEmpty || _jobId == null) return;

    final eventsToSend = List<Map<String, dynamic>>.from(_eventBuffer);
    _eventBuffer.clear();

    try {
      await ApiConfig.dio.post(
        '/driver/jobs/$_jobId/behavior-events',
        data: {'events': eventsToSend},
      );
      debugPrint("[behavior] Flushed ${eventsToSend.length} events");
    } catch (e) {
      debugPrint("[behavior] Failed to flush events: $e");
      // Don't re-queue — drop silently to avoid memory growth
    }
  }

  bool get isRunning => _isRunning;
}
