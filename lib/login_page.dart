import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'permissions_page.dart';
import 'otp_page.dart';
import 'api_config.dart';
import 'providers/localization_provider.dart';
import 'theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a phone number")));
        return;
    }

    setState(() => _isLoading = true);
    
    try {
      final response = await ApiConfig.dio.post('/driver/auth/send-otp', data: {'phone': phone});
      
      if (!mounted) return;

      if (response.data['ok'] == true) {
         Navigator.of(context).push(
           MaterialPageRoute(builder: (_) => OtpPage(phone: phone)),
         );
      } else {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response.data['message'] ?? "Login failed")));
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.response?.data['message'] ?? e.message ?? "Network error")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background - clean slab color per web design
          Positioned.fill(
            child: Container(color: AppColors.background),
          ),
          
          // Language Selector - Top Right
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: Consumer<LocalizationProvider>(
                  builder: (context, t, child) => DropdownButtonHideUnderline(
                    child: DropdownButton<Locale>(
                      value: t.locale,
                      dropdownColor: AppColors.card,
                      icon: const Icon(Icons.language, color: AppColors.textSecondary),
                      items: const [
                        DropdownMenuItem(value: Locale('en', 'US'), child: Text("English", style: TextStyle(color: AppColors.textPrimary))),
                        DropdownMenuItem(value: Locale('hi'), child: Text("हिन्दी", style: TextStyle(color: AppColors.textPrimary))),
                        DropdownMenuItem(value: Locale('te'), child: Text("తెలుగు", style: TextStyle(color: AppColors.textPrimary))),
                        DropdownMenuItem(value: Locale('ml'), child: Text("മലയാളം", style: TextStyle(color: AppColors.textPrimary))),
                        DropdownMenuItem(value: Locale('kn'), child: Text("ಕನ್ನಡ", style: TextStyle(color: AppColors.textPrimary))),
                        DropdownMenuItem(value: Locale('ta'), child: Text("தமிழ்", style: TextStyle(color: AppColors.textPrimary))),
                      ],
                      onChanged: (val) {
                        if (val != null) t.setLocale(val);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   // Drivara Branding
                   Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/drivara-icon.png',
                            height: 72, // Larger
                            fit: BoxFit.contain,
                            color: Colors.white, 
                          ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, end: 0),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("Drivara", style: AppTextStyles.header.copyWith(fontSize: 32, height: 1)),
                              Text("DRIVER", style: AppTextStyles.label.copyWith(fontSize: 14, color: AppColors.textTertiary, letterSpacing: 4)),
                            ],
                          ).animate().fadeIn(delay: 200.ms),
                        ],
                      )
                   ),
                  
                  const SizedBox(height: 48), // Increased spacing
                  
                  // Phone Input
                  TextField(
                    controller: _phoneController,
                    style: AppTextStyles.body.copyWith(fontSize: 18),
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                       filled: true,
                       fillColor: AppColors.card,
                       hintText: t.t('phone_hint'),
                       hintStyle: AppTextStyles.body.copyWith(color: AppColors.textTertiary),
                       prefixIcon: const Icon(Icons.phone_android, color: AppColors.textSecondary),
                       border: OutlineInputBorder(
                         borderRadius: BorderRadius.circular(12),
                         borderSide: const BorderSide(color: AppColors.cardBorder),
                       ),
                       enabledBorder: OutlineInputBorder(
                         borderRadius: BorderRadius.circular(12),
                         borderSide: const BorderSide(color: AppColors.cardBorder),
                       ),
                       focusedBorder: OutlineInputBorder(
                         borderRadius: BorderRadius.circular(12),
                         borderSide: const BorderSide(color: AppColors.primary),
                       ),
                       contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    ),
                  ).animate().fadeIn(delay: 400.ms, duration: 600.ms).slideY(begin: 0.2, end: 0),

                  const SizedBox(height: 24),

                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: AppTheme.darkTheme.elevatedButtonTheme.style,
                      child: _isLoading 
                        ? const Center(child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                        : Text(t.t('get_started')),
                    ),
                  ).animate().fadeIn(delay: 600.ms, duration: 600.ms).slideY(begin: 0.2, end: 0),
                  
                  const SizedBox(height: 24),
                   Center(
                    child: Text(
                      'By continuing, you agree to our Terms & Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.label,
                    ),
                  ).animate().fadeIn(delay: 800.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
