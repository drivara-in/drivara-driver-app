
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'home_page.dart';
import 'package:provider/provider.dart';
import 'providers/localization_provider.dart';

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  // Track status of critical permissions
  PermissionStatus _locationStatus = PermissionStatus.denied;
  PermissionStatus _contactsStatus = PermissionStatus.denied;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final location = await Permission.location.status;
    final contacts = await Permission.contacts.status;

    setState(() {
      _locationStatus = location;
      _contactsStatus = contacts;
    });
  }

  /// Prominent in-app disclosure for background location. Google Play
  /// Location Policy requires this dialog to appear BEFORE the OS
  /// `ACCESS_BACKGROUND_LOCATION` prompt, and to:
  ///   • name the specific feature using background location,
  ///   • state that data is collected while the app is backgrounded,
  ///   • mention the persistent foreground notification,
  ///   • give the user a clear Continue / Not now choice.
  /// Submission gets rejected otherwise.
  Future<bool> _showBackgroundLocationDisclosure() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Allow background location?'),
        content: const Text(
          'Drivara needs background location to:\n\n'
          '• Alert you if you walk more than 1 km away from your assigned vehicle '
          '(driver-vehicle separation safety alert).\n'
          '• Chime when you are within 2 km of a planned fuel stop so you do not '
          'overshoot a pre-paid pump.\n\n'
          'Location is collected while the app is in the background during an '
          'active trip. A persistent notification titled "Drivara — Monitoring '
          'distance from your assigned vehicle" will appear whenever background '
          'location is in use.\n\n'
          'On the next screen, please tap "Allow all the time".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _requestAllPermissions() async {
    final t = Provider.of<LocalizationProvider>(context, listen: false);
    setState(() => _isLoading = true);

    // Foreground permissions first. Background location is requested separately
    // after the prominent disclosure dialog, per Google Play policy.
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.contacts,
    ].request();

    if (!mounted) return;
    setState(() {
      _locationStatus = statuses[Permission.location] ?? PermissionStatus.denied;
      _contactsStatus = statuses[Permission.contacts] ?? PermissionStatus.denied;
      _isLoading = false;
    });

    if (!_locationStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.t('perm_required_message'))),
      );
      return;
    }

    // Foreground granted → show prominent disclosure for background location.
    if (await Permission.locationAlways.isDenied) {
      final accepted = await _showBackgroundLocationDisclosure();
      if (accepted) {
        await Permission.locationAlways.request();
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.t('permissions_title'),
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ).animate().fadeIn().slideY(begin: -0.2, end: 0),
              
              const SizedBox(height: 8),
              Text(
                t.t('permissions_subtitle'),
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
                ),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 32),

              Expanded(
                child: ListView(
                  children: [
                    _PermissionItem(
                      icon: Icons.location_on,
                      title: t.t('perm_location_title'),
                      description: t.t('perm_location_desc'),
                      isGranted: _locationStatus.isGranted,
                      delay: 300.ms,
                    ),
                    _PermissionItem(
                      icon: Icons.contacts,
                      title: t.t('perm_contacts_title'),
                      description: t.t('perm_contacts_desc'),
                      isGranted: _contactsStatus.isGranted,
                      delay: 400.ms,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _requestAllPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).cardTheme.color,
                    foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading 
                    ? const SizedBox(
                        width: 24, 
                        height: 24, 
                        child: CircularProgressIndicator(strokeWidth: 2)
                      )
                    : Text(
                        t.t('allow_permissions'),
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                ),
              ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.2, end: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isGranted;
  final Duration delay;

  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.isGranted,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isGranted ? Colors.green.withOpacity(0.2) : Theme.of(context).dividerColor.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isGranted ? Icons.check : icon,
              color: isGranted ? Colors.green : Theme.of(context).iconTheme.color,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: delay).slideX(begin: 0.1, end: 0);
  }
}
