import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    // iOS settings can be added here if needed
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
         // Handle notification tap
         debugPrint('Notification tapped: ${response.payload}');
      },
    );
    // Permission is NOT requested here. On Android 13+ that triggers the
    // POST_NOTIFICATIONS system dialog, which on a fresh Play Store install
    // pauses the Activity before the Flutter engine has handed off the
    // native splash drawable to the first frame — so the user taps Allow,
    // the dialog dismisses, and the app stays stuck on the splash forever.
    // requestPermission() below is now called from a screen post-OTP,
    // when the Flutter view is already painted and an OS prompt is safe.
  }

  /// Request POST_NOTIFICATIONS permission. Call only AFTER the first
  /// Flutter frame has painted (i.e., user is on Login or any post-OTP
  /// screen). Safe to call multiple times — the plugin no-ops if already
  /// granted or denied.
  Future<bool?> requestPermission() async {
    try {
      return await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[notification] requestPermission failed: $e');
      return null;
    }
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'driver_reminders', 
      'Driver Reminders',
      channelDescription: 'Reminders for driver actions',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidNotificationDetails);

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }
}
