import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/localization_provider.dart';
import '../services/find_service_center_service.dart';

/// Bottom sheet that lists the nearest authorised service centers for the
/// active vehicle. Tap → Google Maps for turn-by-turn.
class ServiceCenterSheet extends StatefulWidget {
  const ServiceCenterSheet({
    super.key,
    required this.driverLocation,
    required this.vehicleMake,
  });

  final LatLng driverLocation;
  final String? vehicleMake;

  @override
  State<ServiceCenterSheet> createState() => _ServiceCenterSheetState();
}

class _ServiceCenterSheetState extends State<ServiceCenterSheet> {
  final FindServiceCenterService _svc = FindServiceCenterService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _centers = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final results = await _svc.findNearby(widget.driverLocation, make: widget.vehicleMake);
      if (!mounted) return;
      setState(() {
        _centers = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context, listen: false);
    final title = t.t('service_centers_title') ?? 'Nearby service centers';
    final emptyMsg = t.t('service_centers_empty') ?? 'No service centers found nearby';
    final searchLabel = t.t('service_centers_searching') ?? 'Searching nearby service centers…';
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
                          color: Colors.indigo.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.build_circle, color: Colors.indigo, size: 22),
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
                if (widget.vehicleMake != null && widget.vehicleMake!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        avatar: const Icon(Icons.local_shipping, size: 16),
                        label: Text(widget.vehicleMake!.toUpperCase()),
                        backgroundColor: Colors.indigo.withOpacity(0.08),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(child: _body(controller, emptyMsg, searchLabel, navigateLabel)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _body(ScrollController controller, String emptyMsg, String searchLabel, String navigateLabel) {
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
    if (_error != null || _centers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error ?? emptyMsg,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14, color: Theme.of(context).textTheme.bodyMedium?.color),
          ),
        ),
      );
    }
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _centers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final c = _centers[i];
        final distKm = c['distance_km'] as double;
        final distLabel = distKm < 10 ? '${distKm.toStringAsFixed(1)} km' : '${distKm.toStringAsFixed(0)} km';
        return Material(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _svc.navigateTo(c['latitude'], c['longitude'], label: c['name']),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.car_repair, color: Colors.indigo, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c['name'] ?? '',
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(c['address'] ?? '',
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 12,
                                color: Theme.of(context).textTheme.bodyMedium?.color)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(distLabel,
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.indigo)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.navigation_rounded, color: Colors.indigo),
                    tooltip: navigateLabel,
                    onPressed: () => _svc.navigateTo(c['latitude'], c['longitude'], label: c['name']),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
