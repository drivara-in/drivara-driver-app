import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api_config.dart';

class FindFuelService {
  // Use a dedicated Dio instance for Routing Service (Port 5055)
  late final Dio _dio;

  FindFuelService() {
    _dio = Dio();
    // Inherit auth token from main ApiConfig
    _dio.interceptors.add(InterceptorsWrapper(
       onRequest: (options, handler) async {
          final token = await ApiConfig.getAuthToken();
          if (token != null) {
             options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
       }
    ));

    // Construct Routing Service URL from Main API URL
    // Main: http://IP:8080/api -> Routing: http://IP:5055/api
    final mainUrl = ApiConfig.baseUrl;
    final routingUrl = mainUrl.replaceAll('8080', '5055');
    _dio.options.baseUrl = routingUrl;
    
    print("FindFuelService: Initialized with Base URL: $routingUrl");
  }

  // 50km search radius to find pumps even if they are far ahead
  static const int SEARCH_RADIUS_METERS = 50000;
  // Max deviation from route (2km) to consider "on route". Highways exits can be wide.
  static const double MAX_DEVIATION_METERS = 2000.0;

  Future<List<Map<String, dynamic>>> findNearbyIndianOil(LatLng location, {String? routePolyline}) async {
    // Backend Endpoint: /api/places/search
    // The backend should proxy this to Google Places API (Text Search)
    const url = '/places/search'; 
    
    print("FindFuelService: Requesting Backend: $url");

    try {
      final response = await _dio.post(
        url,
        data: {
          "textQuery": "Indian Oil petrol pump",
          "locationBias": {
            "circle": {
              "center": {
                "latitude": location.latitude,
                "longitude": location.longitude
              },
              "radius": SEARCH_RADIUS_METERS.toDouble()
            }
          },
          "maxResultCount": 20
        },
      );

      print("FindFuelService: Response Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['places'] == null) {
           print("FindFuelService: No 'places' field in response.");
           return [];
        }

        final results = data['places'] as List;
        print("FindFuelService: Raw Results Count: ${results.length}");
        
        List<Map<String, dynamic>> places = results.map((place) => {
          'name': place['displayName']?['text'] ?? 'Unknown Station',
          'address': place['formattedAddress'] ?? '',
          'lat': place['location']['latitude'],
          'lng': place['location']['longitude'],
          'rating': place['rating'] ?? 0.0,
          'place_id': place['id'],
          'distance_along_route': double.infinity, 
          'deviation': 0.0,
        }).toList();

        // If route is provided, filter by proximity to route AND sort by "distance along route"
        if (routePolyline != null && routePolyline.isNotEmpty) {
           print("FindFuelService: Filtering by remaining route...");
           try {
             final path = _decodePolyline(routePolyline);
             
             if (path.isNotEmpty) {
                // 1. Slice path to start from current location (approx)
                int closestIndex = 0;
                double minDistanceToCar = double.infinity;
                
                for(int i=0; i<path.length; i++) {
                   final d = _calculateDistance(location.latitude, location.longitude, path[i].latitude, path[i].longitude);
                   if (d < minDistanceToCar) {
                      minDistanceToCar = d;
                      closestIndex = i;
                   }
                }
                
                // Truncate path to only points AFTER closest index (Remaining Route)
                final remainingPath = path.sublist(closestIndex);
                
                if (remainingPath.isNotEmpty) {
                    final filtered = <Map<String, dynamic>>[];
                    
                    for (var p in places) {
                        final pLoc = LatLng(p['lat'], p['lng']);
                        double minDev = double.infinity;
                        int bestPointIdx = -1;
                        
                        for (int i=0; i<remainingPath.length - 1; i++) {
                             final segDev = _distanceToSegment(pLoc, remainingPath[i], remainingPath[i+1]);
                             if (segDev < minDev) {
                                minDev = segDev;
                                bestPointIdx = i;
                             }
                        }
                        
                        if (minDev <= MAX_DEVIATION_METERS) {
                             p['distance_along_route'] = bestPointIdx.toDouble();
                             p['deviation'] = minDev;
                             filtered.add(p);
                        }
                    }
                    
                    if (filtered.isNotEmpty) {
                        filtered.sort((a, b) {
                            final idxA = a['distance_along_route'] as double;
                            final idxB = b['distance_along_route'] as double;
                            if (idxA == idxB) {
                               return (a['deviation'] as double).compareTo(b['deviation'] as double);
                            }
                            return idxA.compareTo(idxB);
                        });
                        places = filtered;
                    }
                }
             }
           } catch (e) {
             print("FindFuelService: Route decode error: $e");
           }
        } 

        // Final sort if not filtered
        if (places.isNotEmpty && places.first['distance_along_route'] == double.infinity) {
             places.sort((a, b) {
                final dA = _calculateDistance(location.latitude, location.longitude, a['lat'], a['lng']);
                final dB = _calculateDistance(location.latitude, location.longitude, b['lat'], b['lng']);
                return dA.compareTo(dB);
            });
        }

        // De-duplicate by ID and Location
        final uniquePlaces = <Map<String, dynamic>>[];
        final seenIds = <String>{};
        
        for (var p in places) {
           if (seenIds.contains(p['place_id'])) continue;
           
           bool isSpatialDuplicate = false;
           for (var existing in uniquePlaces) {
               final dist = _calculateDistance(p['lat'], p['lng'], existing['lat'], existing['lng']);
               if (dist < 0.05) { isSpatialDuplicate = true; break; }
           }
           
           if (!isSpatialDuplicate) {
               uniquePlaces.add(p);
               seenIds.add(p['place_id']);
           }
        }
        
        return uniquePlaces.take(5).toList();
      }
    } catch (e) {
      print("Error finding fuel: $e");
    }
    return [];
  }

  Future<void> launchNavigation(double lat, double lng) async {
    final uri = Uri.parse('google.navigation:q=$lat,$lng');
    final webUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  Future<List<LatLng>> getDirections(LatLng origin, LatLng destination) async {
    // Backend Endpoint: /api/routes/compute
    const url = '/routes/compute';
    
    // Explicit syntax for Backend proxy to understand which provider/API to use if needed
    // Assuming backend takes generic Routes API payload
    
    print("FindFuelService: Fetching directions via Backend...");

    try {
      final response = await _dio.post(
        url,
        data: {
          "origin": {
            "location": {
              "latLng": {
                "latitude": origin.latitude,
                "longitude": origin.longitude
              }
            }
          },
          "destination": {
            "location": {
              "latLng": {
                "latitude": destination.latitude,
                "longitude": destination.longitude
              }
            }
          },
          "travelMode": "DRIVE",
          "routingPreference": "TRAFFIC_AWARE",
          "routeModifiers": {
            "avoidTolls": false,
            "avoidHighways": false,
            "avoidFerries": false
          },
          "units": "METRIC"
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
           final encodedPolyline = data['routes'][0]['polyline']['encodedPolyline'];
           return _decodePolyline(encodedPolyline);
        }
      } else {
        print("FindFuelService: backend/http error: ${response.statusCode}");
      }
    } catch (e) {
       print("Error fetching directions: $e");
    }
    return [];
  }

  // --- Geometry Helpers ---

  // Manual Polyline Decoding to avoid package version issues
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble()));
    }
    return points;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = math.cos;
    var a = 0.5 - c((lat2 - lat1) * p)/2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p))/2;
    return 12742 * math.asin(math.sqrt(a));
  }

  double _distanceToSegment(LatLng p, LatLng a, LatLng b) {
    final x = p.latitude;
    final y = p.longitude;
    final x1 = a.latitude;
    final y1 = a.longitude;
    final x2 = b.latitude;
    final y2 = b.longitude;

    final A = x - x1;
    final B = y - y1;
    final C = x2 - x1;
    final D = y2 - y1;

    final dot = A * C + B * D;
    final lenSq = C * C + D * D;
    
    double param = -1;
    if (lenSq != 0) param = dot / lenSq;

    double xx, yy;

    if (param < 0) {
      xx = x1;
      yy = y1;
    } else if (param > 1) {
      xx = x2;
      yy = y2;
    } else {
      xx = x1 + param * C;
      yy = y1 + param * D;
    }

    // Return distance in meters
    return _calculateDistance(x, y, xx, yy) * 1000; 
  }

}
