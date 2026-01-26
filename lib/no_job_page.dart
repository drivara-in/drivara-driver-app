import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'api_config.dart';
import 'login_page.dart';
import 'active_job_page.dart';
import 'leaderboard_page.dart';
import 'theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'providers/localization_provider.dart';

class NoJobPage extends StatefulWidget {
  const NoJobPage({super.key});

  @override
  State<NoJobPage> createState() => _NoJobPageState();
}

class _NoJobPageState extends State<NoJobPage> with WidgetsBindingObserver {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkJob(); // Check immediately on mount
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("App Resumed on NoJobPage: Checking for active job...");
      _checkJob();
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
    }
  }

  void _startPolling() {
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkJob());
  }

  Future<void> _checkJob() async {
      try {
          final res = await ApiConfig.dio.get('/driver/me/active-job');
          final activeJob = res.data['activeJob'];
          
          if (!mounted) return;

          if (activeJob != null) {
              debugPrint("New Job Found! Redirecting to ActiveJobPage.");
              _pollTimer?.cancel();
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => ActiveJobPage(job: activeJob)),
                  (route) => false
              );
          }
      } catch (e) {
          debugPrint("NoJobPage Poll Error: $e");
      }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: 0.8, 
                child: Image.asset('assets/images/drivara-icon.png', height: 80),
              ),
              const SizedBox(height: 32),
              Text(
                t.t('no_active_job'),
                style: AppTextStyles.header.copyWith(fontSize: 28),
              ),
              const SizedBox(height: 12),
              Text(
                t.t('no_active_job_desc'),
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LeaderboardPage()),
                    );
                  },
                  icon: const Icon(Icons.leaderboard),
                  label: const Text("View Leaderboard"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                     _pollTimer?.cancel();
                     await ApiConfig.logout();
                     if (context.mounted) {
                       Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginPage()), 
                          (route) => false
                       );
                     }
                  },
                  style: AppTheme.darkTheme.outlinedButtonTheme.style,
                  child: Text(t.t('logout')),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
