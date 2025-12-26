import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:pinput/pinput.dart';
import 'package:smart_auth/smart_auth.dart';
import 'api_config.dart';
import 'active_job_page.dart';
import 'no_job_page.dart';
import 'theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'providers/localization_provider.dart';

class OtpPage extends StatefulWidget {
  final String phone;
  const OtpPage({super.key, required this.phone});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final _otpController = TextEditingController();
  final _smartAuth = SmartAuth();
  bool _isLoading = false;
  String? _error;
  String? _appSignature;


  @override
  void initState() {
    super.initState();
    _startSmsListening();
  }

  void _startSmsListening() async {
    try {
      final signature = await _smartAuth.getAppSignature();
      debugPrint('App Signature: $signature');
      if (mounted) setState(() => _appSignature = signature);
      
      final res = await _smartAuth.getSmsCode(
        useUserConsentApi: true,
      );
      if (res.succeed && res.code != null) {
        debugPrint('SMS Code Received: \${res.code}');
        _otpController.setText(res.code!);
      }
    } catch (e) {
      debugPrint('SMS Listener Error: \$e');
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 1. Verify OTP
      final response = await ApiConfig.dio.post('/driver/auth/verify-otp', data: {
        'phone': widget.phone,
        'code': otp,
      });

      if (response.data['ok'] == true) {
        final token = response.data['token'];
        await ApiConfig.setAuthToken(token);

        // 2. Fetch Active Job
        await _checkActiveJob();
      } else {
        setState(() => _error = response.data['message'] ?? 'Verification failed');
      }
    } on DioException catch (e) {
      setState(() => _error = e.response?.data['message'] ?? e.message ?? 'Network error');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkActiveJob() async {
    try {
      final response = await ApiConfig.dio.get('/driver/me/active-job');
      final activeJob = response.data['activeJob'];

      if (!mounted) return;

      if (activeJob != null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => ActiveJobPage(job: activeJob)),
          (route) => false,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const NoJobPage()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => _error = "Failed to fetch job status: \$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<LocalizationProvider>(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                   Image.asset('assets/images/drivara-icon.png', height: 72, color: Colors.white),
                   const SizedBox(width: 12),
                   Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("Drivara", style: AppTextStyles.header.copyWith(fontSize: 32, height: 1)),
                      Text("DRIVER", style: AppTextStyles.label.copyWith(fontSize: 14, color: AppColors.textTertiary, letterSpacing: 4)),
                    ],
                   )
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text(
              t.t('enter_otp'),
              style: AppTextStyles.header.copyWith(fontSize: 32),
            ),
            const SizedBox(height: 8),
            Text(
              'Sent to \${widget.phone}',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 48),

            Pinput(
              autofillHints: const [AutofillHints.oneTimeCode],
              controller: _otpController,
              length: 6,
              defaultPinTheme: PinTheme(
                width: 56,
                height: 56,
                textStyle: AppTextStyles.header.copyWith(fontSize: 24, color: Colors.white),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
              ),
              focusedPinTheme: PinTheme(
                width: 56,
                height: 56,
                textStyle: AppTextStyles.header.copyWith(fontSize: 24, color: AppColors.primary),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary),
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8)]
                ),
              ),
              errorPinTheme: PinTheme(
                width: 56,
                height: 56,
                textStyle: AppTextStyles.header.copyWith(fontSize: 24, color: AppColors.error),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error),
                ),
              ),
              onCompleted: (pin) => _verifyOtp(),
              hapticFeedbackType: HapticFeedbackType.lightImpact,
            ),
            
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: AppTextStyles.body.copyWith(color: AppColors.error)),
            ],

            const Spacer(),
            
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verifyOtp,
                style: AppTheme.darkTheme.elevatedButtonTheme.style!.copyWith(
                    backgroundColor: MaterialStateProperty.all(AppColors.success)
                ),
                child: _isLoading 
                    ? const Center(child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))) 
                    : Text(t.t('verify_otp'), style: AppTextStyles.header.copyWith(fontSize: 18)),
              ),
            ),
             const SizedBox(height: 24),
             /*
             if (_appSignature != null)
               Padding(
                 padding: const EdgeInsets.only(bottom: 20),
                 child: SelectableText(
                   "App Sig: \$_appSignature", 
                   style: const TextStyle(color: Colors.white54, fontSize: 10)
                 ),
               ),
             */
          ],
        ),
      ),
    );
  }
}
