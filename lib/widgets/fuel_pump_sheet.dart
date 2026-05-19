import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/localization_provider.dart';
import '../services/find_fuel_service.dart';

/// Mirrors [ServiceCenterSheet] for petrol pumps. List items render name,
/// address and a straight-line distance chip; tap or the Navigate button
/// hands off to Google Maps. Pumps are also pushed back to the parent so
/// they continue to appear as orange markers on the live map (driver may
/// still want the visual overlay).
class FuelPumpSheet extends StatefulWidget {
  const FuelPumpSheet({
    super.key,
    required this.driverLocation,
    this.routePolyline,
    this.onResultsReady,
  });

  final LatLng driverLocation;
  final String? routePolyline;
  final ValueChanged<List<Map<String, dynamic>>>? onResultsReady;

  @override
  State<FuelPumpSheet> createState() => _FuelPumpSheetState();
}

class _FuelPumpSheetState extends State<FuelPumpSheet> {
  final FindFuelService _svc = FindFuelService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pumps = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final pumps = await _svc.findNearbyIndianOil(
        widget.driverLocation,
        routePolyline: widget.routePolyline,
      );
      // Decorate with straight-line distance for the chip.
      for (final p in pumps) {
        final pLat = (p['lat'] as num).toDouble();
        final pLng = (p['lng'] as num).toDouble();
        p['distance_km'] = _haversineKm(
          widget.driverLocation.latitude, widget.driverLocation.longitude,
          pLat, pLng,
        );
      }
      // If no route filter applied, sort by straight-line distance.
      if (widget.routePolyline == null || widget.routePolyline!.isEmpty) {
        pumps.sort((a, b) => (a['distance_km'] as double).compareTo(b['distance_km'] as double));
      }
      if (!mounted) return;
      widget.onResultsReady?.call(pumps);
      setState(() {
        _pumps = pumps;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _navigate(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context, listen: false);
    final title = t.t('fuel_pumps_title') ?? 'Nearby petrol pumps';
    final searchLabel = t.t('searching_pumps') ?? 'Searching nearby pumps…';
    final emptyMsg = t.t('no_pumps_found') ?? 'No pumps found nearby';
    final navigateLabel = t.t('navigate') ?? 'Navigate';

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, controller) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.local_gas_station, color: Colors.orange, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 17, fontWeight: FontWeight.w700,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(child: _body(controller, searchLabel, emptyMsg, navigateLabel)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _body(ScrollController controller, String searchLabel, String emptyMsg, String navigateLabel) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(height: 12),
            Text(searchLabel,
                style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color)),
          ],
        ),
      );
    }
    if (_error != null || _pumps.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error ?? emptyMsg,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: Theme.of(context).textTheme.bodyMedium?.color)),
        ),
      );
    }
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _pumps.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final p = _pumps[i];
        final distKm = (p['distance_km'] as num?)?.toDouble() ?? 0.0;
        final distLabel = distKm < 10 ? '${distKm.toStringAsFixed(1)} km' : '${distKm.toStringAsFixed(0)} km';
        return Material(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _navigate((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.local_gas_station, color: Colors.orange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p['name'] ?? '',
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(p['address'] ?? '',
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 12,
                                color: Theme.of(context).textTheme.bodyMedium?.color)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(distLabel,
                              style: GoogleFonts.inter(
                                  fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange.shade800)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.navigation_rounded, color: Colors.orange),
                    tooltip: navigateLabel,
                    onPressed: () => _navigate((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
