import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:drivara_driver_app/widgets/live_job_map.dart';
import 'package:lottie/lottie.dart';
import 'package:drivara_driver_app/widgets/route_timeline.dart';
import 'api_config.dart';
import 'providers/localization_provider.dart';
import 'no_job_page.dart';
import 'login_page.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';
import 'services/job_stream_service.dart';

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

  JobStreamService? _streamService;
  StreamSubscription? _streamSubscription;

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
        setState(() {
           // Merge stream data into dashboard data structure
           // The stream payload is flat, but dashboard expects nested structure.
           // We reconstruct it to match build() expectations.
           
           final vehicle = _dashboardData?['vehicle'] ?? {};
           vehicle['location'] = {
              'lat': data['lat'] ?? 0,
              'lng': data['lng'] ?? 0,
              'heading': data['heading'] ?? 0
           };
           vehicle['speed_kmh'] = data['speed'] ?? 0;
           vehicle['odometer_km'] = data['odometer'] ?? vehicle['odometer_km'];
           vehicle['fuel_level_percent'] = data['fuel_level'] ?? vehicle['fuel_level_percent']; // New from stream
           vehicle['def_level_percent'] = data['def_level'] ?? vehicle['def_level_percent'];   // New from stream
           
           final balances = _dashboardData?['balances'] ?? {};
           if (data['fuel_wallet_balance'] != null) balances['fuel'] = data['fuel_wallet_balance'];
           if (data['fastag_wallet_balance'] != null) balances['fastag'] = data['fastag_wallet_balance'];

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
              Text('Select Theme', style: AppTextStyles.header.copyWith(fontSize: 20, color: Theme.of(context).textTheme.bodyLarge?.color)),
              const SizedBox(height: 16),
              _buildThemeOption(themeProvider, 'System Default', ThemeMode.system, Icons.smartphone),
              _buildThemeOption(themeProvider, 'Light Mode', ThemeMode.light, Icons.wb_sunny),
              _buildThemeOption(themeProvider, 'Dark Mode', ThemeMode.dark, Icons.nightlight_round),
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
            // 1. Full Screen Map Background (Top Half)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: size.height * 0.65, // Occupy top 65%
              child: LiveJobMap(
                  job: _job,
                  vehicle: vehicle,
              ),
            ),
            
            // 2. Header Gradient for Visibility
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).scaffoldBackgroundColor.withOpacity(0.9), 
                      Theme.of(context).scaffoldBackgroundColor.withOpacity(0.0)
                    ],
                  ),
                ),
              ),
            ),



            // 4. Draggable/Scrollable Content Sheet
            Positioned.fill(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(), // Solid feel
                child: Column(
                  children: [
                    // Invisible Spacer to reveal Map
                    SizedBox(height: size.height * 0.55), 
                    
                    // The "Sheet"
                    Container(
                      constraints: BoxConstraints(minHeight: size.height * 0.5),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                        boxShadow: [
                           BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))
                        ]
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           // Handle Bar (Visual cue)
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
                                  child: Text(
                                    _job['title'] ?? 'Job #${_job['id']}', 
                                    style: AppTextStyles.header.copyWith(fontSize: 24, color: Theme.of(context).textTheme.bodyLarge?.color),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    color: Theme.of(context).cardTheme.color,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Theme.of(context).dividerColor)
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                        const Icon(Icons.stars, color: Colors.amber, size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                            t.t('primary_driver'), 
                                            style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodyMedium?.color),
                                        ),
                                    ]
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
                                                         _job['origin_address']?.split(',')[0] ?? 'Start', 
                                                         style: AppTextStyles.label.copyWith(fontWeight: FontWeight.bold, fontSize: 12),
                                                         maxLines: 1, overflow: TextOverflow.ellipsis
                                                       ),
                                                       Text(t.t('start_location'), style: AppTextStyles.label.copyWith(fontSize: 10, color: Colors.grey)),
                                                    ]
                                                 ),
                                               ),
                                               Expanded(
                                                 child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                       Text(
                                                         _job['destination_address']?.split(',')[0] ?? 'End', 
                                                         style: AppTextStyles.label.copyWith(fontWeight: FontWeight.bold, fontSize: 12),
                                                         maxLines: 1, overflow: TextOverflow.ellipsis
                                                       ),
                                                       Text(t.t('destination_location'), style: AppTextStyles.label.copyWith(fontSize: 10, color: Colors.grey)),
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
                  ],
                ),
              ),
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
                          Image.asset('assets/images/drivara-icon.png', height: 40, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("Drivara", style: AppTextStyles.header.copyWith(fontSize: 18, height: 1, color: Theme.of(context).textTheme.bodyLarge?.color)),
                              Text("DRIVER", style: AppTextStyles.label.copyWith(fontSize: 10, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6), letterSpacing: 2)),
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

  Widget _buildPremiumGauge(String label, int percent, num capacity, Color color, IconData icon) {
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
