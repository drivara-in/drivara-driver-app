
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_page.dart';
import 'permissions_page.dart';
import 'home_page.dart';
import 'api_config.dart';
import 'providers/localization_provider.dart';
import 'active_job_page.dart';
import 'no_job_page.dart';
import 'theme/app_theme.dart';
import 'providers/theme_provider.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/messaging_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android 15 (API 35) enforces edge-to-edge by default and flags the
  // legacy decor-fits-system-windows flow as deprecated. Opt the app in
  // explicitly so the Play Console "edge-to-edge may not display"
  // warning clears and Flutter's framework uses the modern WindowInsets
  // path instead of View.SYSTEM_UI_FLAG_*. Status + nav bars also go
  // transparent so the existing screens render to the edge cleanly.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));

  // Strict environment loading (Default: .env)
  const envFile = String.fromEnvironment('ENV_FILE', defaultValue: '.env');

  bool envLoaded = false;
  try {
    await dotenv.load(fileName: envFile);
    envLoaded = true;
    debugPrint('[ENV] Loaded $envFile (API_BASE_URL=${dotenv.env['API_BASE_URL']})');
  } catch (e) {
    debugPrint('[ENV] FAILED to load $envFile: $e — ApiConfig will use compile fallback');
  }
  // If we asked for a dev/prod env file but got nothing, retry plain `.env`
  // as a last resort. This handles the "user added a new native plugin and
  // hot-restarted; asset bundle stale" case more gracefully.
  if (!envLoaded && envFile != '.env') {
    try {
      await dotenv.load(fileName: '.env');
      debugPrint('[ENV] Fell back to .env (API_BASE_URL=${dotenv.env['API_BASE_URL']})');
    } catch (_) { /* both failed; fallback in ApiConfig handles it */ }
  }

  await initializeDateFormatting();

  final token = await ApiConfig.getAuthToken();

  // NotificationService is local-only (flutter_local_notifications plugin)
  // — safe to init at startup. It does NOT show any permission dialogs;
  // FCM is what triggers POST_NOTIFICATIONS prompts.
  unawaited(NotificationService().init());

  // CRITICAL: do NOT call MessagingService().init() here. It awaits
  // FirebaseMessaging.requestPermission(), which on Android 13+ shows
  // the POST_NOTIFICATIONS system dialog. On a fresh Play Store install
  // that dialog pauses the Activity before the Flutter engine has handed
  // off the native splash drawable, and the app gets stuck on the splash
  // forever after the user taps Allow. Firebase init is now triggered
  // lazily by MessagingService().registerAfterLogin(), which runs from
  // the OTP success path (OtpPage._verifyOtp) — i.e., AFTER the user has
  // typed their phone, received an OTP, entered it, and seen the dashboard
  // start to load. At that point the splash handoff is long done and a
  // permission prompt is harmless. This also matches Android UX guidance:
  // don't prompt for runtime permissions before the user has context.
  if (token != null) {
    unawaited(MessagingService().registerAfterLogin());
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocalizationProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: DrivaraApp(initialRoute: token != null ? '/home' : '/login'),
    ),
  );
}

class DrivaraApp extends StatefulWidget {
  final String initialRoute;
  const DrivaraApp({super.key, required this.initialRoute});

  @override
  State<DrivaraApp> createState() => _DrivaraAppState();
}

class _DrivaraAppState extends State<DrivaraApp> {
  static final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();
  StreamSubscription<dynamic>? _notificationTapSub;

  @override
  void initState() {
    super.initState();
    // Listen for notification taps (FCM → user tapped). When the user taps a
    // fuel-proximity or separation alert while the app is backgrounded or
    // terminated, route them to the active job page.
    _notificationTapSub = MessagingService().onNotificationTapped.listen((_) {
      _navigatorKey.currentState?.pushNamedAndRemoveUntil('/home', (route) => false);
    });
  }

  @override
  void dispose() {
    _notificationTapSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch ThemeProvider to rebuild when theme changes manually
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Drivara Driver',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      initialRoute: widget.initialRoute,
      routes: {
        '/login': (context) => const LoginPage(),
        '/permissions': (context) => const PermissionsPage(),
        '/home': (context) => const HomeRedirector(),
      },
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''), // English
      ],
    );
  }
}

class HomeRedirector extends StatefulWidget {
  const HomeRedirector({super.key});

  @override
  State<HomeRedirector> createState() => _HomeRedirectorState();
}

class _HomeRedirectorState extends State<HomeRedirector> {
  @override
  void initState() {
    super.initState();
    _checkJob();
  }

  Future<void> _checkJob() async {
    try {
      // Re-verify token presence/header setting just to be safe
      final token = await ApiConfig.getAuthToken();
      if (token == null) {
          if (mounted) Navigator.of(context).pushReplacementNamed('/login');
          return;
      }
      
      final response = await ApiConfig.dio.get('/driver/me/active-job');
      final activeJob = response.data['activeJob'];
      if (!mounted) return;
      if (activeJob != null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ActiveJobPage(job: activeJob)));
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const NoJobPage()));
      }
    } catch (e) {
      debugPrint("Check Job Failed: $e");
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const NoJobPage()));
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
