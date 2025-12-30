import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import '../providers/localization_provider.dart';
import '../utils/marker_generator.dart';
import '../utils/map_styles.dart';

class LiveJobMap extends StatefulWidget {
  final Map<String, dynamic> job;
  final Map<String, dynamic> vehicle;

  const LiveJobMap({
    super.key,
    required this.job,
    required this.vehicle,
    this.fuelStations,
    this.onFuelStationTap,
  });

  final List<Map<String, dynamic>>? fuelStations;
  final Function(Map<String, dynamic>)? onFuelStationTap;

  @override
  State<LiveJobMap> createState() => _LiveJobMapState();
}

class _LiveJobMapState extends State<LiveJobMap> {
  final Completer<GoogleMapController> _controller = Completer();
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  String? _mapStyle;
  BitmapDescriptor? _vehicleIcon;
  BitmapDescriptor? _destinationIcon;
  
  // Camera State
  LatLng? _lastVehiclePos;
  double _lastHeading = 0.0;
  bool _isCameraInitialized = false;

  // Navigation Override State
  LatLng? _overrideDestPos;
  String? _overrideDestName;
  List<LatLng>? _overrideRouteCurve;

  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(20.5937, 78.9629), // India center
    zoom: 5,
  );

  @override
  void initState() {
    super.initState();
    // Do not load assets here, wait for context for theme
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadMapStyle();
    _loadAssets(); // Regenerate marker based on new theme
    _parseJobData();
  }


  Future<void> _loadAssets() async {
    try {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        debugPrint("Loading assets... Dark Mode: $isDark");
        final icon = await MarkerGenerator.createCustom3DMarker(isDark: isDark);
        debugPrint("Asset loaded. Icon size (bytes): ${icon.toJson().toString().length}");
        if (mounted) {
            setState(() {
                _vehicleIcon = icon;
                _destinationIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
                _parseJobData(); // Re-parse to apply the new icon
            });
        }
    } catch (e) {
        debugPrint("Error loading assets: $e");
        if (mounted) {
             setState(() {
                _vehicleIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
             });
        }
    }
  }

  @override
  void didUpdateWidget(LiveJobMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    bool fuelChanged = widget.fuelStations != oldWidget.fuelStations;
    
    if (widget.job != oldWidget.job || 
        widget.vehicle != oldWidget.vehicle || 
        fuelChanged) {
      _parseJobData(refitBounds: fuelChanged);
    }
    _loadMapStyle();
  }

  Future<void> _loadMapStyle() async {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    try {
      if (isDark) {
         _mapStyle = MapStyles.dark;
      } else {
         _mapStyle = null; 
      }
      
      // If controller is available, set style. 
      // Note: _controller.future might not be complete yet during init.
      // But _onMapCreated handles initial style. This is for theme changes.
      if (_controller.isCompleted) {
        final controller = await _controller.future;
        controller.setMapStyle(_mapStyle);
      }
    } catch (e) {
      debugPrint("Error loading map style: $e");
    }
  }

  void _parseJobData({bool refitBounds = false}) {
    final markers = <Marker>{};
    final polylines = <Polyline>{};

    // 1. Parse Vehicle Location & Heading
    LatLng? vehiclePos;
    double heading = 0.0;
    
    if (widget.vehicle['location'] != null) {
      final lat = double.tryParse(widget.vehicle['location']['lat'].toString());
      final lng = double.tryParse(widget.vehicle['location']['lng'].toString());
      if (lat != null && lng != null) {
        vehiclePos = LatLng(lat, lng);
        heading = double.tryParse(widget.vehicle['heading']?.toString() ?? '') ?? 
                  double.tryParse(widget.vehicle['location']?['heading']?.toString() ?? '') ?? 
                  0.0;
        
        if (_vehicleIcon != null) {
          markers.add(Marker(
            markerId: const MarkerId('vehicle'),
            position: vehiclePos,
            rotation: heading, 
            icon: _vehicleIcon!,
            anchor: const Offset(0.5, 0.5),
            flat: true,
            infoWindow: const InfoWindow(title: "My Truck"),
            zIndex: 2,
          ));
        }
        
        // If we Just cleared fuel stations (refit=true but no stations), force snap back
        bool stationsCleared = refitBounds && (widget.fuelStations == null || widget.fuelStations!.isEmpty);
        updateVehicleLocation(vehiclePos, heading, force: stationsCleared);
      }
    }

    // ... (Destination Parsing stays same) ...
    // 2. Parse Destination (Check Override first)
    LatLng? destPos;
    
    if (_overrideDestPos != null) {
        // Use Override
        destPos = _overrideDestPos;
        markers.add(Marker(
          markerId: const MarkerId('destination'),
          position: destPos!,
          icon: _destinationIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed), 
          infoWindow: InfoWindow(title: _overrideDestName ?? "Destination", snippet: "Navigating here"),
        ));
    } else {
        // Use Job Destination
        final dLat = double.tryParse(widget.job['destination_latitude'].toString());
        final dLng = double.tryParse(widget.job['destination_longitude'].toString());
        if (dLat != null && dLng != null) {
          destPos = LatLng(dLat, dLng);
          markers.add(Marker(
            markerId: const MarkerId('destination'),
            position: destPos,
            icon: _destinationIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: widget.job['destination'] ?? "Drop Location"),
          ));
        }
    }

    // 3. Polyline
    if (vehiclePos != null && destPos != null) {
      if (_overrideRouteCurve != null && _overrideRouteCurve!.isNotEmpty) {
           polylines.add(Polyline(
            polylineId: const PolylineId('route'),
            points: _overrideRouteCurve!,
            color: Theme.of(context).primaryColor,
            width: 5,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.buttCap,
         ));
      } 
    }

    // 4. Fuel Stations
    List<LatLng> fuelPositions = [];
    if (widget.fuelStations != null) {
      for (var currStation in widget.fuelStations!) {
        final lat = double.tryParse(currStation['lat'].toString());
        final lng = double.tryParse(currStation['lng'].toString());
        
        if (lat != null && lng != null) {
           final pos = LatLng(lat, lng);
           fuelPositions.add(pos);
           
           markers.add(Marker(
             markerId: MarkerId('station_${currStation['place_id']}'),
             position: pos,
             icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow), 
             infoWindow: InfoWindow(
               title: currStation['name'],
               snippet: Provider.of<LocalizationProvider>(context, listen: false).t('tap_to_navigate'),
               onTap: () {
                 if (widget.onFuelStationTap != null) {
                   widget.onFuelStationTap!(currStation);
                 }
               }
             ),
             zIndex: 1, 
           ));
        }
      }
    }

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });
    
    // Auto-Fit Logic for Fuel Stations (ONLY if refit requested)
    if (fuelPositions.isNotEmpty && refitBounds) {
       if (vehiclePos != null) {
          fuelPositions.add(vehiclePos);
       }
       
       if (_overrideDestPos == null) {
          _fitPolylineBounds(fuelPositions);
       }
    }
  }

  // --- State ---
  bool _following = true; // Auto-follow by default

  Future<void> updateVehicleLocation(LatLng pos, double heading, {bool force = false}) async {
    // If not following (User panned or Overview mode), do not update camera automatically
    if (!_following && !force) {
       _lastVehiclePos = pos;
       _lastHeading = heading;
       return;
    }

    if (!force && _lastVehiclePos == pos && _lastHeading == heading && _isCameraInitialized) return;
    
    _lastVehiclePos = pos;
    _lastHeading = heading;

    final controller = await _controller.future;
    
    // Driving Mode / Follow Mode
    final cameraUpdate = CameraUpdate.newCameraPosition(CameraPosition(
      target: pos,
      zoom: 18.0,
      tilt: 50.0,
      bearing: heading,
    ));

    controller.animateCamera(cameraUpdate);
    _isCameraInitialized = true;
  }

  void updateDestination(LatLng point, String name, {List<LatLng>? routePoints}) {
    setState(() {
       _overrideDestPos = point;
       _overrideDestName = name;
       _following = true; // Auto-follow immediately
       
       if (routePoints != null && routePoints.isNotEmpty) {
           _overrideRouteCurve = routePoints;
       }
    });
    
    _parseJobData();

    // User requested "Recenter should be made" -> Snap to vehicle immediately
    if (_lastVehiclePos != null) {
        updateVehicleLocation(_lastVehiclePos!, _lastHeading, force: true);
    }
    
    // Optionally we could fit bounds if vehicle is huge distance away, but user asked for Recenter.
    // if (routePoints != null && routePoints.isNotEmpty) {
    //    _fitPolylineBounds(routePoints);
    // }
  }

  void resetNavigation() {
     setState(() {
        _overrideDestPos = null;
        _overrideDestName = null;
        _overrideRouteCurve = null;
        _following = true; // Resume following
     });
     
     _parseJobData();
     
     if (_lastVehiclePos != null) {
         updateVehicleLocation(_lastVehiclePos!, _lastHeading, force: true);
     }
  }

  void recenter() {
     setState(() => _following = true);
     if (_lastVehiclePos != null) {
         updateVehicleLocation(_lastVehiclePos!, _lastHeading, force: true);
     }
  }

  Future<void> _fitPolylineBounds(List<LatLng> points) async {
     final controller = await _controller.future;
     double minLat = points.first.latitude;
     double maxLat = points.first.latitude;
     double minLng = points.first.longitude;
     double maxLng = points.first.longitude;

     for (var p in points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
     }

     controller.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
           southwest: LatLng(minLat, minLng),
           northeast: LatLng(maxLat, maxLng)
        ), 
        50 // padding
     ));
  }

  Future<void> _fitBounds(LatLng p1, LatLng p2) async {
    final controller = await _controller.future;
    
    LatLngBounds bounds;
    if (p1.latitude > p2.latitude && p1.longitude > p2.longitude) {
      bounds = LatLngBounds(southwest: p2, northeast: p1);
    } else if (p1.longitude > p2.longitude) {
      bounds = LatLngBounds(
          southwest: LatLng(p1.latitude, p2.longitude),
          northeast: LatLng(p2.latitude, p1.longitude));
    } else if (p1.latitude > p2.latitude) {
      bounds = LatLngBounds(
          southwest: LatLng(p2.latitude, p1.longitude),
          northeast: LatLng(p1.latitude, p2.longitude));
    } else {
      bounds = LatLngBounds(southwest: p1, northeast: p2);
    }

    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      mapType: MapType.normal,
      initialCameraPosition: _kGooglePlex,
      markers: _markers,
      polylines: _polylines,
      onMapCreated: (GoogleMapController controller) {
        _controller.complete(controller);
        if (_mapStyle != null) {
          controller.setMapStyle(_mapStyle);
        }
      },
      onCameraMoveStarted: () {
          // If user touches map, stop auto-following
          if (_following) {
             setState(() => _following = false);
          }
      },
      // UI Settings for Clean "Navigation" Look
      zoomControlsEnabled: false,      // Clean UI
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false, 
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      trafficEnabled: false, 
    );
  }
}
