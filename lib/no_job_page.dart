import 'package:flutter/material.dart';
import 'dart:async';
import 'api_config.dart';
import 'active_job_page.dart';
import 'leaderboard_page.dart';
import 'pages/earnings_page.dart';
import 'pages/profile_page.dart';
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
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkJob(); // Check immediately on mount
    _startPolling();
    _fetchProfileAvatar();
  }

  Future<void> _fetchProfileAvatar() async {
    try {
      final res = await ApiConfig.dio.get('/driver/me/profile');
      final url = (res.data is Map) ? (res.data['avatar_url']?.toString()) : null;
      if (mounted) setState(() => _avatarUrl = (url != null && url.isNotEmpty) ? url : null);
    } catch (e) {
      debugPrint('[profile-avatar] fetch failed: $e');
    }
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
      // Lightweight top bar just for the Profile entry point — the page is
      // otherwise a centered "no job" splash. Logout used to live as a
      // full-width button at the bottom; it now lives inside Profile (with a
      // confirm dialog) so a casual tap can't sign the driver out.
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                ? CircleAvatar(radius: 14, backgroundImage: NetworkImage(_avatarUrl!))
                : const Icon(Icons.account_circle_outlined),
            tooltip: 'Profile',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
            },
          ),
        ],
      ),
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
                      MaterialPageRoute(builder: (_) => const EarningsPage()),
                    );
                  },
                  icon: const Icon(Icons.payments),
                  label: const Text('My Earnings'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
                  label: Text(Provider.of<LocalizationProvider>(context, listen: false).t('view_leaderboard') ?? 'View Leaderboard'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
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
