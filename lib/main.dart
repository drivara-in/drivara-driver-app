
import 'dart:async';
import 'package:flutter/material.dart';
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

  // CRITICAL: defer Firebase / FCM init until AFTER the first frame paints.
  // FirebaseMessaging.requestPermission() shows the Android 13+
  // POST_NOTIFICATIONS dialog, which pauses the Activity. If that happens
  // before runApp's first frame, the launcher splash drawable is never
  // swapped for the Flutter view — user taps Allow, the dialog dismisses,
  // and they're stuck looking at the static splash because Flutter never
  // got to paint frame 1. Scheduling on the post-frame callback guarantees
  // the login / home screen is rendered first; the permission dialog then
  // appears on top of it, and dismissing it returns the user to the real
  // app, not to the splash.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(NotificationService().init());
    unawaited(MessagingService().init().then((_) {
      if (token != null) {
        // Re-register FCM token now that init has settled. Pre-1.0.13 this
        // happened in parallel with init() and occasionally raced.
        return MessagingService().registerAfterLogin();
      }
      return null;
    }));
  });

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
