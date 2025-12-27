import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'permissions_page.dart';
import 'otp_page.dart';
import 'api_config.dart';
import 'providers/localization_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Requirement: By default, at time of login, set it to system default mode for theme
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      if (themeProvider.preference != ThemeMode.system) {
         themeProvider.setThemeMode(ThemeMode.system);
      }
    });
  }

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
    // Explicitly grab separate colors to debug/fix potential theme issues
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dropdownBg = isDark ? AppColors.card : AppColors.cardLight;
    final dropdownText = isDark ? AppColors.textPrimary : AppColors.textPrimaryLight;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Background - clean slab color per web design
          Positioned.fill(
            child: Container(color: Theme.of(context).scaffoldBackgroundColor),
          ),
          
          // Language Selector - Top Right
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: Consumer<LocalizationProvider>(
                  builder: (context, t, child) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Locale>(
                        value: t.locale,
                        dropdownColor: dropdownBg,
                        icon: Icon(Icons.language, color: dropdownText),
                        // Explicitly style the selected item text
                        style: AppTextStyles.body.copyWith(
                          color: dropdownText,
                          fontWeight: FontWeight.w500,
                          fontSize: 14
                        ),
                        items: [
                          DropdownMenuItem(value: const Locale('en', 'US'), child: Text("English", style: TextStyle(color: dropdownText))),
                          DropdownMenuItem(value: const Locale('hi'), child: Text("हिन्दी", style: TextStyle(color: dropdownText))),
                          DropdownMenuItem(value: const Locale('te'), child: Text("తెలుగు", style: TextStyle(color: dropdownText))),
                          DropdownMenuItem(value: const Locale('ml'), child: Text("മലയാളം", style: TextStyle(color: dropdownText))),
                          DropdownMenuItem(value: const Locale('kn'), child: Text("ಕನ್ನಡ", style: TextStyle(color: dropdownText))),
                          DropdownMenuItem(value: const Locale('ta'), child: Text("தமிழ்", style: TextStyle(color: dropdownText))),
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
                            color: Theme.of(context).primaryColor, 
                          ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, end: 0),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("Drivara", style: AppTextStyles.header.copyWith(fontSize: 32, height: 1, color: Theme.of(context).textTheme.bodyLarge?.color)),
                              Text("DRIVER", style: AppTextStyles.label.copyWith(fontSize: 14, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6), letterSpacing: 4)),
                            ],
                          ).animate().fadeIn(delay: 200.ms),
                        ],
                      )
                   ),
                  
                  const SizedBox(height: 48), // Increased spacing
                  
                  // Phone Input
                  TextField(
                    controller: _phoneController,
                    style: AppTextStyles.body.copyWith(fontSize: 18, color: Theme.of(context).textTheme.bodyLarge?.color),
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                       filled: true,
                       fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                       hintText: t.t('phone_hint'),
                       hintStyle: AppTextStyles.body.copyWith(color: Theme.of(context).hintColor),
                       prefixIcon: Icon(Icons.phone_android, color: Theme.of(context).iconTheme.color),
                       border: OutlineInputBorder(
                         borderRadius: BorderRadius.circular(12),
                         borderSide: BorderSide(color: Theme.of(context).dividerColor),
                       ),
                       enabledBorder: OutlineInputBorder(
                         borderRadius: BorderRadius.circular(12),
                         borderSide: BorderSide(color: Theme.of(context).dividerColor),
                       ),
                       focusedBorder: OutlineInputBorder(
                         borderRadius: BorderRadius.circular(12),
                         borderSide: BorderSide(color: Theme.of(context).primaryColor),
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
                      style: Theme.of(context).elevatedButtonTheme.style,
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
                      style: AppTextStyles.label.copyWith(color: Theme.of(context).textTheme.bodySmall?.color),
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
