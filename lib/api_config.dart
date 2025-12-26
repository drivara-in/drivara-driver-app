import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiConfig {
  // Use 10.0.2.2 for Android Emulator, or your machine's IP for physical device
  // Since user is testing on physical device, we likely need the machine IP.
  // For now, I'll use a placeholder or the likely local IP if known, but 
  // often it's best to ask or use a known dev server.
  // Given previous logs, user might be on same network.
  // I'll default to a generic IP placeholder that the user might need to change,
  // or use the machine's likely IP if I can infer it.
  // The backend says "Server listening on http://localhost:8080".
  // Android device needs the Mac's IP.
  static const String baseUrl = 'http://192.168.1.4:8080/api'; 

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
