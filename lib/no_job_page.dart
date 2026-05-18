import 'package:flutter/material.dart';
import 'dart:async';
import 'api_config.dart';
import 'active_job_page.dart';
import 'leaderboard_page.dart';
import 'pages/earnings_page.dart';
import 'pages/loans_page.dart';
import 'pages/profile_page.dart';
import 'theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'providers/localization_provider.dart';

// The between-trips screen. Used to be a tiny "no active job" splash with
// a logout button and a profile glyph hidden in the AppBar — drivers
// often missed Loans/Earnings entry points because the only obvious tap
// target was the splash icon. Rebuilt as a dashboard:
//
//   • Prominent tappable avatar that opens Profile (where Loans, DL, RC,
//     and Logout live), with a small "person" indicator nub overlay so
//     it visually invites a tap.
//   • Personalised greeting using the driver's name.
//   • Action tiles for Earnings, Loans, Leaderboard and Profile — all
//     localised. Each tile is the same shape so the page reads cleanly
//     regardless of locale string length.
class NoJobPage extends StatefulWidget {
  const NoJobPage({super.key});

  @override
  State<NoJobPage> createState() => _NoJobPageState();
}

class _NoJobPageState extends State<NoJobPage> with WidgetsBindingObserver {
  Timer? _pollTimer;
  String? _avatarUrl;
  String? _driverName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkJob();
    _startPolling();
    _fetchProfileSnapshot();
  }

  Future<void> _fetchProfileSnapshot() async {
    try {
      final res = await ApiConfig.dio.get('/driver/me/profile');
      final url = (res.data is Map) ? (res.data['avatar_url']?.toString()) : null;
      final name = (res.data is Map) ? (res.data['name']?.toString()) : null;
      if (mounted) {
        setState(() {
          _avatarUrl = (url != null && url.isNotEmpty) ? url : null;
          _driverName = (name != null && name.isNotEmpty) ? name : null;
        });
      }
    } catch (e) {
      debugPrint('[profile-snapshot] fetch failed: $e');
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
      debugPrint('App Resumed on NoJobPage: Checking for active job...');
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
        debugPrint('New Job Found! Redirecting to ActiveJobPage.');
        _pollTimer?.cancel();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => ActiveJobPage(job: activeJob)),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('NoJobPage Poll Error: $e');
    }
  }

  void _openProfile() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
  }

  void _openEarnings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const EarningsPage()));
  }

  void _openLoans() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LoansPage()));
  }

  void _openLeaderboard() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardPage()));
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      // The page is content-driven now; a translucent AppBar without
      // actions keeps the chrome out of the way of the hero.
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 36,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([_checkJob(), _fetchProfileSnapshot()]);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Brand mark — small, low contrast so the avatar reads as
                // the primary visual element.
                Center(
                  child: Opacity(
                    opacity: 0.55,
                    child: Image.asset('assets/images/drivara-icon.png', height: 36),
                  ),
                ),
                const SizedBox(height: 24),

                // Hero avatar. Big, tappable, with a small overlay nub so
                // the affordance is unmistakable.
                Center(
                  child: _AvatarHero(
                    avatarUrl: _avatarUrl,
                    onTap: _openProfile,
                  ),
                ),
                const SizedBox(height: 14),

                // Greeting line. Falls back to a localized "Welcome back"
                // when the name hasn't loaded yet.
                Center(
                  child: Text(
                    _driverName != null
                        ? (t.t('greeting_hi_name') ?? 'Hi, {name}')
                            .replaceAll('{name}', _driverName!)
                        : (t.t('greeting_welcome_back') ?? 'Welcome back'),
                    style: AppTextStyles.header.copyWith(
                      fontSize: 22,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    t.t('tap_avatar_for_profile') ??
                        'Tap your photo for profile, loans and more.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.label.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Status card — "No active trip" framed positively, not
                // as a dead-end. Aux line nudges the driver to use the
                // tiles below to catch up on past trips / loans.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.coffee_outlined,
                          color: Colors.amber.shade800,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.t('no_active_job') ?? 'No active trip',
                              style: AppTextStyles.header.copyWith(
                                fontSize: 16,
                                color: theme.textTheme.bodyLarge?.color,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              t.t('no_active_job_desc') ??
                                  'Hang tight — your next trip will appear here automatically.',
                              style: AppTextStyles.label.copyWith(
                                color: theme.textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Quick actions header
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    (t.t('quick_actions') ?? 'Quick actions').toUpperCase(),
                    style: AppTextStyles.label.copyWith(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w800,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ),
                _ActionTile(
                  icon: Icons.payments_outlined,
                  iconColor: const Color(0xFF059669), // emerald-600
                  label: t.t('earnings_title') ?? 'My Earnings',
                  subtitle: t.t('earnings_subtitle') ??
                      'See what you earned across recent trips',
                  onTap: _openEarnings,
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.account_balance_outlined,
                  iconColor: const Color(0xFF4F46E5), // indigo-600
                  label: t.t('loans_title') ?? 'My Loans',
                  subtitle: t.t('loans_subtitle') ??
                      'Active loans, installments, and payments',
                  onTap: _openLoans,
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.leaderboard_outlined,
                  iconColor: const Color(0xFFD97706), // amber-600
                  label: t.t('view_leaderboard') ?? 'View leaderboard',
                  subtitle: t.t('leaderboard_subtitle') ??
                      'How you compare with other drivers',
                  onTap: _openLeaderboard,
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.account_circle_outlined,
                  iconColor: AppColors.primary,
                  label: t.t('profile_title') ?? 'Profile',
                  subtitle: t.t('profile_subtitle') ??
                      'Driving licence, vehicle docs, and sign out',
                  onTap: _openProfile,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarHero extends StatelessWidget {
  final String? avatarUrl;
  final VoidCallback onTap;

  const _AvatarHero({required this.avatarUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(54),
      child: Stack(
        alignment: Alignment.bottomRight,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withOpacity(0.28),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(3.5),
            child: ClipOval(
              child: (avatarUrl != null && avatarUrl!.isNotEmpty)
                  ? Image.network(
                      avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.white,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.person,
                          size: 56,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.white,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.person,
                        size: 56,
                        color: Color(0xFF4F46E5),
                      ),
                    ),
            ),
          ),
          // Bottom-right "edit" nub — visual affordance that this avatar
          // is interactive (opens profile).
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: Color(0xFF4F46E5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.header.copyWith(
                        fontSize: 15,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(
                        color: theme.textTheme.bodySmall?.color,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
