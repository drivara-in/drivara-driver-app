import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:drivara_driver_app/widgets/live_job_map.dart';
import 'package:lottie/lottie.dart';
import 'package:drivara_driver_app/widgets/route_timeline.dart';
import 'package:drivara_driver_app/widgets/add_expense_sheet.dart';
import 'package:drivara_driver_app/widgets/expense_list_sheet.dart';
import 'package:drivara_driver_app/widgets/action_button_card.dart';
import 'package:drivara_driver_app/widgets/stop_action_sheet.dart';
import 'package:drivara_driver_app/pages/tyre_management_page.dart';
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

  // Reminder State (retained as it's used in _connectStream)
  DateTime? _stoppedSince;
  bool _reminderSent = false;

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _disconnectStream();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("App Resumed: Restarting Services & Checking Job...");
      _checkGlobalJobStatus(); // Immediate check
      
      // Resume Services
      if (_poller == null || !_poller!.isActive) _startPolling();
      if (_streamService == null || _streamSubscription == null) _connectStream();
      
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      debugPrint("App Paused: Suspending Services (Battery Saving Mode)...");
      _stopPolling();
      _disconnectStream();
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
           newVehicle['odometer_km'] = data['odometer'] ?? newVehicle['odometer_km'];
           
           if (_dashboardData == null) _dashboardData = {};
           _dashboardData!['vehicle'] = newVehicle;

           // Use newVehicle for local checks below
           final vehicle = newVehicle;

           // --- Reminder Logic ---
           try {
              final double speed = _parseNum(data['speed'])?.toDouble() ?? 0.0;
              final bool? ignition = data['ignition'] is bool ? data['ignition'] : data['ignition'].toString().toLowerCase() == 'true';
              final List actions = data['available_actions'] ?? [];

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

           // Re-assign to trigger UI update
           _dashboardData = {
              'job': _job, // static for now
              'vehicle': vehicle,
              'balances': balances,
              'route': route, 
           };
           
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

  Future<void> _updateStatus(String action, {Map<String, dynamic>? body}) async {
    // Defines actions that require the Sheet
    const sheetActions = ['reached', 'start_action', 'complete_action', 'depart', 'complete'];

    if (sheetActions.contains(action) && body != null && body['stopIndex'] != null) {
        final stopIndex = body['stopIndex'] as int;
        // Config Sheet
        String title = "Confirm Action";
        String uploadLabel = "Proof (Optional)";
        bool requireFile = false;

        if (action == 'reached') {
           title = "Confirm Arrival";
           uploadLabel = "Gate Entry / Proof";
        } else if (action == 'start_action') {
           title = "Start Activity"; 
        } else if (action == 'complete_action') {
           title = "Complete Activity"; 
           uploadLabel = "Upload POD / Receipt";
           requireFile = false; 
        } else if (action == 'depart') {
           title = "Confirm Departure";
        } else if (action == 'complete') {
           title = "Complete Trip";
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
             Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const NoJobPage()));
             return;
         }
         else if (action == 'reached') msg = t.t('location_reached');
         else if (action == 'start_action') msg = t.t('loading_started'); 
         else if (action == 'complete_action') msg = t.t('loading_completed');
         else if (action == 'depart') msg = t.t('departed');

         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
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
                              // Vehicle ID check
                              if (v['id'] == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vehicle details not fully loaded yet")));
                                  return;
                              }
                              
                              Navigator.push(context, MaterialPageRoute(builder: (_) => TyreManagementPage(
                                  vehicleId: v['id'],
                                  registrationNumber: v['registrationNumber'] ?? 'Unknown'
                              )));
                           } else {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please wait for dashboard data...")));
                           }
                        },
                        mini: true,
                        backgroundColor: Colors.blueGrey,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.settings_suggest, color: Colors.white),
                   ),
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
                           const SizedBox(height: 16),
                           // Handle Bar
                           Center(
                             child: Container(
                               width: 40, height: 4,
                               margin: const EdgeInsets.only(bottom: 20),
                               decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                             ),
                           ),

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
                               child: Row(
                                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                   children: [
                                       _buildPremiumGauge(t.t('fuel_level'), _parseNum(vehicle['fuel_level_percent'] ?? vehicle['fuel_level'])?.toInt() ?? 0, _parseNum(vehicle['fuel_tank_capacity']) ?? 0, Colors.greenAccent, Icons.local_gas_station),
                                       _buildPremiumGauge(t.t('def_level'), _parseNum(vehicle['def_level_percent'] ?? vehicle['def_level'])?.toInt() ?? 0, _parseNum(vehicle['def_tank_capacity']) ?? 0, Colors.blueAccent, Icons.opacity),
                                   ],
                               ),
                            ),
                            const SizedBox(height: 24),

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
                                       RouteTimelineWidget(
                                           progress: progress, 
                                           activeColor: AppColors.primary,
                                           inactiveColor: Theme.of(context).dividerColor,
                                           stops: (_job['route_stops'] as List?)?.cast<Map<String, dynamic>>(),
                                           onStopTap: _onStopTimelineTap,
                                           selectedStopIndex: _selectedStopIndex,
                                       ),
                                       
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
                                subtitle: "Swipe to begin your journey",
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
                                                // Show warning or empty actions
                                                return Padding(
                                                  padding: const EdgeInsets.all(16.0),
                                                  child: Column(
                                                    children: [
                                                       Text("Cannot update previous stop", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                                       Text("You have already proceeded to a later stop.", style: TextStyle(color: Colors.grey)),
                                                       TextButton(
                                                           onPressed: () => setState(() => _selectedStopIndex = null),
                                                           child: const Text("Cancel")
                                                       )
                                                    ],
                                                  ),
                                                );
                                            }

                                           
                                           if (status == 'pending') {
                                                // Always allow Reached
                                                String label = 'Arrived';
                                                if (type == 'loading') label = t.t('reached_loading_point') ?? 'Reached Loading Point';
                                                else if (type == 'unloading') label = t.t('reached_unloading_point') ?? 'Reached Unloading Point';
                                                
                                                actions.add({'action': 'reached', 'label': label, 'stopIndex': _selectedStopIndex});
                                           } else if (status == 'reached') {
                                                if (type == 'loading' && stop['action_completed_at'] == null) {
                                                    // Always allow Start Loading
                                                    actions.add({'action': 'start_action', 'label': t.t('action_loading') ?? 'Load', 'stopIndex': _selectedStopIndex});
                                                } else if (type == 'unloading' && stop['action_completed_at'] == null) {
                                                    // Always allow Start Unloading
                                                    actions.add({'action': 'start_action', 'label': t.t('action_unloading') ?? 'Unload', 'stopIndex': _selectedStopIndex});
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
                                            } else if (status == 'action_in_progress') {
                                                // Restriction applies to Complete (EPOD)
                                                if (!tooFar) {
                                                    String label = type == 'loading' ? (t.t('action_loaded') ?? 'Loaded') : (t.t('action_unloaded') ?? 'Unloaded');
                                                    actions.add({'action': 'complete_action', 'label': label, 'stopIndex': _selectedStopIndex});
                                                }
                                            }
                                       }
                                   } else {
                                    // 2. Default: SSE Data
                                       actions = (_dashboardData?['route'] != null && _dashboardData!['route']['available_actions'] != null) 
                                          ? (_dashboardData!['route']['available_actions'] as List).cast<Map<String, dynamic>>()
                                          : <Map<String, dynamic>>[];
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
                                                  String sub = "Tap to proceed";
                                                  
                                                  final actionCode = act['action'] as String;
                                                  if (actionCode == 'reached') {
                                                     btnColor = Colors.blue.shade700;
                                                     sub = "Confirm arrival at location";
                                                  } else if (actionCode.contains('start_action')) {
                                                      btnColor = Colors.orange.shade700;
                                                      final lowerLabel = (act['label'] as String? ?? '').toLowerCase();
                                                      sub = lowerLabel.contains('unload') ? "Unloading" : "Loading";
                                                  } else if (actionCode.contains('complete_action')) {
                                                     btnColor = Colors.green.shade700;
                                                     sub = "Finish task & Upload POD";
                                                  } else if (actionCode == 'depart') {
                                                     btnColor = Colors.purple.shade700;
                                                     sub = "Leave location for next stop";
                                                  } else if (actionCode == 'complete') {
                                                      btnColor = Colors.green; 
                                                      sub = "Complete Trip";
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
                                                         _updateStatus(act['action'], body: {'stopIndex': act['stopIndex'], 'force': isManual});
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
                                   
                                   bool showDistanceWarning = tooFar && !_isReadyToComplete();

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
                                                   if (_selectedStopIndex != null) ...[
                                                        Icon(showDistanceWarning ? Icons.error_outline : Icons.info_outline, color: showDistanceWarning ? Colors.orangeAccent : Colors.white),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                            showDistanceWarning 
                                                              ? "Distance: ${distKm.toStringAsFixed(1)} km > ${kAllowedActionRadiusKm.toStringAsFixed(0)} km\nYou are too far from the location."
                                                              : "Stop ${_selectedStopIndex! + 1}: ${stopStatus.toUpperCase()}", 
                                                            style: AppTextStyles.header.copyWith(fontSize: 16),
                                                            textAlign: TextAlign.center,
                                                        ),
                                                        const SizedBox(width: 8),
                                                        TextButton(
                                                            onPressed: () => setState(() => _selectedStopIndex = null),
                                                            child: const Text("Back", style: TextStyle(color: Colors.white70))
                                                        )
                                                   ] else ...[
                                                       Lottie.network(
                                                         'https://lottie.host/98692795-0373-455f-8706-53867664871e/9R1k6e3v41.json', 
                                                         width: 40, 
                                                         height: 40,
                                                         errorBuilder: (context, error, stackTrace) => const Icon(Icons.trip_origin, color: Colors.white),
                                                       ),
                                                       const SizedBox(width: 8),
                                                       Text(
                                                           t.t('trip_in_progress'),
                                                           style: AppTextStyles.header.copyWith(fontSize: 16),
                                                       ),
                                                   ]
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
                            icon: const Icon(Icons.logout),
                            color: Theme.of(context).iconTheme.color,
                            onPressed: () async {
                               await ApiConfig.logout();
                               if (!mounted) return;
                               Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => const LoginPage()), 
                                  (route) => false
                               );
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

  double _getHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = 
      (math.sin(dLat / 2) * math.sin(dLat / 2)) +
      math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) * 
      (math.sin(dLon / 2) * math.sin(dLon / 2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degree) {
    return degree * math.pi / 180;
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
