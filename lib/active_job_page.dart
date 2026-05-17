import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:drivara_driver_app/widgets/live_job_map.dart';
import 'package:drivara_driver_app/widgets/tank_history_sheet.dart';
import 'package:lottie/lottie.dart';
import 'package:drivara_driver_app/widgets/route_timeline.dart';
import 'package:drivara_driver_app/widgets/add_expense_sheet.dart';
import 'package:drivara_driver_app/widgets/expense_list_sheet.dart';
import 'package:drivara_driver_app/widgets/action_button_card.dart';
import 'package:drivara_driver_app/widgets/stop_action_sheet.dart';
import 'package:drivara_driver_app/widgets/stoppage_reason_sheet.dart';
import 'package:drivara_driver_app/services/behavior_service.dart';
import 'package:drivara_driver_app/services/separation_service.dart';
import 'package:drivara_driver_app/services/messaging_service.dart';
import 'package:drivara_driver_app/pages/tyre_management_page.dart';
import 'package:drivara_driver_app/pages/earnings_page.dart';
import 'package:drivara_driver_app/pages/settlement_sheet.dart';
import 'package:drivara_driver_app/pages/profile_page.dart';
import 'leaderboard_page.dart';
import 'api_config.dart';
import 'providers/localization_provider.dart';
import 'no_job_page.dart';
import 'login_page.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'services/job_stream_service.dart';
import 'services/find_fuel_service.dart';
import 'services/notification_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

double get kAllowedActionRadiusKm {
  final val = dotenv.env['ALLOWED_ACTION_RADIUS_KM'];
  if (val != null) {
     return double.tryParse(val) ?? 75.0;
  }
  return 75.0;
}

class ActiveJobPage extends StatefulWidget {
  final Map<String, dynamic> job;
  const ActiveJobPage({super.key, required this.job});

  @override
  State<ActiveJobPage> createState() => _ActiveJobPageState();
}

class _ActiveJobPageState extends State<ActiveJobPage> with WidgetsBindingObserver {
  late Map<String, dynamic> _job;
  Map<String, dynamic>? _dashboardData;
  Timer? _poller;
  StreamSubscription? _streamSubscription;
  
  // State variables for UI
  bool _isLoading = false;
  bool _isActionLoading = false;
  int? _selectedStopIndex;
  List<Map<String, dynamic>>? _fuelStations;

  // Fuel-pump proximity state. We compute distance from the live GPS to the
  // first planned fuel stop on every dashboard tick / SSE update; when the
  // truck crosses the 2 km threshold for a given pump (identified by its
  // 4-decimal coord key) we play a one-shot haptic + system tone and show
  // the inline banner above the bottom sheet.
  double? _fuelProxKm;
  Map<String, dynamic>? _fuelProxStop;
  String? _fuelProxAlertedKey; // pump key already alerted — don't repeat
  // Persistent audio player so we pre-load the chime once and never miss
  // the playback because of construction latency on the first alert.
  final AudioPlayer _fuelChime = AudioPlayer(playerId: 'fuel-proximity-chime');
  bool _fuelChimeReady = false;

  // Driver-vs-vehicle separation. We stream the driver's own GPS via
  // geolocator and compare to the latest vehicle telemetry coordinates so
  // the in-app "Vehicle X km away — Navigate" banner can render in real
  // time. No push notification — the user said those add noise; the banner
  // is enough.
  StreamSubscription<Position>? _driverPosSub;
  Position? _driverPos;

  // Reminder State (retained as it's used in _connectStream)
  DateTime? _stoppedSince;
  bool _reminderSent = false;

  // Unplanned stoppage state
  DateTime? _unplannedStopSince;
  bool _stoppageReasonRequested = false;
  String? _activeStoppageId;
  bool _stoppageSheetShowing = false;

  // Driver's avatar URL (if uploaded) — used to render the Profile icon in
  // the toolbar with the actual driver's photo instead of a generic person
  // glyph. Fetched once on init via /driver/me/profile; falls back to the
  // generic icon when null/empty or before the fetch resolves.
  String? _avatarUrl;
  List<Map<String, dynamic>>? _stoppageReasons; // Fetched from API

  JobStreamService? _streamService; // Retained as it's used in _connectStream
  final GlobalKey<dynamic> _mapKey = GlobalKey(); // Using dynamic to access state methods loosely or type it if possible
  
  // Helper to safely parse numbers
  num? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService().init(); // Retained from original
    _job = widget.job;
    // _checkLocationPermission(); // This was in the provided snippet but not in original. Assuming it's a placeholder or future addition.
    _initialFetch();
    _connectStream();
    _initFuelChime();
    _initDriverGps();
  }

  Future<void> _initDriverGps() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return; // user already declined; banner stays hidden, no nag
      }
      _driverPosSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Update at most every 50 m of driver movement — enough to keep
          // the "X km away" label fresh without burning battery.
          distanceFilter: 50,
        ),
      ).listen((pos) {
        if (!mounted) return;
        setState(() => _driverPos = pos);
      }, onError: (e) => debugPrint('[driver-gps] $e'));
    } catch (e) {
      debugPrint('[driver-gps] init failed: $e');
    }
  }

  Future<void> _initFuelChime() async {
    try {
      // Pre-load the source so the first 2 km alert plays without a setup
      // delay. Notification context = audio routes through ringer/media so
      // it overrides silent-ish phones the way nav alerts do.
      await _fuelChime.setReleaseMode(ReleaseMode.stop);
      await _fuelChime.setSourceAsset('sounds/fuel_chime.wav');
      await _fuelChime.setVolume(1.0);
      await _fuelChime.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
      _fuelChimeReady = true;
    } catch (e) {
      debugPrint('Fuel chime init failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _disconnectStream();
    BehaviorService().stop();
    SeparationService().stop();
    _fuelChime.dispose();
    _driverPosSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("App Resumed: Restarting Services & Checking Job...");
      // Emit phone_use event if we were backgrounded while driving.
      BehaviorService().noteForegrounded();
      _checkGlobalJobStatus(); // Immediate check

      // Resume Services
      if (_poller == null || !_poller!.isActive) _startPolling();
      if (_streamService == null || _streamSubscription == null) _connectStream();

    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      debugPrint("App Paused: Suspending Services (Battery Saving Mode)...");
      // Record background-start so we can compute phone_use duration on resume.
      BehaviorService().noteBackgrounded();
      _stopPolling();
      _disconnectStream();
      BehaviorService().stop();
      // SeparationService intentionally keeps running — its own foreground
      // service (Android) / background location mode (iOS) drives the 5-km
      // breach alert while the app is backgrounded. It's torn down when the
      // job ends (dispose / _checkGlobalJobStatus terminal state).
    }
  }

  Future<void> _checkGlobalJobStatus() async {
      try {
          final res = await ApiConfig.dio.get('/driver/me/active-job');
          final activeJob = res.data['activeJob'];
          
          if (!mounted) return;

          // Case 1: No active job anymore -> Go to NoJobPage
          if (activeJob == null) {
              debugPrint("Job Ended/Cancelled. Redirecting to NoJobPage.");
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const NoJobPage()),
                  (route) => false
              );
              return;
          }

          // Case 2: Different Job Assigned -> Reload Page
          if (activeJob['id'] != _job['id']) {
              debugPrint("New Job Detected! Reloading.");
              Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => ActiveJobPage(job: activeJob))
              );
              return;
          }

          // Case 3: Same Job -> Just refresh dashboard data
          debugPrint("Same Job. Refreshing Data.");
          _fetchDashboardData();
          
      } catch (e) {
          debugPrint("Error checking global job status: $e");
      }
  }

  void _initialFetch() {
      // Fetch data immediately
      _fetchDashboardData();
      _startPolling();
      _fetchStoppageReasons();
      _fetchProfileAvatar();
  }

  Future<void> _fetchProfileAvatar() async {
    try {
      final res = await ApiConfig.dio.get('/driver/me/profile');
      final url = (res.data is Map) ? (res.data['avatar_url']?.toString()) : null;
      if (mounted) setState(() => _avatarUrl = (url != null && url.isNotEmpty) ? url : null);
    } catch (e) {
      // Best-effort — Profile icon falls back to the generic person glyph.
      debugPrint('[profile-avatar] fetch failed: $e');
    }
  }

  Future<void> _fetchStoppageReasons() async {
    try {
      final res = await ApiConfig.dio.get('/driver/stoppage-reasons');
      if (res.statusCode == 200 && res.data is List) {
        setState(() {
          _stoppageReasons = (res.data as List).map((r) => Map<String, dynamic>.from(r)).toList();
        });
        debugPrint("[stoppages] Fetched ${_stoppageReasons!.length} stoppage reasons from API");
      }
    } catch (e) {
      debugPrint("[stoppages] Failed to fetch reasons, using fallbacks: $e");
    }
  }

  void _startPolling() {
      _poller?.cancel(); // Safety cleanup
      // Using 30s poll as backup heartbeat
      _poller = Timer.periodic(const Duration(seconds: 30), (_) => _fetchDashboardData());
  }

  void _stopPolling() {
      _poller?.cancel();
      _poller = null;
  }
  
  void _disconnectStream() {
      _streamSubscription?.cancel();
      _streamSubscription = null;
      _streamService?.dispose();
      _streamService = null;
  }

  void _onStopTimelineTap(int index) {
     // USER REQ: If last stop load is unloaded (ready to complete), make all stops unclickable.
     if (_isReadyToComplete()) {
        if (_selectedStopIndex != null) setState(() => _selectedStopIndex = null);
        return;
     }

     setState(() {
        if (_selectedStopIndex == index) {
           _selectedStopIndex = null; // Toggle off
        } else {
           _selectedStopIndex = index;
        }
     });
  }

  bool _isReadyToComplete() {
      // Check if last stop is done (reached & action completed if applicable)
      final stops = (_job['route_stops'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (stops.isEmpty) return false;
      
      final lastStop = stops.last;
      final status = lastStop['status'];
      
      debugPrint("READY CHECK: LastStop Status=$status | Type=${lastStop['type']} | CompletedAt=${lastStop['action_completed_at']}");

      if (status == 'pending' || status == null) return false;
      
      final type = (lastStop['type'] ?? lastStop['stop_type'] ?? lastStop['activity'] ?? 'stop').toString().toLowerCase();
      if (type == 'loading' || type == 'unloading') {
          return lastStop['action_completed_at'] != null;
      }
      
      // For normal stops, if we are not pending, we assume we are reached/done.
      return true;
  }

  // Helper: Haversine Distance
  double _getHaversineDistance(double lat1, double lng1, double lat2, double lng2) {
      const R = 6371; // Radius of the earth in km
      final dLat = _deg2rad(lat2 - lat1);
      final dLng = _deg2rad(lng2 - lng1);
      final a = 
          math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) * 
          math.sin(dLng / 2) * math.sin(dLng / 2);
      final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
      return R * c;
  }

  double _deg2rad(double deg) {
      return deg * (math.pi / 180);
  }

  // Check if vehicle is near ANY planned stop (within 2km)
  bool _isNearAnyPlannedStop(Map<String, dynamic> vehicle) {
    try {
      final double vLat = _parseNum(vehicle['location']?['lat'])?.toDouble() ?? 0.0;
      final double vLng = _parseNum(vehicle['location']?['lng'])?.toDouble() ?? 0.0;
      if (vLat == 0.0 && vLng == 0.0) return true; // No GPS, assume near stop to avoid false trigger

      var stops = _job['route_stops'];
      if (stops == null) return false;
      if (stops is String) return false; // Can't parse
      final stopsList = (stops as List?) ?? [];

      for (final stop in stopsList) {
        final double sLat = double.tryParse(stop['lat']?.toString() ?? '') ?? 0.0;
        final double sLng = double.tryParse(stop['lng']?.toString() ?? '') ?? 0.0;
        if (sLat == 0.0 && sLng == 0.0) continue;
        final dist = _getHaversineDistance(vLat, vLng, sLat, sLng);
        if (dist <= 2.0) return true; // Within 2km of a planned stop
      }
    } catch (e) {
      debugPrint("Near stop check error: $e");
      return true; // On error, assume near stop to avoid false trigger
    }
    return false;
  }

  void _showStoppageReasonSheet() {
    if (!mounted || _stoppageSheetShowing) return;
    _stoppageSheetShowing = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(ctx).size.height * 0.1),
        child: StoppageReasonSheet(
          stoppedSince: _unplannedStopSince ?? DateTime.now(),
          isLoading: _isActionLoading,
          apiReasons: _stoppageReasons,
          onSubmit: (reason, notes, photoId) {
            Navigator.pop(ctx);
            _stoppageSheetShowing = false;
            _submitStoppageReason(reason, notes, photoId);
          },
        ),
      ),
    ).whenComplete(() {
      _stoppageSheetShowing = false;
    });
  }

  Future<void> _submitStoppageReason(String reason, String? notes, String? photoUploadId) async {
    try {
      final vehicle = _dashboardData?['vehicle'] ?? {};
      final lat = _parseNum(vehicle['location']?['lat'])?.toDouble();
      final lng = _parseNum(vehicle['location']?['lng'])?.toDouble();

      final response = await ApiConfig.dio.post(
        '/driver/jobs/${_job['id']}/stoppage',
        data: {
          'reason': reason,
          'notes': notes,
          'photo_upload_id': photoUploadId,
          'latitude': lat,
          'longitude': lng,
          'started_at': _unplannedStopSince?.toIso8601String() ?? DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200 && response.data?['stoppageId'] != null) {
        _activeStoppageId = response.data['stoppageId'];
        debugPrint("[stoppages] Stoppage recorded: $_activeStoppageId reason=$reason");
      }
    } catch (e) {
      debugPrint("[stoppages] Error submitting stoppage: $e");
    }
  }

  Future<void> _closeActiveStoppage() async {
    if (_activeStoppageId == null) return;
    final stoppageId = _activeStoppageId;
    try {
      await ApiConfig.dio.post('/driver/jobs/${_job['id']}/stoppage/$stoppageId/end');
      debugPrint("[stoppages] Stoppage $stoppageId closed");
    } catch (e) {
      debugPrint("[stoppages] Error closing stoppage: $e");
    }
  }

  void _connectStream() {
    _streamService = JobStreamService(jobId: _job['id']);
    _streamSubscription = _streamService!.connect().listen((data) {
        if (!mounted) return;
        debugPrint("SSE RECEIVED: $data"); // Re-enabled
        debugPrint("SSE FUEL RAW: ${data['fuel_level']}");
        setState(() {
           // Merge stream data into dashboard data structure
           // The stream payload is flat, but dashboard expects nested structure.
           // We reconstruct it to match build() expectations.
           
           // Helper to safely parse numbers from String or Num
           num? _parseNum(dynamic v) {
              if (v == null) return null;
              if (v is num) return v;
              if (v is String) return num.tryParse(v);
              return null;
           }

           // Create a NEW map copy to ensure widget.vehicle != oldWidget.vehicle in child
           final oldVehicle = _dashboardData?['vehicle'] ?? {};
           final newVehicle = Map<String, dynamic>.from(oldVehicle);

           newVehicle['location'] = {
              'lat': _parseNum(data['lat'])?.toDouble() ?? 0.0,
              'lng': _parseNum(data['lng'])?.toDouble() ?? 0.0,
              'heading': _parseNum(data['heading'])?.toDouble() ?? 0.0
           };
           newVehicle['speed_kmh'] = _parseNum(data['speed']) ?? 0;
           newVehicle['speed_kmh'] = _parseNum(data['speed']) ?? 0;
           newVehicle['odometer_km'] = data['odometer'] ?? newVehicle['odometer_km'];
           if (data['vehicleNumber'] != null) newVehicle['vehicleNumber'] = data['vehicleNumber'];
           
           if (_dashboardData == null) _dashboardData = {};
           _dashboardData!['vehicle'] = newVehicle;

           // Use newVehicle for local checks below
           final vehicle = newVehicle;

           // --- Reminder Logic ---
           try {
              final double speed = _parseNum(data['speed'])?.toDouble() ?? 0.0;
              final bool? ignition = data['ignition'] is bool ? data['ignition'] : data['ignition'].toString().toLowerCase() == 'true';
              final List actions = data['available_actions'] ?? [];

              // --- Behavior Service: accelerometer control ---
              final double bLat = _parseNum(data['lat'])?.toDouble() ?? 0.0;
              final double bLng = _parseNum(data['lng'])?.toDouble() ?? 0.0;
              if (ignition == true) {
                if (!BehaviorService().isRunning) {
                  BehaviorService().start(jobId: _job['id']);
                }
                BehaviorService().updateVehicleState(speedKmh: speed, lat: bLat, lng: bLng);
              } else {
                if (BehaviorService().isRunning) {
                  BehaviorService().stop();
                }
              }
              // --- End Behavior Service ---

              // --- Separation Service: 5km driver-vehicle distance alert ---
              if (bLat != 0.0 && bLng != 0.0) {
                if (!SeparationService().isRunning) {
                  SeparationService().start(jobId: _job['id']);
                }
                SeparationService().updateVehicleLocation(lat: bLat, lng: bLng);
              }
              // --- End Separation Service ---

              // User definition: Stopped = Ignition OFF
              // Strictly check ignition.
              bool isStopped = (ignition == false);

              if (isStopped && actions.isNotEmpty) {
                  final action = actions.first;
                  // Distance Check
                  bool withinRadius = false;
                  try { 
                      final stopIdx = action['stopIndex'];
                      if (stopIdx != null) {
                           // Ensure stops is a list
                           var stops = _job['route_stops'];
                           if (stops is String) {
                               // JSON decode if needed, though _job usually has objects if passed from parent
                           }
                           // Assuming normalized structure in _job
                           final stopsList = (stops as List?) ?? [];
                           
                           if (stopIdx < stopsList.length) {
                               final stop = stopsList[stopIdx];
                               final double vLat = _parseNum(vehicle['location']['lat'])?.toDouble() ?? 0.0;
                               final double vLng = _parseNum(vehicle['location']['lng'])?.toDouble() ?? 0.0;
                               final double sLat = double.tryParse(stop['lat'].toString()) ?? 0.0;
                               final double sLng = double.tryParse(stop['lng'].toString()) ?? 0.0;
                               
                               final dist = _getHaversineDistance(vLat, vLng, sLat, sLng);
                               if (dist <= kAllowedActionRadiusKm) {
                                   withinRadius = true;
                               }
                           }
                      }
                  } catch (e) {
                      debugPrint("Reminder Dist Check Error: $e");
                  }

                  if (withinRadius) {
                      _stoppedSince ??= DateTime.now();
                      
                      final duration = DateTime.now().difference(_stoppedSince!);
                      if (duration.inMinutes >= 5 && !_reminderSent) {
                           final String actionLabel = action['label'] ?? 'Status';
                           NotificationService().showNotification(
                               id: 888,
                               title: "Action Required: $actionLabel",
                               body: "Ignition is OFF. Please tap '$actionLabel' to update."
                           );
                           _reminderSent = true;
                      }
                  } else {
                      _stoppedSince = null; // Reset if outside radius
                      _reminderSent = false;
                  }
              } else {
                   // Reset if moving / ignition ON
                   _stoppedSince = null;
                   _reminderSent = false;
              }

              // --- Unplanned Stoppage Reason Detection ---
              if (isStopped && !_isNearAnyPlannedStop(vehicle)) {
                  _unplannedStopSince ??= DateTime.now();
                  final elapsed = DateTime.now().difference(_unplannedStopSince!);
                  if (elapsed.inMinutes >= 15 && !_stoppageReasonRequested) {
                      _stoppageReasonRequested = true;
                      NotificationService().showNotification(
                          id: 889,
                          title: Provider.of<LocalizationProvider>(context, listen: false).t('stoppage_why') ?? "Why did you stop?",
                          body: Provider.of<LocalizationProvider>(context, listen: false).t('stoppage_provide_reason') ?? "Please provide a reason for stopping",
                      );
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && !_stoppageSheetShowing) _showStoppageReasonSheet();
                      });
                  }
              } else if (!isStopped) {
                  // Vehicle is moving again — close active stoppage
                  if (_activeStoppageId != null) {
                      _closeActiveStoppage();
                  }
                  _unplannedStopSince = null;
                  _stoppageReasonRequested = false;
                  _activeStoppageId = null;
                  _stoppageSheetShowing = false;
              }
              // --- End Stoppage Detection ---

           } catch (e) {
               debugPrint("Reminder Error: $e");
           }
           // ---------------------
           
           // Robust parsing for Int gauges
           if (data['fuel_level'] != null) {
               vehicle['fuel_level_percent'] = _parseNum(data['fuel_level'])?.toInt();
           }
           if (data['def_level'] != null) {
               vehicle['def_level_percent'] = _parseNum(data['def_level'])?.toInt();
           }
           if (data['battery_level'] != null) {
               vehicle['battery_voltage_v'] = _parseNum(data['battery_level']);
           }
           if (data['exhaust_temperature'] != null) {
               vehicle['exhaust_temperature_c'] = _parseNum(data['exhaust_temperature']);
           }
           
           final balances = _dashboardData?['balances'] ?? {};
           if (data['fuel_wallet_balance'] != null) {
              balances['fuel'] = data['fuel_wallet_balance']; 
           }
           if (data['fastag_wallet_balance'] != null) {
              balances['fastag'] = data['fastag_wallet_balance'];
           }

           final route = _dashboardData?['route'] ?? {};
           // If we have distance left, update it
           if (data['distanceLeftKm'] != null) {
              route['distance_remaining_km'] = data['distanceLeftKm'];
           }
           
           if (data['available_actions'] != null) {
              route['available_actions'] = data['available_actions'];
           }

           // Preserve fuelPlan across SSE updates so the proximity check can
           // still see the planned fuel stops (the SSE payload doesn't include
           // them — it's a thin GPS+telemetry stream).
           final existingFuelPlan = _dashboardData?['fuelPlan'];

           // Re-assign to trigger UI update
           _dashboardData = {
              'job': _job, // static for now
              'vehicle': vehicle,
              'balances': balances,
              'route': route,
              if (existingFuelPlan != null) 'fuelPlan': existingFuelPlan,
           };
           _updateFuelProximity();

           // Force update map
           final state = _mapKey.currentState;
           if (state != null) {
              (state as dynamic).updateVehicleLocation(
                  LatLng(vehicle['location']['lat'], vehicle['location']['lng']),
                  vehicle['location']['heading'] ?? 0.0
              );
           }
        });
    });
  }

  /// Compute distance from current GPS to the next planned fuel stop.
  /// When the truck enters the 2 km zone for a pump it hasn't been alerted
  /// for yet, fire a one-shot haptic + system tone so the driver doesn't
  /// blow past it. Always-on banner above the bottom sheet uses the same
  /// state to render the visual countdown (5 km warm-up, 2 km alert).
  void _updateFuelProximity() {
    final stops = (_dashboardData?['fuelPlan']?['stops'] as List?) ?? const [];
    final vLoc = _dashboardData?['vehicle']?['location'];
    if (stops.isEmpty || vLoc == null) {
      if (_fuelProxKm != null || _fuelProxStop != null) {
        _fuelProxKm = null;
        _fuelProxStop = null;
      }
      return;
    }
    final vLat = double.tryParse(vLoc['lat'].toString()) ?? 0.0;
    final vLng = double.tryParse(vLoc['lng'].toString()) ?? 0.0;
    if (vLat == 0 && vLng == 0) return;

    final next = stops.first as Map<String, dynamic>;
    final pLat = double.tryParse((next['lat']).toString()) ?? 0.0;
    final pLng = double.tryParse((next['lng']).toString()) ?? 0.0;
    if (pLat == 0 && pLng == 0) return;

    final prevKm = _fuelProxKm;
    final km = _getHaversineDistance(vLat, vLng, pLat, pLng);
    _fuelProxKm = km;
    _fuelProxStop = next;

    // One-shot alert when crossing into 2 km. Identify the pump by its
    // 4dp coord key so we don't re-alert if the driver loops back.
    final key = '${pLat.toStringAsFixed(4)},${pLng.toStringAsFixed(4)}';
    if (km <= 2.0 && _fuelProxAlertedKey != key) {
      _fuelProxAlertedKey = key;
      _fireFuelProximityAlert(next, km);
    } else if (km > 5.0 && _fuelProxAlertedKey == key) {
      // Driver moved past the pump or it was swapped — clear so a future
      // pump in the plan can re-trigger if they come within 2 km.
      _fuelProxAlertedKey = null;
      // Server's auto-skip worker fires within 90s after a planned pump
      // is passed by >=5km. Trigger an immediate dashboard refresh so the
      // orange marker for the now-skipped pump disappears from the map
      // (and the Next Refuel card switches to the next planned stop)
      // within one HTTP round-trip instead of waiting up to 30s for the
      // next poll tick.
      if (prevKm != null && prevKm <= 5.0) {
        unawaited(_fetchDashboardData());
      }
    }
  }

  void _fireFuelProximityAlert(Map<String, dynamic> stop, double km) {
    final outletName = (stop['outletName'] ?? 'Fuel Stop').toString();
    // Vibrate + bell chime. Two haptic pulses ~150 ms apart so it's
    // distinguishable from incidental nav haptics; chime plays on top.
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 150), HapticFeedback.heavyImpact);
    if (_fuelChimeReady) {
      // Restart from 0 if it's still ringing from a previous alert.
      _fuelChime.stop().then((_) => _fuelChime.resume()).catchError((e) {
        debugPrint('Fuel chime play failed: $e');
      });
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFF59E0B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        content: Row(
          children: [
            const Icon(Icons.local_gas_station, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Fuel stop ahead — $outletName · ${km.toStringAsFixed(1)} km',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiConfig.dio.get('/driver/jobs/${_job['id']}/dashboard');
      if (!mounted) return;
      setState(() {
        _dashboardData = response.data;
        // debugPrint("DASHBOARD DATA: Vehicle: ${_dashboardData?['vehicle']}"); // Debug Initial Data
        if (_dashboardData?['job'] != null) {
            _job = _dashboardData!['job'];
            
            // Auto-start check: If status is scheduled but time is passed, start it.
            if (_job['status'] == 'scheduled' && _job['planned_start_at'] != null) {
                try {
                   final scheduled = DateTime.parse(_job['planned_start_at']);
                   final now = DateTime.now();
                   debugPrint("AUTO-START CHECK: Status=${_job['status']}");
                   debugPrint("AUTO-START CHECK: Planned (UTC)=${scheduled.toUtc()} | Local=${scheduled.toLocal()}");
                   debugPrint("AUTO-START CHECK: Current (UTC)=${now.toUtc()} | Local=$now");
                   debugPrint("AUTO-START CHECK: IsNowAfterScheduled? ${now.isAfter(scheduled)}");
                   
                   if (now.isAfter(scheduled)) {
                       debugPrint("AUTO-START: Job is past scheduled time. Starting now...");
                       // Use a tiny delay to allow build to finish or avoid state conflict
                       Future.delayed(const Duration(milliseconds: 500), () {
                           if (mounted) _updateStatus('start'); 
                       });
                   }
                } catch (e) {
                   debugPrint("Error parsing planned_start_at: $e");
                }
            } else {
                 if (_job['status'] == 'scheduled') {
                    debugPrint("AUTO-START CHECK: Skipped. PlannedStart=${_job['planned_start_at']}");
                 }
            }
        }
        _updateFuelProximity();
      });
    } on DioException catch (e) {
      // If we get a 404/403, the job probably doesn't exist or we lost access.
      // Trigger a global check to see if we should get a new job or go to NoJobPage.
      if (e.response?.statusCode == 404 || e.response?.statusCode == 403) {
          debugPrint("Dashboard Fetch Failed (${e.response?.statusCode}). Verifying Global Job Status...");
          if (mounted) _checkGlobalJobStatus();
      } else {
          debugPrint("Error fetching dashboard: $e");
      }
    } catch (e) {
      debugPrint("Error fetching dashboard: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Belt-and-suspenders confirmation before any stop status update.
  // The map can stack overlapping markers (warehouse + nearby pump, two
  // adjacent loading docks, etc.); a tap meant for one stop occasionally
  // selects another. Showing the stop's name + address + position in the
  // trip prominently before submitting lets the driver catch a wrong-
  // stop selection BEFORE the status flips. Skip this gate for `start`
  // (no stopIndex) and any action without an explicit stopIndex.
  Future<bool> _confirmStopActionDialog(int stopIndex, String actionLabel) async {
    final stops = (_job['route_stops'] as List?) ?? [];
    if (stopIndex < 0 || stopIndex >= stops.length) return true;
    final stop = stops[stopIndex] as Map<String, dynamic>;
    final stopName = (stop['address'] ?? stop['label'] ?? 'Stop ${stopIndex + 1}').toString();
    final stopType = (stop['type'] ?? stop['stop_type'] ?? stop['activity'] ?? '').toString().toLowerCase();
    final typeBadge = (stopType == 'loading' || stopType == 'unloading')
        ? stopType.toUpperCase()
        : null;

    final t = Provider.of<LocalizationProvider>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(actionLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stop ${stopIndex + 1} of ${stops.length}',
              style: TextStyle(color: Theme.of(ctx).hintColor, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              stopName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            if (typeBadge != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: stopType == 'loading' ? Colors.blue.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  typeBadge,
                  style: TextStyle(
                    color: stopType == 'loading' ? Colors.blue.shade700 : Colors.green.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              t.t('confirm_stop_action_prompt') ??
                'Confirm this is the right stop to update.',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.t('cancel') ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.t('confirm') ?? 'Confirm'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _updateStatus(String action, {Map<String, dynamic>? body}) async {
    // Defines actions that require the Sheet
    const sheetActions = ['reached', 'start_action', 'complete_action', 'depart', 'complete'];

    // Compound: at the first loading/unloading stop where the driver is already
    // on top of the location, "Arrived" is redundant. We merge it with the
    // Start action — fire reached silently, refresh state, then open the
    // start_action sheet so the driver only sees and confirms one button.
    if (action == 'reached_then_start') {
      final stopIdx = body?['stopIndex'];
      if (stopIdx != null) {
        try {
          await ApiConfig.dio.post(
            '/driver/jobs/${_job['id']}/reached',
            data: {'stopIndex': stopIdx},
          );
        } catch (e) {
          if (!mounted) return;
          final t = Provider.of<LocalizationProvider>(context, listen: false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${t.t('couldnt_mark_arrived') ?? "Couldn't mark arrived"}: $e')),
          );
          return;
        }
        await _fetchDashboardData();
      }
      return _updateStatus('start_action', body: body);
    }

    // Stop-affecting actions get a confirmation gate first. Driver sees
    // the stop name + address before the action sheet opens, so an
    // accidental wrong-stop selection (overlapping map markers, fat-
    // finger on the timeline) gets caught here.
    if (sheetActions.contains(action) && body != null && body['stopIndex'] != null) {
      final stopIdx = body['stopIndex'] is int
          ? body['stopIndex'] as int
          : int.tryParse(body['stopIndex'].toString()) ?? -1;
      final actionLabel = body['label']?.toString() ?? action;
      if (stopIdx >= 0) {
        final ok = await _confirmStopActionDialog(stopIdx, actionLabel);
        if (!ok) return;
      }
    }

    if (sheetActions.contains(action) && body != null && body['stopIndex'] != null) {
        final stopIndex = body['stopIndex'] as int;
        // Config Sheet
        final t = Provider.of<LocalizationProvider>(context, listen: false);
        String title = t.t('dialog_title_confirm_action') ?? "Confirm Action";
        String uploadLabel = t.t('proof_optional_label') ?? "Proof (Optional)";
        bool requireFile = false;

        if (action == 'reached') {
           title = t.t('dialog_title_confirm_arrival') ?? "Confirm Arrival";
           uploadLabel = t.t('gate_entry_proof_label') ?? "Gate Entry / Proof";
        } else if (action == 'start_action') {
           title = t.t('dialog_title_start_activity') ?? "Start Activity"; 
        } else if (action == 'complete_action') {
           title = t.t('dialog_title_complete_activity') ?? "Complete Activity"; 
           uploadLabel = t.t('upload_proof_label') ?? "Upload POD / Receipt";
           requireFile = false; 
        } else if (action == 'depart') {
           title = t.t('dialog_title_confirm_departure') ?? "Confirm Departure";
        } else if (action == 'complete') {
           title = t.t('dialog_title_complete_trip') ?? "Complete Trip";
        }

        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => StopActionSheet(
            title: title,
            uploadLabel: uploadLabel,
            requireFile: requireFile,
            isLoading: _isActionLoading,
            onSubmit: (time, fileId, notes) {
               Navigator.pop(ctx);
               final data = Map<String, dynamic>.from(body);
               data['actionAt'] = time.toIso8601String();
               if (fileId != null) data['pod_upload_id'] = fileId;
               if (notes != null && notes.isNotEmpty) data['pod_notes'] = notes;
               
               _performUpdateStatus(action, body: data);
            },
          )
        );
        return;
    }

    // Default path (e.g. Start Trip)
    await _performUpdateStatus(action, body: body);
  }

  Future<void> _performUpdateStatus(String action, {Map<String, dynamic>? body}) async {  
    setState(() => _isActionLoading = true);
    try {
      debugPrint("Updating status: $action with body $body");
      final response = await ApiConfig.dio.post(
          '/driver/jobs/${_job['id']}/$action',
          data: body 
      );
      
      if (!mounted) return;
      setState(() => _isActionLoading = false);

      if (response.data['ok'] == true) {
         String msg = "Status updated";
         final t = Provider.of<LocalizationProvider>(context, listen: false);
         
         if (action == 'start') msg = t.t('job_started');
         else if (action == 'complete') {
             _poller?.cancel();
             _disconnectStream();
             // IMPORTANT: "Complete Trip" means driver is done. Job might be pending admin review.
             msg = "Trip Completed";
             // Show the driver their settlement breakdown ("here is what we
             // owe you for this trip") before bouncing to NoJobPage. Mirrors
             // the dispatcher's CompleteJobModal on the web. Failure to fetch
             // is silently swallowed — Complete is the user-critical action,
             // the sheet is a nicety. Sheet uses the driver's role + split
             // share from /api/driver/jobs/:jobId/settlement.
             try {
                 final sRes = await ApiConfig.dio.get('/driver/jobs/${_job['id']}/settlement');
                 if (mounted && sRes.data is Map) {
                     await showSettlementSheet(
                         context,
                         settlement: Map<String, dynamic>.from(sRes.data as Map),
                         jobTitle: _job['title']?.toString(),
                         okLabel: 'Done',
                     );
                 }
             } catch (e) {
                 debugPrint('[settlement] fetch failed after complete: $e');
             }
             if (!mounted) return;
             Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const NoJobPage()));
             return;
         }
         else if (action == 'reached') {
             msg = t.t('location_reached');
             if (body != null && body['stopIndex'] != null) {
                 try {
                     final int idx = body['stopIndex'] is int ? body['stopIndex'] : int.parse(body['stopIndex'].toString());
                     final stops = (_job['route_stops'] as List?) ?? [];
                     if (idx < stops.length) {
                         final stop = stops[idx];
                         final type = (stop['type'] ?? stop['stop_type'] ?? '').toString().toLowerCase();
                         if (type == 'loading') {
                             msg = t.t('reached_loading_point');
                         } else if (type == 'unloading') {
                             msg = t.t('reached_unloading_point');
                         }
                     }
                 } catch (e) {
                     debugPrint("Error resolving stop type for message: $e");
                 }
             }
         }
         else if (action == 'start_action') {
             final label = body != null ? body['label'].toString().toLowerCase() : '';
             if (label.contains('unload')) {
                 msg = t.t('action_unloading') ?? 'Unloading Started'; 
             } else {
                 msg = t.t('loading_started'); 
             }
         }
         else if (action == 'complete_action') {
             final label = body != null ? body['label'].toString().toLowerCase() : '';
             if (label.contains('unload')) {
                 msg = t.t('action_unloaded') ?? 'Unloading Completed'; 
             } else {
                 msg = t.t('loading_completed'); 
             }
         }
         else if (action == 'depart') msg = t.t('departed');

         // Dynamic Color Logic
         Color snackColor = Colors.green;
         if (action == 'start_action') {
             final label = body != null ? body['label'].toString().toLowerCase() : '';
             if (label.contains('unload')) snackColor = Colors.orange; // Distinct for Unload
             else snackColor = Colors.blue; // Distinct for Load
         }

         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: snackColor));
         _fetchDashboardData(); 
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response.data['message'] ?? "Action failed")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  void _showThemeSheet(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final t = Provider.of<LocalizationProvider>(context, listen: false);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.t('select_theme'), style: AppTextStyles.header.copyWith(fontSize: 20, color: Theme.of(context).textTheme.bodyLarge?.color)),
              const SizedBox(height: 16),
              _buildThemeOption(themeProvider, t.t('theme_system'), ThemeMode.system, Icons.smartphone),
              _buildThemeOption(themeProvider, t.t('theme_light'), ThemeMode.light, Icons.wb_sunny),
              _buildThemeOption(themeProvider, t.t('theme_dark'), ThemeMode.dark, Icons.nightlight_round),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThemeOption(ThemeProvider provider, String label, ThemeMode mode, IconData icon) {
    final isSelected = provider.preference == mode;
    return InkWell(
      onTap: () {
        provider.setThemeMode(mode);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? AppColors.primary : Theme.of(context).iconTheme.color?.withOpacity(0.5)),
            const SizedBox(width: 12),
            Text(label, style: AppTextStyles.body.copyWith(
              color: isSelected ? AppColors.primary : Theme.of(context).textTheme.bodyMedium?.color,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
            )),
            const Spacer(),
            if (isSelected) const Icon(Icons.check, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }

  void _showLanguageSheet(BuildContext context, LocalizationProvider t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.t('select_language'), style: AppTextStyles.header.copyWith(fontSize: 20, color: Theme.of(context).textTheme.bodyLarge?.color)),
              const SizedBox(height: 16),
              _buildLanguageOption(t, 'English', const Locale('en', 'US')),
              _buildLanguageOption(t, 'हिन्दी', const Locale('hi')),
              _buildLanguageOption(t, 'తెలుగు', const Locale('te')),
              _buildLanguageOption(t, 'മലയാളം', const Locale('ml')),
              _buildLanguageOption(t, 'ಕನ್ನಡ', const Locale('kn')),
              _buildLanguageOption(t, 'தமிழ்', const Locale('ta')),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLanguageOption(LocalizationProvider t, String label, Locale locale) {
    final isSelected = t.locale.languageCode == locale.languageCode;
    return InkWell(
      onTap: () {
        t.setLocale(locale);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Text(label, style: AppTextStyles.body.copyWith(
              color: isSelected ? AppColors.primary : Theme.of(context).textTheme.bodyMedium?.color,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
            )),
            const Spacer(),
            if (isSelected) const Icon(Icons.check, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }

  void _showFuelOptions() async {
      final vehicle = _dashboardData?['vehicle'] ?? {};
      final loc = vehicle['location'];
      
      if (loc == null || loc['lat'] == 0 || loc['lng'] == 0) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Provider.of<LocalizationProvider>(context, listen: false).t('vehicle_location_unknown'))));
         return;
      }
      
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Provider.of<LocalizationProvider>(context, listen: false).t('searching_pumps')), duration: const Duration(milliseconds: 1500)));

      try {
         final service = FindFuelService();
         double lat = (loc['lat'] is String) ? double.tryParse(loc['lat']) ?? 0 : (loc['lat'] as num).toDouble();
         double lng = (loc['lng'] is String) ? double.tryParse(loc['lng']) ?? 0 : (loc['lng'] as num).toDouble();
         
         String? routePolyline;
         if (_job['route_path'] is String) {
            routePolyline = _job['route_path'];
         }

         final pumps = await service.findNearbyIndianOil(LatLng(lat, lng), routePolyline: routePolyline);
         
         if (pumps.isEmpty) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Provider.of<LocalizationProvider>(context, listen: false).t('no_pumps_found'))));
            return;
         }
         
         if (!mounted) return;

         // Update Map Markers
         setState(() {
            _fuelStations = pumps;
         });
         
         // Inform user
         // Inform user
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
           content: Text("${Provider.of<LocalizationProvider>(context, listen: false).t('found_pumps')} (${pumps.length})"),
           duration: const Duration(seconds: 4),
         ));

      } catch (e) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${Provider.of<LocalizationProvider>(context, listen: false).t('error_searching_fuel')} $e"))); 
      }
  }

  void _showExpenseSheet() {
      LatLng? loc;
      final vehicle = _dashboardData?['vehicle'];
      if (vehicle != null && vehicle['location'] != null) {
          final l = vehicle['location'];
          if (l['lat'] != null && l['lng'] != null) {
             loc = LatLng((l['lat'] as num).toDouble(), (l['lng'] as num).toDouble());
          }
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => AddExpenseSheet(
           job: _job,
           currentLocation: loc,
           onSuccess: _fetchDashboardData, // refresh balances
        ),
      );
  }

  void _showExpenseList() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ExpenseListSheet(job: _job),
      );
  }

  void _showSwitchDriverDialog(bool isCurrentDriver) async {
     final t = Provider.of<LocalizationProvider>(context, listen: false);
     // 1. Confirm Intent
     final confirm = await showDialog<bool>(
       context: context, 
       builder: (ctx) => AlertDialog(
         title: Text(isCurrentDriver ? t.t('switch_driver_title') : t.t('take_over_title')),
         content: Text(isCurrentDriver ? t.t('switch_driver_content') : t.t('take_over_content')),
         actions: [
           TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.t('cancel'))),
           TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.t('send_otp'))),
         ],
       )
     );

     if (confirm != true) return;

     setState(() => _isActionLoading = true);
     try {
        // 2. Request OTP
        debugPrint("Requesting switch for job ${_job['id']}");
        final res = await ApiConfig.dio.post('/driver/jobs/${_job['id']}/switch/request');
        
        if (!mounted) return;
        setState(() => _isActionLoading = false);

        if (res.data['ok'] == true) {
           _showOtpInput(res.data['message']); // Message from server might be dynamic, keep as is or translate if static
        } else {
           final t = Provider.of<LocalizationProvider>(context, listen: false);
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.data['message'] ?? t.t('failed_request_switch'))));
        }
     } catch (e) {
        if (mounted) {
           setState(() => _isActionLoading = false);
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        }
     }
  }

  void _showOtpInput(String message) {
     final t = Provider.of<LocalizationProvider>(context, listen: false);
     final TextEditingController _otpCtrl = TextEditingController();
     showDialog(
       context: context,
       barrierDismissible: false,
       builder: (ctx) => AlertDialog(
         title: Text(t.t('verify_codriver_title')),
         content: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             Text(message, style: const TextStyle(fontSize: 13, color: Colors.grey)),
             const SizedBox(height: 16),
             TextField(
               controller: _otpCtrl,
               keyboardType: TextInputType.number,
               maxLength: 6,
               decoration: InputDecoration(
                 labelText: t.t('enter_otp_label'),
                 border: const OutlineInputBorder(),
               ),
             ),
           ],
         ),
         actions: [
           TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.t('cancel'))),
           ElevatedButton(
             onPressed: () async {
                final code = _otpCtrl.text.trim();
                if (code.length < 4) return;
                
                Navigator.pop(ctx); // Close dialog
                _verifySwitch(code);
             }, 
             child: Text(t.t('verify_switch_btn'))
           )
         ],
       )
     );
  }

  Future<void> _verifySwitch(String code) async {
     setState(() => _isLoading = true);
     final t = Provider.of<LocalizationProvider>(context, listen: false);
     try {
        final res = await ApiConfig.dio.post('/driver/jobs/${_job['id']}/switch/confirm', data: {'code': code});
        if (res.data['ok'] == true) {
           if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.t('driver_switched_success'))));
              _fetchDashboardData();
           }
        } else {
           if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.data['message'] ?? t.t('invalid_otp'))));
        }
     } catch (e) {
        String msg = t.t('switch_verification_failed');
        if (e is DioException && e.response?.data != null && e.response!.data['message'] != null) {
           msg = e.response!.data['message'];
        }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
     } finally {
        if (mounted) setState(() => _isLoading = false);
     }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context);
    final status = _job['status'] ?? 'scheduled';
    final isStarted = status == 'in_progress';
    final size = MediaQuery.of(context).size;
    
    // Safety check just in case dashboard data failed
    final balances = _dashboardData?['balances'] ?? {'fuel': 0.0, 'fastag': 0.0};
    final vehicle = _dashboardData?['vehicle'] ?? {'fuel_level_percent': 0, 'def_level_percent': 0, 'odometer_km': 0};
    final route = _dashboardData?['route'] ?? {'distance_remaining_km': 0, 'eta_minutes': 0};

    // Distance Logic (Sync with Web JobCard)
    final double? startOdo = double.tryParse(_job['start_odometer_km']?.toString() ?? '');
    final double? currentOdo = double.tryParse(vehicle['odometer_km']?.toString() ?? '');
    final double? routeDistance = double.tryParse(_job['route_distance_km']?.toString() ?? '');
    final double? serverRemaining = double.tryParse(route['distance_remaining_km']?.toString() ?? '');
    
    double distanceCovered = 0.0;
    double distanceRemaining = 0.0;
    double progress = 0.0;
    
    // 1. Calculate Distance Covered (Priority: Odometer)
    if (isStarted && startOdo != null && currentOdo != null) {
         distanceCovered = (currentOdo - startOdo).clamp(0, double.infinity);
    } else {
         // Fallback covered if needed, though usually 0 or inferred
         if (routeDistance != null && serverRemaining != null) {
            distanceCovered = (routeDistance - serverRemaining).clamp(0, double.infinity);
         }
    }

    // 2. Calculate Distance Remaining (Priority: Haversine Corrected Server Value -> Calculated)
    double? direct = serverRemaining;
    
     if (direct != null) {
          distanceRemaining = direct;
     }

    // 3. Calculate Progress
    final double effectiveTotal = distanceCovered + distanceRemaining;
    if (effectiveTotal > 0) {
        progress = (distanceCovered / effectiveTotal).clamp(0.0, 1.0);
    } else if (routeDistance != null && routeDistance > 0) {
        progress = (distanceCovered / routeDistance).clamp(0.0, 1.0);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading && _dashboardData == null 
        ? const Center(child: CircularProgressIndicator())
        : Stack(
          children: [
            // 1. Full Screen Map Background
            Positioned.fill(
              child: LiveJobMap(
                  key: _mapKey, // Assign Key
                  job: _job,
                  vehicle: vehicle,
                  fuelStations: _fuelStations,
                  // Feed the server's live fuel plan (stops) into the map so
                  // the driver sees orange pump markers at each planned refuel,
                  // not just the text card below.
                  plannedFuelStops: (_dashboardData?['fuelPlan']?['stops'] as List?)
                      ?.whereType<Map<String, dynamic>>()
                      .toList(),
                  onPlannedFuelStopTap: (stop) {
                    final lat = (stop['lat'] as num?)?.toDouble();
                    final lng = (stop['lng'] as num?)?.toDouble();
                    final name = (stop['outletName'] ?? 'Fuel stop').toString();
                    if (lat != null && lng != null) {
                      final truck = _vehicleLatLng();
                      _launchMapsNavigation(lat, lng, name,
                          originLat: truck?[0], originLng: truck?[1]);
                    }
                  },
                  onFuelStationTap: (station) async {
                    final state = _mapKey.currentState;
                    if (state != null) {
                       // 1. Optimistic Update
                       (state as dynamic).updateDestination(
                          LatLng(station['lat'], station['lng']),
                          station['name']
                       );
                       
                       ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                         content: Text("${Provider.of<LocalizationProvider>(context, listen: false).t('routing_to')} ${station['name']}..."), 
                         duration: const Duration(seconds: 1)
                       ));

                       // 2. Directions
                       try {
                           final vLoc = vehicle['location'];
                           if (vLoc != null) {
                               final lat = _parseNum(vLoc['lat'])?.toDouble() ?? 0.0;
                               final lng = _parseNum(vLoc['lng'])?.toDouble() ?? 0.0;
                               final service = FindFuelService();
                               final routePoints = await service.getDirections(
                                   LatLng(lat, lng), 
                                   LatLng(station['lat'], station['lng'])
                               );
                               if (routePoints.isNotEmpty) {
                                   (state as dynamic).updateDestination(
                                     LatLng(station['lat'], station['lng']),
                                     station['name'],
                                     routePoints: routePoints
                                  );
                              } else {
                                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Provider.of<LocalizationProvider>(context, listen: false).t('no_road_route_found'))));
                              }
                           }
                       } catch (e) {
                          debugPrint("Error fetching route: $e");
                       }
                    }
                  },
              ),
            ),
            
            // 2. Header Gradient
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 180, // Slightly taller
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context).scaffoldBackgroundColor.withOpacity(1.0), // Fully solid at top
                        Theme.of(context).scaffoldBackgroundColor.withOpacity(0.8), // Stays strong
                        Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0)
                      ],
                      stops: const [0.0, 0.6, 1.0], // Push the fade lower down
                    ),
                  ),
                ),
              ),
            ),

            // 3. Find Fuel Button (Floating on Map) - Moved BEFORE sheet so sheet covers it
            Positioned(
              right: 16,
              top: 130, // Below header
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [


                   // 0. Leaderboard (Shortcut)
                   FloatingActionButton(
                        heroTag: "leaderboardBtn",
                        onPressed: () {
                           Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardPage()));
                        },
                        mini: true,
                        backgroundColor: Colors.teal,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.leaderboard, color: Colors.white),
                   ),
                   const SizedBox(height: 12),

                   // 1. Recenter / Navigation Button
                   FloatingActionButton(
                        heroTag: "recenterBtn",
                        onPressed: () {
                           final state = _mapKey.currentState;
                           if (state != null) {
                              (state as dynamic).recenter();
                           }
                        },
                        mini: true,
                        backgroundColor: Theme.of(context).cardTheme.color,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.navigation, color: Theme.of(context).primaryColor),
                   ),
                   const SizedBox(height: 12),
                   
                   // 2. Clear Route (Only if fuel stations active)
                   if (_fuelStations != null)
                     Padding(
                       padding: const EdgeInsets.only(bottom: 12),
                       child: FloatingActionButton(
                            heroTag: "clearBtn",
                            onPressed: () {
                               setState(() => _fuelStations = null);
                               final state = _mapKey.currentState;
                               if (state != null) {
                                  (state as dynamic).resetNavigation();
                               }
                            },
                            mini: true,
                            backgroundColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.close, color: Colors.white),
                       ),
                     ),

                   // 3. Fuel Search (Only if NOT navigating/searching)
                   if (_fuelStations == null)
                     FloatingActionButton(
                        heroTag: "fuelBtn", 
                        onPressed: _showFuelOptions,
                        mini: true,
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.local_gas_station, color: Colors.white),
                     ),
                    
                   const SizedBox(height: 12),
                   
                   // 4. Add Expense
                   FloatingActionButton(
                        heroTag: "expenseBtn",
                        onPressed: () {
                          // Dynamic import or local usage? Need to import at top.
                          // Assuming import added below manually or via separate chunk
                          _showExpenseSheet();
                        },
                        mini: true,
                        backgroundColor: Colors.purpleAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.add_circle, color: Colors.white),
                   ),
                   
                   const SizedBox(height: 12),
                   
                   // 5. View Expenses
                   FloatingActionButton(
                        heroTag: "viewExpensesBtn",
                        onPressed: _showExpenseList,
                        mini: true,
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.list_alt, color: Colors.white),
                   ),




                   const SizedBox(height: 12),

                   // 6. Tyre Management
                   FloatingActionButton(
                        heroTag: "tyreBtn",
                        onPressed: () {
                           // Navigate to Tyre Management
                           // We need vehicleId and registrationNumber.
                           // Assuming they are available in _dashboardData['vehicle']
                           if (_dashboardData != null && _dashboardData!['vehicle'] != null) {
                              final v = _dashboardData!['vehicle'];
                              debugPrint("TyreBtn Check: Vehicle Data: $v"); // DEBUG
                              // Vehicle ID check with fallback
                              if (v['id'] == null && _job['vehicle_id'] == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Provider.of<LocalizationProvider>(context, listen: false).t('vehicle_details_loading') ?? 'Vehicle details not fully loaded yet')));
                                  return;
                              }
                              
                              String regNum = 'Unknown';
                              if (v['registrationNumber'] != null) regNum = v['registrationNumber'];
                              else if (v['vehicleNumber'] != null) regNum = v['vehicleNumber'];
                              else if (v['registration_number'] != null) regNum = v['registration_number'];
                              else if (v['vehicle_number'] != null) regNum = v['vehicle_number'];
                              else if (v['plate_number'] != null) regNum = v['plate_number'];
                              else if (v['registration_no'] != null) regNum = v['registration_no'];
                              else if (v['reg_no'] != null) regNum = v['reg_no'];
                              else if (v['name'] != null) regNum = v['name']; // Fallback to name if generic

                              Navigator.push(context, MaterialPageRoute(builder: (_) => TyreManagementPage(
                                  vehicleId: v['id'] ?? _job['vehicle_id'],
                                  registrationNumber: regNum,
                                  orgId: _job['org_id']
                              )));
                           } else {
                               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Provider.of<LocalizationProvider>(context, listen: false).t('dashboard_loading') ?? 'Please wait for dashboard data...')));
                           }
                        },
                        mini: true,
                        backgroundColor: Colors.blueGrey,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.local_shipping, color: Colors.white),
                   ),

                   // Loans tile moved into the Profile screen — accessible
                   // from the Profile icon in the toolbar. Removing the FAB
                   // here so the action column doesn't repeat the same entry.

                   // Earnings — always visible; the driver should be able
                   // to check what they've made over a period at any time.
                   const SizedBox(height: 12),
                   FloatingActionButton(
                     heroTag: "earningsBtn",
                     onPressed: () {
                       Navigator.push(context, MaterialPageRoute(builder: (_) => const EarningsPage()));
                     },
                     mini: true,
                     backgroundColor: Colors.green.shade700,
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                     child: const Icon(Icons.payments, color: Colors.white),
                   ),

                ],
              ),
            ),

            // 3a. Floating banners stack — fuel proximity (amber/red) +
            //     vehicle locator (blue), in that priority. Both anchor
            //     just above the bottom sheet so they never overlap the
            //     scrollable content.
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).size.height * 0.40 + 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_fuelProxKm != null && _fuelProxKm! <= 5.0 && _fuelProxStop != null) ...[
                    _buildFuelProximityBanner(),
                    const SizedBox(height: 8),
                  ],
                  if (_shouldShowVehicleLocator()) _buildVehicleLocatorBanner(),
                ],
              ),
            ),

            // 4. Draggable Sheet
            DraggableScrollableSheet(
              initialChildSize: 0.45,
              minChildSize: 0.40,
              maxChildSize: 0.88, // Stops just below header for "Merge" effect
              snap: true,
              builder: (context, scrollController) {
                return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                      boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))
                      ]
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: RefreshIndicator(
                      onRefresh: _fetchDashboardData,
                      color: AppColors.primary,
                      backgroundColor: Theme.of(context).cardTheme.color,
                      child: SingleChildScrollView(
                        controller: scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           const SizedBox(height: 8),
                           // Handle Bar
                           Center(
                             child: Container(
                               width: 40, height: 4,
                               margin: const EdgeInsets.only(bottom: 12),
                               decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                             ),
                           ),

                           // Compact next-stop strip — always visible at the top of
                           // the sheet so the driver sees where they're heading
                           // without scrolling. Tap → fly to it on the map.
                           _buildNextStopStrip(),
                           const SizedBox(height: 14),

                           // Job Title
                           Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                               Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _job['title'] ?? '${t.t('job_label')} #${_job['id']}', 
                                        style: AppTextStyles.header.copyWith(fontSize: 24, color: Theme.of(context).textTheme.bodyLarge?.color),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                      const SizedBox(height: 8),
                                      // Driver Status Row
                                      FutureBuilder<String?>(
                                        future: ApiConfig.getDriverId(),
                                        builder: (context, snapshot) {
                                           if (!snapshot.hasData) return const SizedBox.shrink();
                                           
                                           // Verify job data
                                           debugPrint("JOB DATA [switch_ui]: driver=${_job['driver_id']}, sec=${_job['secondary_driver_id']}, cur=${_job['current_driver_id']}, myId=${snapshot.data}");
                                           // Only show if there is a co-driver
                                           if (_job['secondary_driver_id'] == null) return const SizedBox.shrink();

                                           final myId = snapshot.data;
                                           final currentDriverId = _job['current_driver_id'] ?? _job['driver_id']; // Default to primary if null
                                           final isDriving = myId == currentDriverId;
                                           
                                           // Determine current driver name
                                           String currentDriverName = '';
                                           if (currentDriverId == _job['secondary_driver_id']) {
                                              currentDriverName = _job['secondary_driver_name'] ?? 'Co-Driver';
                                           } else {
                                              currentDriverName = _job['driver_name'] ?? 'Driver';
                                           }

                                           return Wrap(
                                             spacing: 12,
                                             runSpacing: 8,
                                             crossAxisAlignment: WrapCrossAlignment.center,
                                             children: [
                                               Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  decoration: BoxDecoration(
                                                      color: isDriving ? Colors.green.withOpacity(0.1) : Colors.amber.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(20),
                                                      border: Border.all(color: isDriving ? Colors.green : Colors.amber)
                                                  ),
                                                  child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                          Icon(Icons.local_shipping, color: isDriving ? Colors.green : Colors.amber, size: 16),
                                                          const SizedBox(width: 6),
                                                          Text(
                                                              isDriving ? t.t('you_are_driving') : t.t('passenger_codriver'), 
                                                              style: AppTextStyles.label.copyWith(
                                                                fontWeight: FontWeight.w600, 
                                                                color: isDriving ? Colors.green : Colors.amber
                                                              ),
                                                          ),
                                                      ]
                                                  ),
                                                ),
                                                InkWell(
                                                  onTap: () => _showSwitchDriverDialog(isDriving),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                    decoration: BoxDecoration(
                                                       color: Theme.of(context).primaryColor.withOpacity(0.1),
                                                       borderRadius: BorderRadius.circular(20),
                                                       border: Border.all(color: Theme.of(context).primaryColor)
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min, // Ensure button also doesn't expand unnecessarily
                                                      children: [
                                                        Icon(Icons.swap_horiz, size: 16, color: Theme.of(context).primaryColor),
                                                        const SizedBox(width: 4),
                                                        Flexible( // Add Flexible to truncate text if button itself is too wide even on new line (rare but safe)
                                                          child: Text(
                                                            isDriving ? t.t('switch_btn') : t.t('take_over_btn'), 
                                                            style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 12),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                )
                                             ],
                                           );
                                      }
                                    ),
                                    

                                  ],
                                ),
                              ),
                             ],
                           ),
                           const SizedBox(height: 24),

                           // Balances
                           Text(t.t('wallet_balances'), style: AppTextStyles.header.copyWith(fontSize: 18, color: Theme.of(context).textTheme.bodyLarge?.color)),
                           const SizedBox(height: 12),
                           Row(
                             children: [
                               Expanded(child: _buildBalanceCard(t.t('fuel_balance'), "₹ ${balances['fuel']}", Colors.orangeAccent, Icons.local_gas_station)),
                               const SizedBox(width: 12),
                               Expanded(child: _buildBalanceCard(t.t('fastag_balance'), "₹ ${balances['fastag']}", Colors.purpleAccent, Icons.credit_card)),
                             ],
                           ),
                           const SizedBox(height: 24),

                            // Vehicle Stats
                            Text(t.t('vehicle_health'), style: AppTextStyles.header.copyWith(fontSize: 18, color: Theme.of(context).textTheme.bodyLarge?.color)),
                            const SizedBox(height: 12),
                             Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
                                decoration: BoxDecoration(
                                    color: Theme.of(context).cardTheme.color,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Theme.of(context).dividerColor)
                                ),
                               child: Column(
                                   children: [
                                       // Row 1 — fuel + DEF. Tap any gauge → 24h history sheet.
                                       Row(
                                           mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                           children: [
                                               GestureDetector(
                                                   onTap: () => _openTankHistory(metric: 'fuel', label: t.t('fuel_level'), unit: 'L', color: Colors.greenAccent),
                                                   child: _buildPremiumGauge(t.t('fuel_level'), _parseNum(vehicle['fuel_level_percent'] ?? vehicle['fuel_level'])?.toInt() ?? 0, _parseNum(vehicle['fuel_tank_capacity']) ?? 0, Colors.greenAccent, Icons.local_gas_station),
                                               ),
                                               GestureDetector(
                                                   onTap: () => _openTankHistory(metric: 'def', label: t.t('def_level'), unit: 'L', color: Colors.blueAccent),
                                                   child: _buildPremiumGauge(t.t('def_level'), _parseNum(vehicle['def_level_percent'] ?? vehicle['def_level'])?.toInt() ?? 0, _parseNum(vehicle['def_tank_capacity']) ?? 0, Colors.blueAccent, Icons.opacity),
                                               ),
                                           ],
                                       ),
                                       const SizedBox(height: 16),
                                       // Row 2 — battery voltage + exhaust temperature.
                                       Row(
                                           mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                           children: [
                                               GestureDetector(
                                                   onTap: () => _openTankHistory(metric: 'battery', label: t.t('battery_voltage'), unit: 'V', color: Colors.tealAccent),
                                                   child: _buildMetricGauge(
                                                       label: t.t('battery_voltage'),
                                                       value: _parseNum(vehicle['battery_voltage_v']),
                                                       unit: 'V',
                                                       arcMin: 20,
                                                       arcMax: 30,
                                                       icon: Icons.battery_charging_full,
                                                       colorFor: (v) {
                                                           if (v == null) return Colors.grey;
                                                           if (v < 23 || v > 30) return Colors.redAccent;
                                                           if (v < 24.5) return Colors.orangeAccent;
                                                           return Colors.tealAccent;
                                                       },
                                                       decimals: 1,
                                                   ),
                                               ),
                                               GestureDetector(
                                                   onTap: () => _openTankHistory(metric: 'exhaust', label: t.t('exhaust_temp'), unit: '°C', color: Colors.amberAccent),
                                                   child: _buildMetricGauge(
                                                       label: t.t('exhaust_temp'),
                                                       value: _parseNum(vehicle['exhaust_temperature_c']),
                                                       unit: '°C',
                                                       arcMin: 0,
                                                       arcMax: 600,
                                                       icon: Icons.local_fire_department,
                                                       colorFor: (v) {
                                                           if (v == null) return Colors.grey;
                                                           if (v > 550) return Colors.redAccent;
                                                           if (v > 450) return Colors.orangeAccent;
                                                           return Colors.amberAccent;
                                                       },
                                                       decimals: 0,
                                                   ),
                                               ),
                                           ],
                                       ),
                                   ],
                               ),
                            ),
                            const SizedBox(height: 24),

                            // Next Refuel card — only shown when the server returned a fuelPlan
                            // with at least one upcoming stop. Navigate button deep-links to
                            // Google Maps (no cost to Drivara — uses driver's own installed app).
                            if (_dashboardData != null
                                && _dashboardData!['fuelPlan'] != null
                                && (_dashboardData!['fuelPlan']['stops'] as List?)?.isNotEmpty == true) ...[
                              Text(
                                'Next refuel',
                                style: AppTextStyles.header.copyWith(
                                  fontSize: 18,
                                  color: Theme.of(context).textTheme.bodyLarge?.color,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildNextRefuelCard(_dashboardData!['fuelPlan']),
                              const SizedBox(height: 24),
                            ],

                            // Route Progress
                            Text(t.t('route_progress'), style: AppTextStyles.header.copyWith(fontSize: 18, color: Theme.of(context).textTheme.bodyLarge?.color)),
                            const SizedBox(height: 12),
                            Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                    color: Theme.of(context).cardTheme.color,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Theme.of(context).dividerColor)
                                ),
                                child: Column(
                                    children: [
                                        Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(t.t('distance_covered'), style: AppTextStyles.body.copyWith(color: Theme.of(context).textTheme.bodyMedium?.color)),
                                                    Text("${_parseNum(distanceCovered)?.toStringAsFixed(1) ?? '0.0'} km", style: AppTextStyles.header.copyWith(fontSize: 16, color: Theme.of(context).textTheme.bodyLarge?.color)),
                                                  ],
                                                ),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    Text(t.t('distance_remaining'), style: AppTextStyles.body.copyWith(color: Theme.of(context).textTheme.bodyMedium?.color)),
                                                    Text("${_parseNum(distanceRemaining)?.toStringAsFixed(1) ?? '0.0'} km", style: AppTextStyles.header.copyWith(fontSize: 16, color: Theme.of(context).textTheme.bodyLarge?.color)),
                                                  ],
                                                ),
                                            ],
                                        ),
                                       const SizedBox(height: 10),
                                       
                                       // Custom Graphical Route Tracker
                                       // Calculate proportional stops
                                       _buildTimelineSection(context, progress),

                                       
                                       const SizedBox(height: 10),
                                       Row(
                                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                           children: [
                                               Expanded(
                                                 child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                       Text(
                                                         _job['origin_address']?.split(',')[0] ?? t.t('label_start'), 
                                                         style: AppTextStyles.label.copyWith(fontWeight: FontWeight.bold, fontSize: 12),
                                                         maxLines: 1, overflow: TextOverflow.ellipsis
                                                       ),
                                                    ]
                                                 ),
                                               ),
                                               Expanded(
                                                 child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                       Text(
                                                         _job['destination_address']?.split(',')[0] ?? t.t('label_end'), 
                                                         style: AppTextStyles.label.copyWith(fontWeight: FontWeight.bold, fontSize: 12),
                                                         maxLines: 1, overflow: TextOverflow.ellipsis
                                                       ),
                                                    ]
                                                 ),
                                               ),
                                           ],
                                       ),
                                   ],
                               ),
                           ),
                           const SizedBox(height: 30),

                            // Action Buttons (Dynamic)
                            if (!isStarted)
                              ActionButtonCard(
                                label: t.t('start_trip') ?? 'Start Trip',
                                subtitle: t.t('tap_to_start_trip') ?? "Swipe to begin your journey",
                                icon: Icons.play_arrow,
                                color: AppColors.success,
                                isLoading: _isActionLoading,
                                onPressed: _isActionLoading ? null : () => _updateStatus('start'),
                              )
                              else Builder(
                                builder: (context) {
                                   List<Map<String, dynamic>> actions = [];
                                   bool isManual = false;
                                   bool tooFar = false;
                                   double distKm = 0;
                                   String stopStatus = '';
                                   Map<String, dynamic> stop = {};

                                   final vehicle = _dashboardData?['vehicle'] ?? {};
                                   final vLoc = vehicle['location'];

                                   // 1. Manual Selection Override
                                   if (_selectedStopIndex != null) {
                                       isManual = true;
                                       final stops = (_job['route_stops'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                                       if (_selectedStopIndex! < stops.length) {
                                           stop = stops[_selectedStopIndex!];
                                           final status = stop['status'] ?? 'pending';
                                           final rawType = stop['type'] ?? stop['stop_type'] ?? stop['activity'] ?? 'stop';
                                           final type = rawType.toString().toLowerCase();
                                           debugPrint("STOP DEBUG: Index=${_selectedStopIndex} | Status=$status | RawType=$rawType | ResolvedType=$type | ActionCompleted=${stop['action_completed_at']}");
                                           stopStatus = status;

                                           // Calc Distance
                                           if (vLoc != null && stop['lat'] != null && stop['lng'] != null) {
                                               final vLat = double.tryParse(vLoc['lat'].toString()) ?? 0.0;
                                               final vLng = double.tryParse(vLoc['lng'].toString()) ?? 0.0;
                                               
                                               if (vLat != 0 && vLng != 0) {
                                                   // Support both lat/lng and latitude/longitude
                                                   final sLat = double.tryParse(stop['lat'].toString()) ?? double.tryParse(stop['latitude'].toString()) ?? 0.0;
                                                   final sLng = double.tryParse(stop['lng'].toString()) ?? double.tryParse(stop['longitude'].toString()) ?? 0.0;
                                                   
                                                   if (sLat != 0 && sLng != 0) {
                                                        distKm = _getHaversineDistance(vLat, vLng, sLat, sLng);
                                                        debugPrint("DISTANCE CHECK: Stop ${_selectedStopIndex} | V: $vLat,$vLng | S: $sLat,$sLng | Dist: $distKm");
                                                        if (distKm > kAllowedActionRadiusKm) tooFar = true;
                                                   }
                                               }
                                           }

                                            // VALIDATION: Check if any future stop is already active
                                            // If Stop 1 is 'reached' or 'completed', Stop 0 cannot be acted upon.
                                            bool futureStopActive = false;
                                            for (int i = _selectedStopIndex! + 1; i < stops.length; i++) {
                                                final s = stops[i];
                                                if (s['status'] != null && s['status'] != 'pending') {
                                                    futureStopActive = true;
                                                    break;
                                                }
                                            }

                                            if (futureStopActive) {
                                                final tt = Provider.of<LocalizationProvider>(context, listen: false);
                                                return Padding(
                                                  padding: const EdgeInsets.all(16.0),
                                                  child: Column(
                                                    children: [
                                                       Text(tt.t('cannot_update_prev_stop') ?? 'Cannot update previous stop', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                                       Text(tt.t('proceeded_to_later_stop') ?? 'You have already proceeded to a later stop.', style: const TextStyle(color: Colors.grey)),
                                                       TextButton(
                                                           onPressed: () => setState(() => _selectedStopIndex = null),
                                                           child: Text(tt.t('cancel') ?? 'Cancel'),
                                                       )
                                                    ],
                                                  ),
                                                );
                                            }

                                           
                                           if (status == 'pending') {
                                                if (!tooFar) {
                                                    // SKIP ARRIVED for the first stop entirely.
                                                    // Stop 0 is the *start* of the job — the driver is, by
                                                    // definition, already at it (and the action buttons only
                                                    // even render here when within the action radius). So
                                                    // "Arrived" is meaningless: surface the actual next step.
                                                    //   - loading/unloading first stop → merged "Start
                                                    //     Loading"/"Start Unloading" (fires reached + start_action)
                                                    //   - generic first stop → go straight to Depart
                                                    //   - 2nd+ stops → existing "Arrived" / "Reached
                                                    //     Loading/Unloading Point" behavior, unchanged.
                                                    final isFirstStop = _selectedStopIndex == 0;
                                                    final isActionStop = type == 'loading' || type == 'unloading';

                                                    if (isFirstStop && isActionStop) {
                                                        final label = type == 'loading'
                                                            ? (t.t('action_loading') ?? 'Start Loading')
                                                            : (t.t('action_unloading') ?? 'Start Unloading');
                                                        actions.add({'action': 'reached_then_start', 'label': label, 'stopIndex': _selectedStopIndex});
                                                    } else if (isFirstStop || stop['skip_arrived'] == true) {
                                                        actions.add({'action': 'depart', 'label': t.t('action_departed') ?? 'Departed', 'stopIndex': _selectedStopIndex});
                                                    } else {
                                                        String label = 'Arrived';
                                                        if (type == 'loading') label = t.t('reached_loading_point') ?? 'Reached Loading Point';
                                                        else if (type == 'unloading') label = t.t('reached_unloading_point') ?? 'Reached Unloading Point';

                                                        actions.add({'action': 'reached', 'label': label, 'stopIndex': _selectedStopIndex});
                                                    }
                                                }
                                           } else if (status == 'reached') {
                                                if (type == 'loading' && stop['action_completed_at'] == null) {
                                                    if (!tooFar) {
                                                        actions.add({'action': 'start_action', 'label': 'Load', 'stopIndex': _selectedStopIndex});
                                                    }
                                                } else if (type == 'unloading' && stop['action_completed_at'] == null) {
                                                    if (!tooFar) {
                                                        actions.add({'action': 'start_action', 'label': 'Unload', 'stopIndex': _selectedStopIndex});
                                                    }
                                                } else {
                                                    // Restriction applies to Depart OR Complete
                                                    if (!tooFar) {
                                                        if (_selectedStopIndex == stops.length - 1) {
                                                            actions.add({'action': 'complete', 'label': t.t('action_complete_job') ?? 'Complete Trip', 'stopIndex': _selectedStopIndex});
                                                        } else {
                                                            actions.add({'action': 'depart', 'label': t.t('action_departed') ?? 'Departed', 'stopIndex': _selectedStopIndex});
                                                        }
                                                    }
                                                }
                                            } else if (status == 'action_in_progress' || status == 'loading' || status == 'unloading') {
                                                // Handle 'action_in_progress' and literal 'loading'/'unloading' statuses
                                                if (!tooFar) {
                                                    String label = (type == 'loading' || status == 'loading') ? 'Loaded' : 'Unloaded';
                                                    actions.add({'action': 'complete_action', 'label': label, 'stopIndex': _selectedStopIndex});
                                                }
                                            }
                                       }
                                   } else {
                                    // 2. Default: No generic actions if no stop selected (User Req)
                                       actions = []; 
                                   }

                                   // USER REQ: "Once the last stop's load is unloaded, it should by default show complete action"
                                   if (_isReadyToComplete()) {
                                       // Force exit manual mode if we are ready to complete
                                       if (isManual) {
                                          debugPrint("Force exiting manual mode because job is ReadyToComplete");
                                          // We can't setState during build, but we can treat 'isManual' as false locally for this render
                                          // and queue a reset? Better to just ignore manual actions here.
                                          isManual = false; 
                                          // Note: Actual state reset needs to happen elsewhere or we just ignore it in UI like this.
                                       }
                                   
                                       // Force inject Complete Action if not present
                                       bool hasComplete = actions.any((a) => a['action'] == 'complete' || a['action'] == 'depart'); // Depart will be converted below
                                       if (!hasComplete) {
                                           final stops = (_job['route_stops'] as List?) ?? [];
                                           actions = [{
                                              'action': 'complete', 
                                              'label': t.t('action_complete_job') ?? 'Complete Trip',
                                              'stopIndex': stops.length - 1
                                           }];
                                       }
                                   }
                                   
                                   
                                   // FIX: Intercept Depart on Last Stop -> Complete
                                   for (var i = 0; i < actions.length; i++) {
                                      final act = actions[i];
                                      if (act['action'] == 'depart') {
                                           int? stopIdx = act['stopIndex'];
                                           final stops = (_job['route_stops'] as List?) ?? [];
                                           if (stopIdx != null && stopIdx == stops.length - 1) {
                                               actions[i] = {
                                                  ...act,
                                                  'action': 'complete', 
                                                  'label': t.t('action_complete_job') ?? 'Complete Trip'
                                               };
                                           }
                                      }
                                   }

                                   if (actions.isNotEmpty) {
                                       return Column(
                                          children: [

                                              ...actions.map((act) {
                                                  // Determine Color & Subtitle
                                                  Color btnColor = AppColors.primary;
                                                  String sub = t.t('tap_to_proceed') ?? "Tap to proceed";
                                                  
                                                  final actionCode = act['action'] as String;
                                                  if (actionCode == 'reached') {
                                                     btnColor = Colors.blue.shade700;
                                                     sub = t.t('tap_to_confirm_arrival') ?? "Confirm arrival at location";
                                                  } else if (actionCode.contains('start_action')) {
                                                      btnColor = Colors.orange.shade700;
                                                      final lowerLabel = (act['label'] as String? ?? '').toLowerCase();
                                                      if (lowerLabel.contains('unload')) {
                                                          sub = t.t('tap_if_unloading_started');
                                                      } else {
                                                          sub = t.t('tap_if_loading_started');
                                                      }
                                                  } else if (actionCode.contains('complete_action')) {
                                                     btnColor = Colors.green.shade700;
                                                     final lowerLabel = (act['label'] as String? ?? '').toLowerCase();
                                                     if (lowerLabel.contains('unload')) {
                                                         sub = t.t('tap_if_unloading_completed');
                                                     } else {
                                                         sub = t.t('tap_if_loading_completed');
                                                     }
                                                  } else if (actionCode == 'depart') {
                                                     btnColor = Colors.purple.shade700;
                                                     sub = t.t('tap_to_depart') ?? "Leave location for next stop";
                                                  } else if (actionCode == 'complete') {
                                                      btnColor = Colors.green; 
                                                      sub = t.t('tap_to_complete_trip') ?? "Complete Trip";
                                                  }


                                                  
                                                  // FIX: Manual mode usually sets orange, but 'complete' MUST be green
                                                  Color finalColor = (isManual && actionCode != 'complete') ? Colors.orange.shade800 : btnColor;

                                              return ActionButtonCard(
                                                      label: _getLocalizedActionLabel(act, t),
                                                      subtitle: sub,
                                                      icon: _getActionIcon(act['label'] ?? act['action']),
                                                      color: finalColor,
                                                      isLoading: _isActionLoading,
                                                      onPressed: _isActionLoading ? null : () {
                                                         _updateStatus(act['action'], body: {'stopIndex': act['stopIndex'], 'label': act['label'], 'force': isManual});
                                                         if(isManual) setState(() => _selectedStopIndex = null);
                                                      },
                                                  );
                                              }).toList(),
                                          ],
                                       );
                                   }

                                   // Default "On Route" State
                                   // USER REQ: "still OFF ROUTE WARNING shows, it should not show when Driver completes it."
                                   // Logic: If ready to complete, we might be far effectively (since we are done), but we shouldn't warn.
                                   
                                   // Strict Radius & Selection Logic
                                   // "Do nothing, if > allowed action radius" -> Hide everything
                                   // "No action until any place is clicked" -> Hide everything if no selection
                                   // "Hide COMPLETED status bar" -> User Request
                                   
                                   final lowerStatus = stopStatus.toLowerCase();
                                   if (tooFar || _selectedStopIndex == null || ['completed', 'departed', 'skipped'].contains(lowerStatus)) {
                                      return const SizedBox.shrink();
                                   }
                                   
                                   // If we are here, we have a selection AND are within radius.
                                   // Show status bar or nothing? 
                                   // If 'actions' is empty (e.g. pending status but within radius), show status info.

                                   return Container(
                                       width: double.infinity,
                                       height: 56,
                                       decoration: BoxDecoration(
                                           gradient: LinearGradient(colors: [Colors.blue.shade900, Colors.blue.shade600]),
                                           borderRadius: BorderRadius.circular(16),
                                           boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]
                                       ),
                                       child: Center(
                                           child: Row(
                                               mainAxisAlignment: MainAxisAlignment.center,
                                               children: [
                                                    Icon(Icons.info_outline, color: Colors.white),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                        "Stop ${_selectedStopIndex! + 1}: ${stopStatus.toUpperCase()}", 
                                                        style: AppTextStyles.header.copyWith(fontSize: 16),
                                                        textAlign: TextAlign.center,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    TextButton(
                                                        onPressed: () => setState(() => _selectedStopIndex = null),
                                                        child: const Text("Back", style: TextStyle(color: Colors.white70))
                                                    )
                                               ],
                                           ),
                                       ),
                                   );
                                }
                              ),
                            const SizedBox(height: 40), // Bottom padding
                        ],
                      ),
                    ),
                  ),
                );
              }
            ),



            // 3. Header Content (Floating) - Moved to bottom to be on top of Sheet (z-index)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Image.asset('assets/images/drivara-icon.png', height: 40),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("Drivara", style: AppTextStyles.header.copyWith(fontSize: 18, height: 1, color: Theme.of(context).textTheme.bodyLarge?.color)),
                              Text(t.t('driver_role'), style: AppTextStyles.label.copyWith(fontSize: 10, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6), letterSpacing: 2)),
                            ],
                          )
                        ],
                      ),
                      
                      // Fuel PIN (In Header)
                      Builder(builder: (context) {
                        final pin = _job['fuel_card_pin'] ?? _job['pin'] ?? _dashboardData?['vehicle']?['fuel_card_pin'] ?? _dashboardData?['vehicle']?['pin'];
                        if (pin != null) {
                            return FutureBuilder<String?>(
                               future: ApiConfig.getDriverId(),
                               builder: (ctx, snap) {
                                  if (!snap.hasData) return const SizedBox.shrink();
                                  final myId = snap.data;
                                  final curId = _job['current_driver_id'] ?? _job['driver_id'];
                                  
                                  if (myId == curId) {
                                      return Container(
                                         margin: const EdgeInsets.only(left: 12),
                                         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                         decoration: BoxDecoration(
                                            color: Theme.of(context).cardTheme.color?.withOpacity(0.9),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: AppColors.primary.withOpacity(0.3))
                                         ),
                                         child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                                Icon(Icons.local_gas_station, size: 16, color: AppColors.primary),
                                                const SizedBox(width: 4),
                                                Text("$pin", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 14))
                                            ]
                                         )
                                      );
                                  }
                                  return const SizedBox.shrink();
                               }
                            );
                        }
                        return const SizedBox.shrink();
                      }),

                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.palette),
                            color: Theme.of(context).iconTheme.color,
                            onPressed: () => _showThemeSheet(context),
                          ),
                          IconButton(
                            icon: const Icon(Icons.language),
                            color: Theme.of(context).iconTheme.color,
                            onPressed: () => _showLanguageSheet(context, t),
                          ),
                          IconButton(
                            // Profile takes over from the old Logout icon —
                            // Logout now lives at the bottom of the Profile
                            // page (with a confirm dialog), alongside DL/RC/
                            // loans visibility. The icon renders the driver's
                            // avatar when one is uploaded (fetched once on
                            // init via _fetchProfileAvatar) and falls back to
                            // a generic person glyph otherwise.
                            icon: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                                ? CircleAvatar(
                                    radius: 14,
                                    backgroundImage: NetworkImage(_avatarUrl!),
                                  )
                                : const Icon(Icons.account_circle_outlined),
                            color: Theme.of(context).iconTheme.color,
                            tooltip: 'Profile',
                            onPressed: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
                            },
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildBalanceCard(String title, String amount, Color accentColor, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: accentColor.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(height: 12),
          Text(title, style: AppTextStyles.label.copyWith(color: Theme.of(context).textTheme.bodyMedium?.color)),
          const SizedBox(height: 4),
          Text(amount, style: AppTextStyles.header.copyWith(fontSize: 20, color: Theme.of(context).textTheme.bodyLarge?.color)),
        ],
      ),
    );
  }

  // Deep-link into the driver's installed map app. Zero cost to Drivara — the driver's
  // Google Maps (or fallback map app) handles turn-by-turn, re-routing, traffic, voice
  // guidance. We just hand off the destination lat/lng.
  //
  // When `origin` is supplied (truck's lat/lng for next-stop nav), Google Maps
  // computes the route from THAT point instead of the phone's GPS. Matters
  // when the driver has briefly stepped away from the truck — the route
  // shown should be the truck's route, not "directions from wherever I'm
  // standing". For the Navigate-to-Truck banner we leave origin null so
  // Google Maps uses the phone's GPS (driver wants directions from where
  // they actually are to the parked truck).
  Future<void> _launchMapsNavigation(
    double lat,
    double lng,
    String label, {
    List<List<double>> waypoints = const [],
    double? originLat,
    double? originLng,
  }) async {
    // With waypoints OR an explicit origin we have to use the universal Maps
    // web URL — the android `google.navigation:` scheme supports neither.
    final hasOrigin = originLat != null && originLng != null;
    if (waypoints.isNotEmpty || hasOrigin) {
      final wpStr = waypoints.map((p) => '${p[0]},${p[1]}').join('|');
      final originStr = hasOrigin ? '&origin=$originLat,$originLng' : '';
      final wpQuery = waypoints.isNotEmpty ? '&waypoints=${Uri.encodeComponent(wpStr)}' : '';
      final webUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '$originStr'
        '&destination=$lat,$lng'
        '$wpQuery'
        '&travelmode=driving',
      );
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    }

    // No waypoints, no origin → prefer the native Google Maps navigation URI
    // for an immediate turn-by-turn launch (origin defaults to phone GPS).
    final navUri = Uri.parse('google.navigation:q=$lat,$lng');
    if (await canLaunchUrl(navUri)) {
      await launchUrl(navUri, mode: LaunchMode.externalApplication);
      return;
    }
    final webUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  /// Pull the upcoming planned fuel stops between the driver's current GPS
  /// and the given user stop, in order. We compare `distanceFromStartKm`
  /// (set by the fuel-strategy planner) against the user-stop's projected
  /// km along the route. Returns at most 8 waypoints (Google Maps cap is
  /// 9 incl. destination).
  List<List<double>> _fuelWaypointsTo(Map<String, dynamic> userStop) {
    final stops = (_dashboardData?['fuelPlan']?['stops'] as List?) ?? const [];
    if (stops.isEmpty) return const [];

    // userStop's distance along route — fall back to distanceFromStartKm
    // when present, else use the proportional position * total distance.
    double userDistKm = double.infinity;
    final fromStart = _parseNum(userStop['distanceFromStartKm']) ?? _parseNum(userStop['distance_from_start_km']);
    if (fromStart != null) {
      userDistKm = fromStart.toDouble();
    } else {
      final totalKm = _parseNum(_dashboardData?['route']?['distance_remaining_km']);
      final pct = _parseNum(userStop['proportional_position']);
      if (totalKm != null && pct != null) {
        userDistKm = totalKm.toDouble() * pct.toDouble();
      }
    }

    final List<List<double>> wps = [];
    for (final raw in stops) {
      final m = (raw is Map) ? raw as Map<String, dynamic> : null;
      if (m == null) continue;
      final lat = _parseNum(m['lat'])?.toDouble();
      final lng = _parseNum(m['lng'])?.toDouble();
      final fuelDist = _parseNum(m['distanceFromStartKm']);
      if (lat == null || lng == null) continue;
      if (lat == 0 && lng == 0) continue;
      if (fuelDist != null && fuelDist.toDouble() > userDistKm) continue;
      wps.add([lat, lng]);
      if (wps.length >= 8) break;
    }
    return wps;
  }

  Widget _buildNextRefuelCard(Map<String, dynamic> fuelPlan) {
    final stops = (fuelPlan['stops'] as List?) ?? const [];
    if (stops.isEmpty) return const SizedBox.shrink();
    final next = stops.first as Map<String, dynamic>;

    final outletName = (next['outletName'] ?? 'Fuel Stop').toString();
    final outletAddress = (next['outletAddress'] ?? '').toString();
    final state = (next['state'] ?? '').toString();
    final fillLiters = (_parseNum(next['fillLiters']) ?? 0).toDouble();
    final pricePerLiter = (_parseNum(next['pricePerLiter']) ?? 0).toDouble();
    final fillCostInr = (_parseNum(next['fillCostInr']) ?? 0).toDouble();
    final lat = (_parseNum(next['lat']) ?? 0).toDouble();
    final lng = (_parseNum(next['lng']) ?? 0).toDouble();
    // Live distance: current vehicle position → pump (haversine). Falls
    // back to the server-computed distanceFromStartKm (static, set at
    // route-plan time) only when telemetry hasn't arrived yet. Never uses
    // the driver's phone GPS — the truck is what we're refuelling, not the
    // phone.
    double distanceKm = (_parseNum(next['distanceFromStartKm']) ?? 0).toDouble();
    final vLoc = _dashboardData?['vehicle']?['location'];
    if (vLoc != null && lat != 0 && lng != 0) {
      final vLat = double.tryParse(vLoc['lat'].toString()) ?? 0.0;
      final vLng = double.tryParse(vLoc['lng'].toString()) ?? 0.0;
      if (vLat != 0 && vLng != 0) {
        distanceKm = _getHaversineDistance(vLat, vLng, lat, lng);
      }
    }
    final action = (next['action'] ?? 'fill_partial').toString();
    final reason = (next['reason'] ?? '').toString();
    final remainingStops = stops.length > 1 ? stops.length - 1 : 0;
    final rangeKm = _parseNum(fuelPlan['currentRangeKm']);
    final currentFuelL = _parseNum(fuelPlan['currentFuelLiters']);

    final t = Provider.of<LocalizationProvider>(context, listen: false);
    final isFullTank = action == 'fill_full';
    final actionLabel = isFullTank
        ? (t.t('fill_full') ?? 'Full tank')
        : (t.t('fill_partial') ?? 'Partial fill');
    final amberOrange = const Color(0xFFF59E0B);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [amberOrange.withOpacity(0.08), amberOrange.withOpacity(0.02)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: amberOrange.withOpacity(0.35), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: pump icon + name + distance pill
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: amberOrange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_gas_station, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      outletName,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (outletAddress.isNotEmpty || state.isNotEmpty)
                      Text(
                        [outletAddress, state].where((s) => s.isNotEmpty).join(', '),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: amberOrange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  (t.t('refuel_in_km') ?? 'in {distance} {unit}')
                      .replaceAll('{distance}', distanceKm.toStringAsFixed(0))
                      .replaceAll('{unit}', t.t('unit_km') ?? 'km'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: amberOrange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Fill details row
          Row(
            children: [
              _refuelStat(
                label: t.t('refuel_fill_label') ?? 'Fill',
                // For full tank → just the label, no exact litres (driver
                // doesn't pre-meter; pump auto-stops at full).
                value: isFullTank ? actionLabel : '${fillLiters.toStringAsFixed(0)} ${t.t('unit_litre_short') ?? 'L'}',
                sub: isFullTank ? null : actionLabel,
              ),
              _refuelStat(label: '₹/${t.t('unit_litre_short') ?? 'L'}', value: '₹${pricePerLiter.toStringAsFixed(1)}'),
              _refuelStat(
                label: t.t('refuel_total_label') ?? 'Total',
                value: '₹${fillCostInr.toStringAsFixed(0)}',
                highlight: true,
              ),
            ],
          ),
          if (currentFuelL != null && rangeKm != null) ...[
            const SizedBox(height: 10),
            Text(
              (t.t('current_fuel_format') ?? 'Current fuel: {liters} {unit} (~{range} {kmUnit} range)')
                  .replaceAll('{liters}', currentFuelL.toStringAsFixed(0))
                  .replaceAll('{unit}', t.t('unit_litre_short') ?? 'L')
                  .replaceAll('{range}', rangeKm.toStringAsFixed(0))
                  .replaceAll('{kmUnit}', t.t('unit_km') ?? 'km')
              + (remainingStops > 0
                  ? (remainingStops == 1
                      ? (t.t('more_stops_after') ?? '· {n} more stop after this')
                      : (t.t('more_stops_after_pl') ?? '· {n} more stops after this')
                    ).replaceAll('{n}', '$remainingStops').replaceAll('· ', ' · ')
                  : ''),
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              reason,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
          const SizedBox(height: 14),
          // Navigate only — manual Skip removed by design. The auto-skip
          // worker (server-side, 90 s tick) detects when the truck has
          // projected past a planned pump by ≥5 km and auto-blocklists it,
          // triggering an immediate replan. Driver gets the next-best
          // alternate on the next dashboard tick without any tap.
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (lat != 0 && lng != 0)
                  ? () {
                      final truck = _vehicleLatLng();
                      _launchMapsNavigation(lat, lng, outletName,
                          originLat: truck?[0], originLng: truck?[1]);
                    }
                  : null,
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: Text(t.t('action_navigate') ?? 'Navigate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: amberOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _refuelStat({required String label, required String value, String? sub, bool highlight = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: highlight
                  ? const Color(0xFF047857)
                  : Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Find the next stop the driver is heading to — first one whose status
  /// is not completed / departed / skipped. Returns the original index in
  /// `route_stops` so navigation deep-links to the right coords.
  Map<String, dynamic>? _nextPendingStop() {
    final raw = (_job['route_stops'] as List?) ?? const [];
    for (int i = 0; i < raw.length; i++) {
      final s = (raw[i] is Map) ? Map<String, dynamic>.from(raw[i] as Map) : null;
      if (s == null) continue;
      final status = (s['status'] ?? 'pending').toString().toLowerCase();
      if (status == 'completed' || status == 'departed' || status == 'skipped') {
        continue;
      }
      s['__index'] = i;
      return s;
    }
    return null;
  }

  /// Launch turn-by-turn navigation in the driver's installed maps app
  /// (Google Maps, then Apple Maps as fallback) for the next pending stop.
  /// Any planned fuel stops between current GPS and that user stop are
  /// included as waypoints so the driver doesn't have to re-route at each
  /// pump — Google Maps chains them in a single nav session.
  Future<void> _navigateToNextStop() async {
    final next = _nextPendingStop();
    if (next == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending stop to navigate to.')),
      );
      return;
    }
    final lat = double.tryParse((next['lat'] ?? next['latitude']).toString());
    final lng = double.tryParse((next['lng'] ?? next['longitude']).toString());
    if (lat == null || lng == null || (lat == 0 && lng == 0)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stop coordinates missing.')),
      );
      return;
    }
    final label = (next['address'] ?? next['label'] ?? 'Stop ${(next['__index'] ?? 0) + 1}').toString();
    final fuelWaypoints = _fuelWaypointsTo(next);
    if (fuelWaypoints.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Routing via ${fuelWaypoints.length} planned fuel stop${fuelWaypoints.length == 1 ? '' : 's'}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    // Anchor the route at the truck's current location, not the phone's GPS.
    // When the driver has stepped away from the truck (parked, refuelling
    // outside the cab, etc.) Google Maps' default behaviour of using the
    // phone GPS as origin produces nonsense directions — distance and ETA
    // start from wherever the driver is standing instead of from the truck
    // that's actually going to drive the route.
    final truckLatLng = _vehicleLatLng();
    await _launchMapsNavigation(
      lat,
      lng,
      label,
      waypoints: fuelWaypoints,
      originLat: truckLatLng?[0],
      originLng: truckLatLng?[1],
    );
  }

  /// Open the 24-hour history sheet for a tank/gauge metric.
  void _openTankHistory({
    required String metric,
    required String label,
    required String unit,
    required Color color,
  }) {
    final jobId = _job['id']?.toString();
    if (jobId == null || jobId.isEmpty) return;
    TankHistorySheet.open(
      context,
      jobId: jobId,
      metric: metric,
      label: label,
      unit: unit,
      color: color,
    );
  }

  /// Generic gauge for raw sensor values like battery voltage (V) and exhaust
  /// temperature (°C). Unlike [_buildPremiumGauge] (which derives % from
  /// capacity), this maps `value` to a fraction of `[arcMin, arcMax]` and
  /// thresholds the arc color via [colorFor]. Renders "—" when [value] is null.
  Widget _buildMetricGauge({
    required String label,
    required num? value,
    required String unit,
    required double arcMin,
    required double arcMax,
    required IconData icon,
    required Color Function(num? v) colorFor,
    int decimals = 1,
  }) {
    final color = colorFor(value);
    double arcValue = 0;
    if (value != null && arcMax > arcMin) {
      arcValue = ((value.toDouble() - arcMin) / (arcMax - arcMin)).clamp(0.0, 1.0);
    }

    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
          BoxShadow(color: color.withOpacity(0.05), blurRadius: 10, spreadRadius: 0),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 100,
            width: 100,
            child: Stack(
              children: [
                SizedBox(
                  height: 100,
                  width: 100,
                  child: CircularProgressIndicator(
                    value: 1.0,
                    color: color.withOpacity(0.1),
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                SizedBox(
                  height: 100,
                  width: 100,
                  child: CircularProgressIndicator(
                    value: arcValue,
                    color: color,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (value != null) ...[
                        Text(
                          value.toDouble().toStringAsFixed(decimals),
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                            height: 1.0,
                          ),
                        ),
                        Text(
                          unit,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.55),
                            fontWeight: FontWeight.w600,
                            height: 1.0,
                          ),
                        ),
                      ] else ...[
                        Icon(icon, size: 22, color: color.withOpacity(0.7)),
                        const SizedBox(height: 2),
                        Text(
                          '—',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(label, style: AppTextStyles.label.copyWith(fontSize: 13, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildPremiumGauge(String label, num percent, num capacity, Color color, IconData icon) {
      final t = Provider.of<LocalizationProvider>(context);
      double liters = 0;
      if (capacity > 0) {
          liters = (percent / 100.0) * capacity;
      }

      return Container(
        width: 140, // Fixed width for stability
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
            BoxShadow(color: color.withOpacity(0.05), blurRadius: 10, spreadRadius: 0), 
          ]
        ),
        child: Column(
          children: [
            SizedBox(
              height: 100,
              width: 100,
              child: Stack(
                children: [
                  // Background Track
                  SizedBox(
                    height: 100,
                    width: 100,
                    child: CircularProgressIndicator(
                      value: 1.0,
                      color: color.withOpacity(0.1),
                      strokeWidth: 8,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  // Progress Arc
                  SizedBox(
                    height: 100,
                    width: 100,
                    child: CircularProgressIndicator(
                      value: percent / 100,
                      color: color,
                      strokeWidth: 8,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  // Center Content
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon removed to save space for larger text, or keep it very small/subtle?
                        // User wants to highlight actual value.
                        
                        if (capacity > 0) ...[
                           Text(
                            "${liters.toStringAsFixed(0)}",
                            style: GoogleFonts.outfit(
                              fontSize: 28, // Bigger
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                              height: 1.0
                            ),
                          ),
                          Text(
                            t.t('liters'),
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.5),
                              fontWeight: FontWeight.w500,
                              height: 1.0
                            ),
                          ),
                        ] else ...[
                           // Fallback if no capacity
                           Icon(icon, size: 16, color: color.withOpacity(0.8)),
                           Text(
                            "$percent%",
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                           ),
                        ]
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(label, style: AppTextStyles.label.copyWith(fontSize: 13, letterSpacing: 0.5)),
          ],
        ),
      );
  }

  Widget _buildTimelineSection(BuildContext context, double progress) {
    // Custom Graphical Route Tracker
    // Calculate proportional stops
    List<Map<String, dynamic>>? timelineStops;
    final rawStops = (_job['route_stops'] as List?)?.cast<Map<String, dynamic>>();
    
    if (rawStops != null && rawStops.isNotEmpty) {
        double totalDist = 0.0;
        List<double> stopDists = [];
        
        // Origin
        double lastLat = _parseNum(_job['origin_latitude'])?.toDouble() ?? 0.0;
        double lastLng = _parseNum(_job['origin_longitude'])?.toDouble() ?? 0.0;
        
        // If origin missing, use first stop as 0? No, try best effort.
        // If origin is 0,0, maybe used vehicle start location? 
        // For now assume valid origin or 0 distances.
        
        for (var s in rawStops) {
            double sLat = _parseNum(s['lat'])?.toDouble() ?? _parseNum(s['latitude'])?.toDouble() ?? 0.0;
            double sLng = _parseNum(s['lng'])?.toDouble() ?? _parseNum(s['longitude'])?.toDouble() ?? 0.0;
            
            if (lastLat != 0 && lastLng != 0 && sLat != 0 && sLng != 0) {
                double d = _getHaversineDistance(lastLat, lastLng, sLat, sLng);
                totalDist += d;
            }
            stopDists.add(totalDist);
            
            // Update last
            if (sLat != 0 && sLng != 0) {
                lastLat = sLat;
                lastLng = sLng;
            }
        }
        
        // Normalize
        timelineStops = rawStops.asMap().entries.map((entry) {
            int idx = entry.key;
            Map<String, dynamic> s = Map.from(entry.value);
            double d = stopDists[idx];
            // If totalDist is small (e.g. single stop at origin), default to 1.0 or 0.0
            // Ideally, last stop should be at 1.0
            double pct = (totalDist > 0.5) ? (d / totalDist) : (idx / (rawStops.length > 1 ? rawStops.length - 1 : 1)); 
            s['proportional_position'] = pct.clamp(0.0, 1.0);
            return s;
        }).toList();
    }

    return RouteTimelineWidget(
        progress: progress,
        activeColor: AppColors.primary,
        inactiveColor: Theme.of(context).dividerColor,
        stops: timelineStops,
        onStopTap: _onStopTimelineTap,
        selectedStopIndex: _selectedStopIndex,
    );
  }

  /// Whether to render the "Vehicle X km away" banner. We need:
  ///  - the driver's GPS (geolocator stream),
  ///  - the vehicle's last known location (from dashboard telemetry),
  ///  - separation > 1 km.
  bool _shouldShowVehicleLocator() {
    // Always show the Navigate-to-vehicle banner whenever we know where the
    // truck is — the driver may need to head to it even before their own
    // GPS has locked on. The visual is tuned in _buildVehicleLocatorBanner
    // for 3 zones: missing-driver-gps, 1–5 km (normal), >5 km (urgent).
    final v = _vehicleLatLng();
    if (v == null) return false;
    if (_driverPos == null) return true;
    final km = _getHaversineDistance(_driverPos!.latitude, _driverPos!.longitude, v[0], v[1]);
    return km > 1.0;
  }

  List<double>? _vehicleLatLng() {
    final loc = _dashboardData?['vehicle']?['location'];
    if (loc == null) return null;
    final lat = double.tryParse(loc['lat'].toString()) ?? 0.0;
    final lng = double.tryParse(loc['lng'].toString()) ?? 0.0;
    if (lat == 0 && lng == 0) return null;
    return [lat, lng];
  }

  /// Banner shown when the driver is > 1 km from the vehicle (typical case:
  /// a job was just assigned and the driver hasn't reached the truck yet).
  /// Tap "Navigate" → opens Google Maps with the truck's lat/lng as the
  /// destination. No push notification — banner is the only signal so the
  /// driver isn't getting nagged on lock-screen for moving away.
  Widget _buildVehicleLocatorBanner() {
    final t = Provider.of<LocalizationProvider>(context, listen: false);
    final v = _vehicleLatLng();
    if (v == null) return const SizedBox.shrink();
    final km = _driverPos == null
        ? null
        : _getHaversineDistance(_driverPos!.latitude, _driverPos!.longitude, v[0], v[1]);
    final distLabel = km == null
        ? '—'
        : (km < 10
            ? '${km.toStringAsFixed(1)} ${t.t('unit_km') ?? 'km'}'
            : '${km.toStringAsFixed(0)} ${t.t('unit_km') ?? 'km'}');
    final reg = (_dashboardData?['vehicle']?['registration_number']
            ?? _job['vehicle_registration']
            ?? _job['vehicle_name']
            ?? t.t('vehicle_locator_title') ?? 'Vehicle')
        .toString();
    final isFar = km != null && km > 5.0;
    final accent = isFar ? const Color(0xFFEF4444) : AppColors.primary;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.30),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.local_shipping, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isFar
                        ? (t.t('vehicle_far_label') ?? 'TOO FAR FROM TRUCK')
                        : (t.t('vehicle_away_label') ?? 'VEHICLE LOCATION'),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    km == null
                        ? '$reg · ${t.t('vehicle_locator_subtitle') ?? 'Tap Navigate to head to it'}'
                        : '$reg · $distLabel ${t.t('away_suffix') ?? 'away'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => _launchMapsNavigation(v[0], v[1], reg),
              icon: const Icon(Icons.directions, size: 16),
              label: Text(t.t('action_navigate') ?? 'Navigate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: accent,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Always-on inline banner that sits above the bottom sheet whenever the
  /// next planned fuel stop is within 5 km. Goes orange + flashes inside
  /// 2 km (paired with the one-shot haptic + system tone fired from
  /// `_updateFuelProximity`).
  Widget _buildFuelProximityBanner() {
    final t = Provider.of<LocalizationProvider>(context, listen: false);
    final stop = _fuelProxStop ?? const {};
    final km = _fuelProxKm ?? 0;
    final outletName = (stop['outletName'] ?? 'Fuel Stop').toString();
    final pricePerL = double.tryParse((stop['pricePerLiter'] ?? '').toString());
    final fillL = double.tryParse((stop['fillLiters'] ?? '').toString());
    final isFullTank = (stop['action'] ?? '').toString() == 'fill_full';
    final isUrgent = km <= 2.0;
    final litreShort = t.t('unit_litre_short') ?? 'L';

    final accent = isUrgent ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    final kmUnit = t.t('unit_km') ?? 'km';
    final distLabel = km < 1
        ? '${(km * 1000).round()} m'
        : '${km.toStringAsFixed(km < 10 ? 1 : 0)} $kmUnit';
    final headerKey = isUrgent ? 'fuel_stop_ahead' : 'approaching_fuel_stop';
    final headerTpl = t.t(headerKey) ?? (isUrgent ? 'FUEL STOP — {distance} AHEAD' : 'Approaching fuel stop · {distance}');
    final header = headerTpl.replaceAll('{distance}', distLabel);

    return Material(
      color: Colors.transparent,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.95, end: isUrgent ? 1.0 : 1.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.45),
                blurRadius: isUrgent ? 24 : 12,
                spreadRadius: isUrgent ? 2 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_gas_station, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      header,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      outletName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (pricePerL != null)
                      Text(
                        isFullTank
                            ? '${t.t('fill_full') ?? 'Full tank'} · ₹${pricePerL.toStringAsFixed(1)}/$litreShort'
                            : (fillL != null
                                ? '${fillL.toStringAsFixed(0)} $litreShort @ ₹${pricePerL.toStringAsFixed(1)}/$litreShort'
                                : '₹${pricePerL.toStringAsFixed(1)}/$litreShort'),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () {
                  final lat = double.tryParse(stop['lat'].toString());
                  final lng = double.tryParse(stop['lng'].toString());
                  if (lat != null && lng != null) {
                    final truck = _vehicleLatLng();
                    _launchMapsNavigation(lat, lng, outletName,
                        originLat: truck?[0], originLng: truck?[1]);
                  }
                },
                icon: const Icon(Icons.directions, color: Colors.white),
                tooltip: t.t('action_navigate') ?? 'Navigate',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact next-stop card pinned at the top of the bottom sheet. Always
  /// visible so the driver sees the destination + a Navigate shortcut without
  /// having to scroll. Returns a placeholder gap when there's no pending
  /// stop (job complete) so the sheet layout stays stable.
  Widget _buildNextStopStrip() {
    final t = Provider.of<LocalizationProvider>(context, listen: false);
    final stops = (_job['route_stops'] as List?) ?? const [];
    if (stops.isEmpty) return const SizedBox.shrink();

    final next = _nextPendingStop();
    if (next == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t.t('all_stops_done') ?? 'All stops handled — head back or complete the trip.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final idx = next['__index'] as int? ?? 0;
    final type = (next['type'] ?? next['stop_type'] ?? next['activity'] ?? '').toString().toLowerCase();
    final address = (next['address'] ?? next['label'] ?? 'Stop ${idx + 1}').toString();
    final state = (next['state'] ?? '').toString();
    final stopLetter = String.fromCharCode(65 + idx);

    Color typeColor;
    IconData typeIcon;
    String typeLabel;
    if (type == 'loading') {
      typeColor = Colors.green;
      typeIcon = Icons.upload;
      typeLabel = t.t('next_loading') ?? 'NEXT · LOADING';
    } else if (type == 'unloading') {
      typeColor = Colors.orange;
      typeIcon = Icons.download;
      typeLabel = t.t('next_unloading') ?? 'NEXT · UNLOADING';
    } else {
      typeColor = AppColors.primary;
      typeIcon = Icons.place;
      typeLabel = idx == stops.length - 1
          ? (t.t('next_destination') ?? 'NEXT · DESTINATION')
          : (t.t('next_stop') ?? 'NEXT · STOP');
    }

    // Distance to this stop from current vehicle location.
    String? distLabel;
    final vLoc = _dashboardData?['vehicle']?['location'];
    if (vLoc != null) {
      final vLat = double.tryParse(vLoc['lat'].toString()) ?? 0.0;
      final vLng = double.tryParse(vLoc['lng'].toString()) ?? 0.0;
      final sLat = double.tryParse((next['lat'] ?? next['latitude']).toString()) ?? 0.0;
      final sLng = double.tryParse((next['lng'] ?? next['longitude']).toString()) ?? 0.0;
      if (vLat != 0 && vLng != 0 && sLat != 0 && sLng != 0) {
        final km = _getHaversineDistance(vLat, vLng, sLat, sLng);
        final awayWord = t.t('away_suffix') ?? 'away';
        if (km < 1) {
          distLabel = '${(km * 1000).round()} m $awayWord';
        } else {
          distLabel = '${km.toStringAsFixed(km < 10 ? 1 : 0)} ${t.t('unit_km') ?? 'km'} $awayWord';
        }
      }
    }

    return InkWell(
      onTap: () => _onStopTimelineTap(idx),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: typeColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: typeColor.withOpacity(0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: typeColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(typeIcon, color: Colors.white, size: 18),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Text(
                      stopLetter,
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          typeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700,
                            color: typeColor,
                          ),
                        ),
                      ),
                      if (distLabel != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 3, height: 3,
                          decoration: BoxDecoration(color: Theme.of(context).hintColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            distLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  if (state.isNotEmpty)
                    Text(
                      state,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _navigateToNextStop,
              icon: const Icon(Icons.directions, size: 16),
              label: Text(t.t('go_button') ?? 'Go'),
              style: ElevatedButton.styleFrom(
                backgroundColor: typeColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }


  IconData _getActionIcon(String actionOrLabel) {
    final lower = actionOrLabel.toLowerCase();
    if (lower.contains('reach') || lower.contains('arrive')) return Icons.location_on;
    if (lower.contains('start') || lower.contains('load') && !lower.contains('unload')) return Icons.upload; // Loading
    if (lower.contains('unload')) return Icons.download;
    if (lower.contains('depart')) return Icons.arrow_forward;
    if (lower.contains('finish') || lower.contains('loaded') || lower.contains('unloaded')) return Icons.check_circle;
    return Icons.play_arrow;
  }

  String _getLocalizedActionLabel(Map<String, dynamic> act, LocalizationProvider t) {
    final action = act['action'] as String;
    final rawLabel = (act['label'] as String? ?? '').toLowerCase();

    if (action == 'reached') {
        return t.t('action_reached') ?? 'Arrived';
    }
    if (action == 'depart') {
        return t.t('action_departed') ?? 'Depart';
    }
    if (action == 'start_action') {
        if (rawLabel.contains('unload')) return t.t('action_unloading') ?? 'Start Unloading';
        return t.t('action_loading') ?? 'Start Loading';
    }
    if (action == 'complete_action') {
        if (rawLabel.contains('unload')) return t.t('action_unloaded') ?? 'Finished Unloading';
        return t.t('action_loaded') ?? 'Finished Loading';
    }
    
    // Fallback: If label looks like a key (has underscores), try to translate it directly
    if (rawLabel.contains('_')) {
        final translated = t.t(rawLabel);
        if (translated != null && translated != rawLabel) return translated;
    }

    return act['label'] ?? action;
  }
}
