
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Failed to load .env: $e");
    // Continue anyway, maybe connection string is hardcoded or not critical immediately
  }
  
  await initializeDateFormatting();

  final token = await ApiConfig.getAuthToken();
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

class DrivaraApp extends StatelessWidget {
  final String initialRoute;
  const DrivaraApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    // Watch ThemeProvider to rebuild when theme changes manually
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return MaterialApp(
      title: 'Drivara Driver',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      initialRoute: initialRoute,
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
