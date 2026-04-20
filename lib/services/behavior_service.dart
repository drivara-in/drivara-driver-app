import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../api_config.dart';

/// Detects harsh driving events using phone accelerometer.
///
/// Battery profile: ~near-zero.
///   - Accelerometer stream only subscribes while vehicle is actually moving
///     (speed ≥ 5 km/h, reported via SSE). Auto-stops after 60s of being
///     stopped so a traffic light / loading bay doesn't drain the battery.
///   - Sampled at 10Hz instead of 25Hz — harsh events last 300-500ms and are
///     still detected with margin.
///   - Events batched and sent to the backend every 60 seconds.
///   - `phone_use` is lifecycle-based (zero sensor cost).
///
/// Event types emitted:
///   - `harsh_brake`    (longitudinal ≥ 0.35g, decel)
///   - `harsh_accel`    (longitudinal ≥ 0.30g, accel)
///   - `sharp_turn`     (lateral ≥ 0.35g)         — VIOLATION
///   - `cornering`      (lateral 0.20–0.35g)      — COACH (not a violation)
///   - `lane_weaving`   (≥4 alternating micro-corrections within 10s) — COACH
///   - `phone_use`      (app backgrounded ≥10s while vehicle > 5 km/h)
class BehaviorService {
  static final BehaviorService _instance = BehaviorService._internal();
  factory BehaviorService() => _instance;
  BehaviorService._internal();

  StreamSubscription? _accelSubscription;
  Timer? _batchTimer;
  Timer? _idleStopTimer;
  bool _isRunning = false;
  bool _sensorActive = false;

  static const double _movingThresholdKmh = 5;
  static const Duration _idleGracePeriod = Duration(seconds: 60);

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
  static const double _corneringLoG = 0.20;            // soft corner start
  static const double _weavingMicroG = 0.10;           // micro-correction threshold
  static const double _weavingMicroMaxG = 0.20;        // upper bound — above this is real cornering, not weaving

  // Cooldown: ignore events within 3s of last event (same type)
  final Map<String, DateTime> _lastEventTime = {};
  static const Duration _cooldown = Duration(seconds: 3);

  // Lane-weaving detection — ring buffer of recent micro-corrections.
  // Entry: (timestamp, sign of lateral g: +1 left, -1 right)
  final List<_WeaveSample> _weaveBuffer = [];
  static const Duration _weaveWindow = Duration(seconds: 10);
  static const int _weaveMinAlternations = 4;
  static const Duration _weaveCooldown = Duration(seconds: 30);

  // Phone-use detection — when app backgrounds while vehicle is moving we
  // start a timer; on resume we emit `phone_use` if duration ≥ threshold.
  DateTime? _backgroundedAt;
  double _speedAtBackground = 0;
  double _latAtBackground = 0;
  double _lngAtBackground = 0;
  static const Duration _phoneUseMinDuration = Duration(seconds: 10);

  // Note: `userAccelerometerEventStream` already returns gravity-compensated
  // readings, so no explicit calibration pass is needed here.

  /// Start the service. Call when ignition turns ON.
  /// Note: the accelerometer stream is NOT started here — it's started on
  /// the first SSE update that shows the vehicle actually moving.
  void start({required String jobId}) {
    if (_isRunning) return;
    _isRunning = true;
    _jobId = jobId;
    _eventBuffer.clear();
    _lastEventTime.clear();
    _weaveBuffer.clear();

    debugPrint("[behavior] Service armed for job $jobId (accelerometer idle until vehicle moves)");

    // Batch send every 60 seconds (runs regardless of sensor state so any
    // phone_use / lane_weaving collected near a stop is still flushed).
    _batchTimer = Timer.periodic(const Duration(seconds: 60), (_) => _flushEvents());
  }

  /// Stop the service completely. Call when ignition turns OFF, page disposes,
  /// or app backgrounds.
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;
    debugPrint("[behavior] Service stopped");

    _stopSensor();
    _batchTimer?.cancel();
    _batchTimer = null;
    _idleStopTimer?.cancel();
    _idleStopTimer = null;

    // Flush remaining events
    _flushEvents();
  }

  /// Begin the accelerometer subscription. Idempotent.
  void _startSensor() {
    if (_sensorActive) return;
    _sensorActive = true;
    debugPrint("[behavior] Sensor ON (vehicle moving)");
    _accelSubscription = userAccelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100), // 10Hz
    ).listen(_onAccelData);
  }

  void _stopSensor() {
    if (!_sensorActive) return;
    _sensorActive = false;
    debugPrint("[behavior] Sensor OFF (vehicle idle)");
    _accelSubscription?.cancel();
    _accelSubscription = null;
  }

  /// Update vehicle state from SSE stream (call on every SSE update).
  /// Drives sensor-on/off so the accelerometer only runs while moving —
  /// this is how we keep battery impact near zero.
  void updateVehicleState({
    required double speedKmh,
    required double lat,
    required double lng,
  }) {
    _currentSpeedKmh = speedKmh;
    _currentLat = lat;
    _currentLng = lng;

    if (!_isRunning) return;

    if (speedKmh >= _movingThresholdKmh) {
      // Moving — cancel any pending idle-stop, turn sensor on.
      _idleStopTimer?.cancel();
      _idleStopTimer = null;
      _startSensor();
    } else if (_sensorActive && _idleStopTimer == null) {
      // Went stationary — schedule a one-shot stop after the grace period.
      // A short red light shouldn't bounce the sensor on/off every tick.
      _idleStopTimer = Timer(_idleGracePeriod, () {
        _stopSensor();
        _idleStopTimer = null;
      });
    }
  }

  /// Called by the page's lifecycle observer when app goes to background.
  /// We don't try to keep sensors running (battery + OS restrictions); we
  /// only remember when + how fast we were going.
  void noteBackgrounded() {
    if (_jobId == null) return;
    _backgroundedAt = DateTime.now();
    _speedAtBackground = _currentSpeedKmh;
    _latAtBackground = _currentLat;
    _lngAtBackground = _currentLng;
  }

  /// Called by the page's lifecycle observer when app returns to foreground.
  /// If the vehicle was moving when we left and the background duration is
  /// meaningful, emit a `phone_use` event.
  void noteForegrounded() {
    final bgAt = _backgroundedAt;
    if (bgAt == null || _jobId == null) return;
    _backgroundedAt = null;

    final duration = DateTime.now().difference(bgAt);
    if (_speedAtBackground < 5) return;                  // wasn't driving
    if (duration < _phoneUseMinDuration) return;         // too short to care

    // Severity: 10s → 0.1, 60s → 0.5, 120s+ → 1.0
    final severity = (duration.inSeconds / 120).clamp(0.0, 1.0);

    _eventBuffer.add({
      'event_type': 'phone_use',
      'severity': double.parse(severity.toStringAsFixed(2)),
      'duration_s': duration.inSeconds,
      'speed_kmh': _speedAtBackground,
      'latitude': _latAtBackground,
      'longitude': _lngAtBackground,
      'confidence': 'app_bg',
      'event_time': bgAt.toIso8601String(),
    });

    debugPrint("[behavior] Detected phone_use: ${duration.inSeconds}s at "
        "${_speedAtBackground.toStringAsFixed(0)} km/h");
  }

  void _onAccelData(UserAccelerometerEvent event) {
    // userAccelerometerEvent already has gravity removed
    // x = lateral (left/right), y = longitudinal (forward/back), z = vertical
    final double ax = event.x; // lateral
    final double ay = event.y; // longitudinal

    final double totalG = math.sqrt(ax * ax + ay * ay + event.z * event.z) / 9.81;

    if (_currentSpeedKmh < 5) return;

    final now = DateTime.now();
    final double lateralG = ax.abs() / 9.81;
    final double longG = ay.abs() / 9.81;

    // ── Lane weaving — track micro-corrections regardless of the main event ──
    if (lateralG >= _weavingMicroG && lateralG < _weavingMicroMaxG) {
      _trackWeaveSample(now, ax > 0 ? 1 : -1);
      _maybeEmitWeaving(now);
    }
    // Trim old samples regardless
    _weaveBuffer.removeWhere((s) => now.difference(s.ts) > _weaveWindow);

    // ── Primary event classification (priority: sharp_turn > harsh_brake > harsh_accel > cornering) ──
    String? eventType;
    double gForce = 0;

    if (lateralG >= _sharpTurnThresholdG) {
      eventType = 'sharp_turn';
      gForce = lateralG;
    } else if (ay < 0 && longG >= _harshBrakeThresholdG) {
      eventType = 'harsh_brake';
      gForce = longG;
    } else if (ay > 0 && longG >= _harshAccelThresholdG) {
      eventType = 'harsh_accel';
      gForce = longG;
    } else if (lateralG >= _corneringLoG) {
      // Softer tier — informational "cornering" nudge, not a violation.
      eventType = 'cornering';
      gForce = lateralG;
    } else if (totalG > _harshBrakeThresholdG) {
      // Fallback — couldn't classify by axis but magnitude is high
      eventType = 'harsh_brake';
      gForce = totalG;
    }

    if (eventType == null) return;

    // Cooldown check
    final lastTime = _lastEventTime[eventType];
    if (lastTime != null && now.difference(lastTime) < _cooldown) return;
    _lastEventTime[eventType] = now;

    // Severity: 0.0 to 1.0 scale
    double severity;
    switch (eventType) {
      case 'harsh_brake':
        severity = ((gForce - _harshBrakeThresholdG) / (1.0 - _harshBrakeThresholdG)).clamp(0.0, 1.0);
        break;
      case 'harsh_accel':
        severity = ((gForce - _harshAccelThresholdG) / (0.8 - _harshAccelThresholdG)).clamp(0.0, 1.0);
        break;
      case 'sharp_turn':
        severity = ((gForce - _sharpTurnThresholdG) / (0.8 - _sharpTurnThresholdG)).clamp(0.0, 1.0);
        break;
      case 'cornering':
        // Soft tier — severity is 0-1 across the 0.20-0.35g band.
        severity = ((gForce - _corneringLoG) / (_sharpTurnThresholdG - _corneringLoG)).clamp(0.0, 1.0);
        break;
      default:
        severity = 0.5;
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

  /// Append a lateral micro-correction sample and drop any that fell out of
  /// the 10s window. `dir` is the sign of lateral g (+1 left, -1 right).
  void _trackWeaveSample(DateTime now, int dir) {
    _weaveBuffer.add(_WeaveSample(now, dir));
    _weaveBuffer.removeWhere((s) => now.difference(s.ts) > _weaveWindow);
  }

  /// Emit `lane_weaving` if we've seen ≥ _weaveMinAlternations direction
  /// flips inside the window and we're not in cooldown.
  void _maybeEmitWeaving(DateTime now) {
    if (_weaveBuffer.length < _weaveMinAlternations) return;

    final last = _lastEventTime['lane_weaving'];
    if (last != null && now.difference(last) < _weaveCooldown) return;

    // Count alternating sign flips in order
    int flips = 0;
    for (int i = 1; i < _weaveBuffer.length; i++) {
      if (_weaveBuffer[i].dir != _weaveBuffer[i - 1].dir) flips++;
    }
    if (flips < _weaveMinAlternations - 1) return;

    _lastEventTime['lane_weaving'] = now;
    _eventBuffer.add({
      'event_type': 'lane_weaving',
      'severity': (flips / 8).clamp(0.2, 1.0),     // 4 flips → 0.5, 8+ → 1.0
      'g_force': null,
      'speed_kmh': _currentSpeedKmh,
      'latitude': _currentLat,
      'longitude': _currentLng,
      'confidence': 'lateral_pattern',
      'event_time': now.toIso8601String(),
    });
    debugPrint("[behavior] Detected lane_weaving: $flips flips in 10s at ${_currentSpeedKmh.toStringAsFixed(0)} km/h");

    _weaveBuffer.clear();
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

class _WeaveSample {
  final DateTime ts;
  final int dir; // +1 or -1
  _WeaveSample(this.ts, this.dir);
}
