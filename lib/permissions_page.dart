
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
  PermissionStatus _smsStatus = PermissionStatus.denied;
  PermissionStatus _callLogStatus = PermissionStatus.denied;
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final location = await Permission.location.status;
    final contacts = await Permission.contacts.status;
    final sms = await Permission.sms.status;
    final callLog = await Permission.phone.status; // Using phone/call logs group usually

    setState(() {
      _locationStatus = location;
      _contactsStatus = contacts;
      _smsStatus = sms;
      _callLogStatus = callLog;
    });
  }

  Future<void> _requestAllPermissions() async {
    final t = Provider.of<LocalizationProvider>(context, listen: false);
    setState(() => _isLoading = true);

    // Request permissions
    // Note: Android 11+ might require multiple steps for background location
    // We start with foreground location, then background if needed.
    
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.contacts,
      Permission.sms, // Careful: Google Play strict policy
      Permission.phone, // For Call logs
    ].request();

    // Check results
    if (mounted) {
        setState(() {
            _locationStatus = statuses[Permission.location] ?? PermissionStatus.denied;
            _contactsStatus = statuses[Permission.contacts] ?? PermissionStatus.denied;
            _smsStatus = statuses[Permission.sms] ?? PermissionStatus.denied;
            _callLogStatus = statuses[Permission.phone] ?? PermissionStatus.denied;
            _isLoading = false;
        });

        // Simple logic: if at least location is granted, proceed
        // In a real app, you might block until all critical ones are granted.
        if (_locationStatus.isGranted) {
             // Try to request background location separately for Android 10+
             if (await Permission.locationAlways.isDenied) {
                // Ideally show a dialog explaining why
                await Permission.locationAlways.request();
             }
             
             Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomePage()),
             );
        } else {
             ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t.t('perm_required_message'))),
             );
        }
    }
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
                    _PermissionItem(
                      icon: Icons.sms,
                      title: t.t('perm_sms_title'),
                      description: t.t('perm_sms_desc'),
                      isGranted: _smsStatus.isGranted,
                      delay: 500.ms,
                    ),
                    _PermissionItem(
                      icon: Icons.phone_in_talk,
                      title: t.t('perm_call_log_title'),
                      description: t.t('perm_call_log_desc'),
                      isGranted: _callLogStatus.isGranted,
                      delay: 600.ms,
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
