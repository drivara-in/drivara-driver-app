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
import 'api_config.dart';
import 'providers/localization_provider.dart';
import 'no_job_page.dart';
import 'login_page.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'services/job_stream_service.dart';
import 'services/find_fuel_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ActiveJobPage extends StatefulWidget {
  final Map<String, dynamic> job;
  const ActiveJobPage({super.key, required this.job});

  @override
  State<ActiveJobPage> createState() => _ActiveJobPageState();
}

class _ActiveJobPageState extends State<ActiveJobPage> {
  late Map<String, dynamic> _job;
  Map<String, dynamic>? _dashboardData;
  bool _isLoading = false;
  bool _isActionLoading = false;
  List<Map<String, dynamic>>? _fuelStations;

  JobStreamService? _streamService;
  StreamSubscription? _streamSubscription;
  final GlobalKey<dynamic> _mapKey = GlobalKey(); // Using dynamic to access state methods loosely or type it if possible

  @override
  void initState() {
    super.initState();
    _job = widget.job;
    // Initial fetch for loading state
    _fetchDashboardData().then((_) {
       _connectStream();
    });
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _streamService?.dispose();
    super.dispose();
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
           
           final vehicle = _dashboardData?['vehicle'] ?? {};
           vehicle['location'] = {
              'lat': (data['lat'] as num?)?.toDouble() ?? 0.0,
              'lng': (data['lng'] as num?)?.toDouble() ?? 0.0,
              'heading': (data['heading'] as num?)?.toDouble() ?? 0.0
           };
           vehicle['speed_kmh'] = data['speed'] ?? 0;
           vehicle['odometer_km'] = data['odometer'] ?? vehicle['odometer_km'];
           
           // Robust parsing for Int gauges
           if (data['fuel_level'] != null) {
               vehicle['fuel_level_percent'] = (data['fuel_level'] as num).toInt(); 
           }
           if (data['def_level'] != null) {
               vehicle['def_level_percent'] = (data['def_level'] as num).toInt();
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
              // Simple ETA recalc if needed or trust server stream eventually
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
        debugPrint("DASHBOARD DATA: Vehicle: ${_dashboardData?['vehicle']}"); // Debug Initial Data
        if (_dashboardData?['job'] != null) {
            _job = _dashboardData!['job'];
        }
      });
    } catch (e) {
      debugPrint("Error fetching dashboard: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(String action) async {
    setState(() => _isActionLoading = true);
    try {
      final response = await ApiConfig.dio.post('/driver/jobs/${_job['id']}/$action');
      if (!mounted) return;
      if (response.data['ok'] == true) {
        if (action == 'complete') {
           Navigator.of(context).pushAndRemoveUntil(
             MaterialPageRoute(builder: (_) => const NoJobPage()), 
             (route) => false
           );
        } else {
          _fetchDashboardData(); // Refresh all data
        }
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
    
    // Check Client-side Haversine (Crow Flies) check if Server Value is suspicious
    final vLoc = vehicle['location']; // { lat: ..., lng: ... } 
    final dLat = double.tryParse(_job['destination_latitude']?.toString() ?? '');
    final dLng = double.tryParse(_job['destination_longitude']?.toString() ?? '');
    
    if (vLoc != null && vLoc['lat'] != null && vLoc['lng'] != null && dLat != null && dLng != null) {
         final vLat = double.tryParse(vLoc['lat'].toString()) ?? 0;
         final vLng = double.tryParse(vLoc['lng'].toString()) ?? 0;
         
         if (vLat != 0 && vLng != 0) {
             final hDist = _getHaversineDistance(vLat, vLng, dLat, dLng);
             
             // If Direct (Server) is way larger than Haversine (e.g. stuck at start vs near end), prefer Haversine
             // This fixes the issue where Server returns Total Route Distance as remaining.
             if (direct == null || (direct > hDist + 50)) {
                  direct = double.parse(hDist.toStringAsFixed(1));
             }
         }
    }

    if (direct != null) {
        distanceRemaining = direct;
    } else if (routeDistance != null && routeDistance > 0) {
        distanceRemaining = (routeDistance - distanceCovered).clamp(0, double.infinity);
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
                              final lat = (vLoc['lat'] as num).toDouble();
                              final lng = (vLoc['lng'] as num).toDouble();
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
                                           // Only show if there is a co-driver (Commented out for debugging/freedom)
                                           // if (_job['secondary_driver_id'] == null) return const SizedBox.shrink();

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
                                      _buildPremiumGauge(t.t('fuel_level'), vehicle['fuel_level_percent'] ?? 0, vehicle['fuel_tank_capacity'] ?? 0, Colors.greenAccent, Icons.local_gas_station),
                                      _buildPremiumGauge(t.t('def_level'), vehicle['def_level_percent'] ?? 0, vehicle['def_tank_capacity'] ?? 0, Colors.blueAccent, Icons.opacity),
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
                                                   Text("${distanceCovered.toStringAsFixed(1)} km", style: AppTextStyles.header.copyWith(fontSize: 16, color: Theme.of(context).textTheme.bodyLarge?.color)),
                                                 ],
                                               ),
                                               Column(
                                                 crossAxisAlignment: CrossAxisAlignment.end,
                                                 children: [
                                                   Text(t.t('distance_remaining'), style: AppTextStyles.body.copyWith(color: Theme.of(context).textTheme.bodyMedium?.color)),
                                                   Text("${distanceRemaining.toStringAsFixed(1)} km", style: AppTextStyles.header.copyWith(fontSize: 16, color: Theme.of(context).textTheme.bodyLarge?.color)),
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

                           // Action Button
                           if (!isStarted)
                             ElevatedButton.icon(
                                 onPressed: _isActionLoading ? null : () => _updateStatus('start'),
                                 icon: const Icon(Icons.play_arrow),
                                 label: Text(t.t('start_trip')),
                                 style: AppTheme.darkTheme.elevatedButtonTheme.style!.copyWith(
                                     backgroundColor: MaterialStateProperty.all(AppColors.success),
                                 ),
                             )
                           else 
                             Container(
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
                                         ],
                                     ),
                                 ),
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
}
