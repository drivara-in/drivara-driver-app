import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'dart:io';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

class ApiConfig {
  // Compile-time fallback — used when dotenv didn't initialise (e.g. asset
  // bundle was stale after a new native plugin was added without a full
  // rebuild). The launcher (run.sh --android-{dev,prod}) injects the
  // matching URL via --dart-define=API_BASE_URL so the fallback honors
  // whichever environment the user actually launched. Hard default is dev,
  // so an unflagged plain `flutter run` still hits a working API.
  static const String _compileFallbackBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dev.drivara.in/api',
  );

  // Read API base URL from .env file, with bulletproof fallback. flutter_dotenv
  // throws NotInitializedError on env access if `load()` failed/was skipped —
  // wrap the read so a missing-config crashes the network call rather than
  // dotenv-throwing two layers up.
  static String get baseUrl {
    String? envUrl;
    try {
      envUrl = dotenv.env['API_BASE_URL'];
    } catch (e) {
      debugPrint('[ApiConfig] dotenv not initialised — using compile fallback ($e)');
      return _compileFallbackBaseUrl;
    }
    if (envUrl != null && envUrl.isNotEmpty) {
      if (envUrl.endsWith('/api')) {
        return envUrl;
      }
      return '$envUrl/api';
    }
    return _compileFallbackBaseUrl;
  }

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      // Bumped from 10s → 30s after we observed occasional 17–79s TLS
      // handshake stalls from drivers' phones to the self-hosted origin.
      // 30s lets a single packet-loss retry succeed instead of timing out
      // and surfacing as a frozen splash / spinner on the driver app.
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ));

    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => debugPrint(obj.toString()),
    ));

    // Configure SSL Bypass for Dev
    if (baseUrl.contains('dev.drivara.in') || baseUrl.contains('localhost')) {
      // ignore: deprecated_member_use
      (dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = (client) {
        client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        return client;
      };
    }

    return dio;
  }

  static final Dio _dio = _createDio();
  static Dio get dio => _dio;
  static const _storage = FlutterSecureStorage();
  static FlutterSecureStorage get storage => _storage;

  static Future<void> setAuthToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
    _dio.options.headers['Authorization'] = 'Bearer $token';
    // Restore orgId if available
    final orgId = await _storage.read(key: 'org_id');
    if (orgId != null) {
        _dio.options.headers['x-org-id'] = orgId;
    }
  }

  static Future<void> setOrgId(String orgId) async {
    await _storage.write(key: 'org_id', value: orgId);
    _dio.options.headers['x-org-id'] = orgId;
  }

  static Future<String?> getAuthToken() async {
    final token = await _storage.read(key: 'auth_token');
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';

      // 1. Try storage
      String? orgId = await _storage.read(key: 'org_id');
      
      // 2. Fallback: Extract from Token
      if (orgId == null) {
         try {
           if (!JwtDecoder.isExpired(token)) {
             final decoded = JwtDecoder.decode(token);
             // Check both camelCase and snake_case
             orgId = decoded['orgId'] ?? decoded['org_id'];
             
             if (orgId != null) {
                // Persist for future
                await _storage.write(key: 'org_id', value: orgId);
             }
           }
         } catch (e) {
           print('Error decoding JWT: $e');
         }
      }

      if (orgId != null) {
        _dio.options.headers['x-org-id'] = orgId;
      }
    }
    return token;
  }

  static Future<void> logout() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'org_id');
    _dio.options.headers.remove('Authorization');
    _dio.options.headers.remove('x-org-id');
  }

  static Future<String?> getDriverId() async {
    final token = await getAuthToken();
    if (token != null && !JwtDecoder.isExpired(token)) {
      final decodedToken = JwtDecoder.decode(token);
      return decodedToken['sub']; // 'sub' usually holds the user ID
    }
    return null;
  }

  static Future<bool> deleteExpense(String expenseId) async {
    try {
      await getAuthToken(); // Ensure token header is set
      final response = await _dio.delete('/driver/expenses/$expenseId');
      return response.statusCode == 200;
    } catch (e) {
      print("Delete expense error: $e");
      return false;
    }
  }

  // File Upload Helper
  static Future<String?> uploadFile(String filePath, {String? customKey}) async {
    try {
      String? token = await getAuthToken();
      if (token == null) {
         print("Upload failed: No auth token found");
         return null;
      }
      File file = File(filePath);
      if (!file.existsSync()) return null;

      String key = customKey ?? filePath.split('/').last;
      String encodedKey = Uri.encodeComponent(key);
      // If customKey contains slashes, we need to ensure they are not double encoded if we want to preserve directory structure?
      // Actually, the server route is /api/uploads/put/:key(*)
      // Dio/Uri encoding will encode slashes as %2F.
      // If the server uses :key(*), it expects raw slashes to separate path segments?
      // Express path params with (*) capture the rest of the path including slashes.
      // So /api/uploads/put/orgs/1/file.jpg -> key = "orgs/1/file.jpg".
      // But if we encode, it becomes /api/uploads/put/orgs%2F1%2Ffile.jpg -> key might be "orgs%2F1%2Ffile.jpg".
      // We should probably NOT encode the slashes in the key if we want directories.
      // Or we encode segments.
      // Let's assume the user passes a fully formed key "dirs/file.ext".
      // We should encode it but maybe preserve slashes?
      // Actually, standard URL encoding encodes slashes.
      // However, if the client sends encoded slashes, the server (Express) might or might not decode them before matching.
      // Let's check how the server is implemented: app.put("/api/uploads/put/:key(*)")
      // If I send /uploads/put/foo/bar, key="foo/bar".
      // If I send /uploads/put/foo%2Fbar, key="foo/bar" (usually decoded by Express).
      // So using encodedKey is safer.
      
      String uploadUrl = '/uploads/put/$encodedKey';

      // Read file as bytes
      List<int> fileBytes = await file.readAsBytes();
      
      // Perform PUT request with raw bytes
      final response = await _dio.put(
        uploadUrl, 
        data: fileBytes, // Pass bytes directly
        options: Options(
          headers: {
            Headers.contentLengthHeader: fileBytes.length,
            Headers.contentTypeHeader: 'application/octet-stream', // Force raw
          }
        )
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Response format: { ok: true, objectKey: "...", uploadId: "..." }
        String? uploadId = response.data['uploadId']?.toString();
        if (uploadId == null) {
          print("Upload successful but ID is null. Server DB Error: ${response.data['dbError']}");
        } else {
          print("Upload successful: $uploadId");
        }
        return uploadId;
      }
      return null;
    } catch (e) {
      print("File upload error: $e");
      rethrow;
    }
  }
}
