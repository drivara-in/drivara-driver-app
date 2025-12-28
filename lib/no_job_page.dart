import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api_config.dart';
import 'login_page.dart';
import 'theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'providers/localization_provider.dart';

class NoJobPage extends StatelessWidget {
  const NoJobPage({super.key});

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
                child: OutlinedButton(
                  onPressed: () async {
                     await ApiConfig.logout();
                     Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginPage()), 
                        (route) => false
                     );
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
