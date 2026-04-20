import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dio/dio.dart';
import '../api_config.dart';
import 'notification_service.dart';

/// Handles Firebase Cloud Messaging lifecycle for the driver app:
///   - initializes Firebase Admin SDK against project `drivara-cc236`
///   - fetches the FCM token
///   - registers it with the backend on login (→ notification_service)
///   - unregisters it on logout
///   - surfaces foreground pushes as local notifications via NotificationService
///
/// The channel IDs here must match what the server sets (`drivara_default`) —
/// see server src/fcm.ts channelId in drivara-notification-service.
class MessagingService {
  static final MessagingService _instance = MessagingService._internal();
  factory MessagingService() => _instance;
  MessagingService._internal();

  String? _currentToken;
  StreamSubscription<String>? _refreshSub;
  bool _initialized = false;

  String? get currentToken => _currentToken;

  /// Initialise Firebase + FCM listeners. Idempotent; safe to call multiple
  /// times (e.g., once at app start and once after login).
  Future<void> init() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
      _initialized = true;
    } catch (e) {
      debugPrint("[messaging] Firebase init failed: $e");
      return;
    }

    // Ask for permission (iOS is strict; Android 13+ needs POST_NOTIFICATIONS)
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint("[messaging] permission=${settings.authorizationStatus}");

    // Foreground message → surface as a local notification via the existing
    // NotificationService. FCM on Android doesn't display notifications
    // automatically when the app is in the foreground.
    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      final notif = msg.notification;
      if (notif == null) return;
      NotificationService().showNotification(
        id: DateTime.now().millisecondsSinceEpoch % 2147483647,
        title: notif.title ?? "Drivara",
        body: notif.body ?? "",
        payload: msg.data['deep_link'] as String?,
      );
    });

    // Token-refresh handler — re-register when FCM rotates the token.
    _refreshSub?.cancel();
    _refreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      debugPrint("[messaging] token refreshed");
      _currentToken = newToken;
      _registerWithBackend(newToken);
    });
  }

  /// Call after a successful driver login. Fetches the FCM token and POSTs
  /// it to the main server (which proxies to the notification service).
  /// No-ops silently if Firebase/FCM isn't available.
  Future<void> registerAfterLogin() async {
    if (!_initialized) await init();
    if (!_initialized) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        debugPrint("[messaging] no FCM token returned");
        return;
      }
      _currentToken = token;
      await _registerWithBackend(token);
    } catch (e) {
      debugPrint("[messaging] registerAfterLogin failed: $e");
    }
  }

  /// Call before logout. Disables this device's token on the backend so the
  /// driver doesn't keep receiving push after signing out.
  Future<void> unregisterOnLogout() async {
    final token = _currentToken;
    if (token == null) return;
    try {
      await ApiConfig.dio.delete(
        '/driver/notifications/tokens',
        data: {'fcmToken': token},
      );
      debugPrint("[messaging] token unregistered");
    } catch (e) {
      debugPrint("[messaging] unregister failed: $e");
    } finally {
      _currentToken = null;
    }
  }

  Future<void> _registerWithBackend(String token) async {
    final platform = Platform.isAndroid ? "android" : Platform.isIOS ? "ios" : "web";
    try {
      await ApiConfig.dio.post(
        '/driver/notifications/tokens',
        data: {
          'fcmToken': token,
          'platform': platform,
        },
      );
      debugPrint("[messaging] token registered with backend ($platform)");
    } on DioException catch (e) {
      debugPrint("[messaging] backend register failed: ${e.response?.statusCode} ${e.message}");
    } catch (e) {
      debugPrint("[messaging] backend register failed: $e");
    }
  }
}
