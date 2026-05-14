
import '../api_config.dart';
import 'package:dio/dio.dart';

enum LeaderboardPeriod { week, month, all }

class LeaderboardViolations {
  final int speed;    // speed-only events (over 80 km/h, RPM normal)
  final int rpm;      // RPM-only events (over 2400 rpm, speed normal)
  final int impact;   // both speed AND RPM at the same instant — hardest driving
  final int harsh;    // brake / accel / sharp turn / cornering from phone sensors
  const LeaderboardViolations({
    required this.speed,
    required this.rpm,
    required this.impact,
    required this.harsh,
  });
  int get total => speed + rpm + impact + harsh;
  factory LeaderboardViolations.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const LeaderboardViolations(speed: 0, rpm: 0, impact: 0, harsh: 0);
    return LeaderboardViolations(
      speed: (j['speed'] ?? 0) as int,
      rpm: (j['rpm'] ?? 0) as int,
      impact: (j['impact'] ?? 0) as int,
      harsh: (j['harsh'] ?? 0) as int,
    );
  }
}

class LeaderboardEntry {
  final String id;
  final String name;
  final String? avatarUploadId;
  final String? avatarUrl;
  final double distanceKm;
  final double mileage;            // overall km/L
  final double? loadedMileage;     // km/L when truck was carrying cargo
  final double? emptyMileage;      // km/L when running empty
  final LeaderboardViolations violations;
  final int score;                 // 0-100 composite (higher = safer + more efficient)
  final int rank;

  LeaderboardEntry({
    required this.id,
    required this.name,
    this.avatarUploadId,
    this.avatarUrl,
    required this.distanceKm,
    required this.mileage,
    required this.loadedMileage,
    required this.emptyMileage,
    required this.violations,
    required this.score,
    required this.rank,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Driver',
      avatarUploadId: json['avatar_upload_id'],
      avatarUrl: json['avatar_url'],
      distanceKm: (json['distance_km'] ?? 0).toDouble(),
      mileage: (json['mileage'] ?? 0).toDouble(),
      loadedMileage: json['loaded_mileage'] != null ? (json['loaded_mileage'] as num).toDouble() : null,
      emptyMileage: json['empty_mileage'] != null ? (json['empty_mileage'] as num).toDouble() : null,
      violations: LeaderboardViolations.fromJson(json['violations'] as Map<String, dynamic>?),
      score: (json['score'] ?? 0) as int,
      rank: (json['rank'] ?? 0) as int,
    );
  }
}

class LeaderboardService {
  Future<List<LeaderboardEntry>> getLeaderboard({LeaderboardPeriod period = LeaderboardPeriod.week}) async {
    try {
      String periodStr = 'week';
      if (period == LeaderboardPeriod.month) periodStr = 'month';
      if (period == LeaderboardPeriod.all) periodStr = 'all';

      print('Fetching Leaderboard: period=$periodStr');
      await ApiConfig.getAuthToken(); // Ensure headers are set
      print('Headers: ${ApiConfig.dio.options.headers}');
      
      final response = await ApiConfig.dio.get('/drivers/leaderboard', queryParameters: {'period': periodStr});
      print('Leaderboard Response: ${response.statusCode} - ${response.data}');

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        return data.map((e) => LeaderboardEntry.fromJson(e)).toList();
      } else {
        print('Leaderboard Failed: ${response.statusCode}');
        throw Exception('Failed to load leaderboard');
      }
    } catch (e) {
      if (e is DioException) {
         print('DioError: ${e.response?.statusCode} - ${e.response?.data}');
      }
      print('Leaderboard fetch error: $e');
      return [];
    }
  }
}
