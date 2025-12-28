import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  // Read API base URL from .env file, fallback to localhost for emulator
  static String get baseUrl {
    final envUrl = dotenv.env['API_BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      return '$envUrl/api';
    }
    // Fallback to localhost (works for emulator)
    return 'http://localhost:8080/api';
  } 

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  static final _storage = const FlutterSecureStorage();

  static Dio get dio => _dio;
  static FlutterSecureStorage get storage => _storage;

  static Future<void> setAuthToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  static Future<String?> getAuthToken() async {
    final token = await _storage.read(key: 'auth_token');
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
    return token;
  }

  static Future<void> logout() async {
    await _storage.delete(key: 'auth_token');
    _dio.options.headers.remove('Authorization');
  }
}
