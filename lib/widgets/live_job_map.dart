import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';
import 'dart:math' as math;
import '../utils/marker_generator.dart';
import '../utils/map_styles.dart';

class LiveJobMap extends StatefulWidget {
  final Map<String, dynamic> job;
  final Map<String, dynamic> vehicle;

  const LiveJobMap({
    super.key,
    required this.job,
    required this.vehicle,
  });

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
    if (widget.job != oldWidget.job || widget.vehicle != oldWidget.vehicle) {
      _parseJobData();
    }
    _loadMapStyle();
  }

  Future<void> _loadMapStyle() async {
    // Basic dark/light style logic
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    try {
       // Ideally load proper JSON styles. 
       // For 3D effect, clean styles without too many labels work best.
      if (isDark) {
         _mapStyle = MapStyles.dark;
      } else {
         _mapStyle = null; 
      }
      
      final controller = await _controller.future;
      controller.setMapStyle(_mapStyle);
      
    } catch (e) {
      debugPrint("Error loading map style: $e");
    }
  }

  void _parseJobData() {
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
        // Check both top-level and nested 'location' for heading
        heading = double.tryParse(widget.vehicle['heading']?.toString() ?? '') ?? 
                  double.tryParse(widget.vehicle['location']?['heading']?.toString() ?? '') ?? 
                  0.0;
        
        // Only add marker if custom icon is ready to avoid showing default pin
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
        
        _updateCamera(vehiclePos, heading);
      }
    }

    // 2. Parse Destination
    LatLng? destPos;
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

    // 3. Polyline (Disabled as per user request to remove "the line that connects")
    /*
    if (vehiclePos != null && destPos != null) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: [vehiclePos, destPos],
        color: Theme.of(context).primaryColor,
        width: 5,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.buttCap,
      ));
    }
    */

    setState(() {
      _markers = markers;
      _polylines = polylines;
    });
  }

  Future<void> _updateCamera(LatLng pos, double heading) async {
    // Only animate if position changed significantly or first load
    if (_lastVehiclePos == pos && _lastHeading == heading && _isCameraInitialized) return;
    
    _lastVehiclePos = pos;
    _lastHeading = heading;

    final controller = await _controller.future;
    
    // "Best in Class" 3D Animation
    // 1. High Zoom for detail
    // 2. High Tilt (60 deg) for horizon view
    // 3. Bearing aligned with vehicle heading (Navigation Mode)
    
    final cameraUpdate = CameraUpdate.newCameraPosition(CameraPosition(
      target: pos,
      zoom: 18.0,      // Zoomed IN
      tilt: 50.0,      // Tilted for 3D
      bearing: heading, // Dynamic Rotation
    ));

    controller.animateCamera(cameraUpdate);
    _isCameraInitialized = true;
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
      // UI Settings for Clean "Navigation" Look
      zoomControlsEnabled: false,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false, 
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      trafficEnabled: false, // Optional: Turn on if real-time traffic desired
    );
  }
}
