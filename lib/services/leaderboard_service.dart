
import '../api_config.dart';
import 'package:dio/dio.dart';

enum LeaderboardPeriod { week, month, all }

class LeaderboardEntry {
  final String id;
  final String name;
  final String? avatarUploadId;
  final double distanceKm;
  final double mileage;
  final int rank;

  LeaderboardEntry({
    required this.id,
    required this.name,
    this.avatarUploadId,
    required this.distanceKm,
    required this.mileage,
    required this.rank,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Driver',
      avatarUploadId: json['avatar_upload_id'],
      distanceKm: (json['distance_km'] ?? 0).toDouble(),
      mileage: (json['mileage'] ?? 0).toDouble(),
      rank: json['rank'] ?? 0,
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
