import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Plays a short chime then announces the planned fuel-stop with TTS
/// in the driver's preferred locale. Triggered from
/// [MessagingService] whenever an FCM payload arrives carrying
/// `event: 'fuel_proximity'`.
///
/// The 10/5/2 km tiering is decided server-side; we only consume the
/// `thresholdKm` field for chime intensity. TTS is identical at all
/// thresholds — pace and language stay constant so the driver isn't
/// listening to wildly different sentences mid-trip.
class FuelProximityAlertService {
  FuelProximityAlertService._();
  static final FuelProximityAlertService instance = FuelProximityAlertService._();

  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.45); // Slow, intelligible over cab noise.
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (e) {
      debugPrint('[fuel-proximity-alert] tts init failed: $e');
    }
    _ready = true;
  }

  /// Map the driver app's locale codes to BCP-47 tags flutter_tts wants.
  /// flutter_tts maps these to the platform-native TTS engine (Google
  /// TTS on Android, AVSpeechSynthesizer on iOS); engines pick the
  /// closest supported voice when the exact tag isn't available.
  String _bcp47ForLocale(String locale) {
    switch (locale) {
      case 'hi': return 'hi-IN';
      case 'ta': return 'ta-IN';
      case 'te': return 'te-IN';
      case 'kn': return 'kn-IN';
      case 'ml': return 'ml-IN';
      case 'en':
      default:   return 'en-IN';
    }
  }

  /// Renders the spoken message in [locale] using a small per-language
  /// template table. Kept inline so the locale stays in step with what
  /// flutter_tts is set to — pulling from LocalizationProvider would
  /// mean two sources of truth for the same string.
  String _renderMessage({
    required String locale,
    required num distanceKm,
    required String outletName,
    required num pricePerLiter,
  }) {
    final d = distanceKm.toStringAsFixed(0);
    final p = pricePerLiter.toStringAsFixed(1);
    switch (locale) {
      case 'hi':
        return 'अगला ईंधन भरने का स्थान $d किलोमीटर दूर है, $outletName, $p रुपये प्रति लीटर।';
      case 'ta':
        return 'அடுத்த எரிபொருள் நிலையம் $d கிலோமீட்டர் தொலைவில் உள்ளது, $outletName, லிட்டருக்கு $p ரூபாய்.';
      case 'te':
        return 'తదుపరి ఇంధన నింపే స్థలం $d కిలోమీటర్ల దూరంలో ఉంది, $outletName, లీటరుకు $p రూపాయలు.';
      case 'kn':
        return 'ಮುಂದಿನ ಇಂಧನ ತುಂಬುವ ಸ್ಥಳ $d ಕಿಲೋಮೀಟರ್ ದೂರದಲ್ಲಿದೆ, $outletName, ಲೀಟರ್‌ಗೆ $p ರೂಪಾಯಿ.';
      case 'ml':
        return 'അടുത്ത ഇന്ധനം നിറയ്ക്കുന്ന സ്ഥലം $d കിലോമീറ്റർ അകലെയാണ്, $outletName, ലിറ്ററിന് $p രൂപ.';
      case 'en':
      default:
        return 'Next fuel stop in $d kilometers at $outletName, $p rupees per litre.';
    }
  }

  /// Called by MessagingService when a `fuel_proximity` FCM lands.
  Future<void> announce({
    required String locale,
    required num distanceKm,
    required String outletName,
    required num pricePerLiter,
  }) async {
    await _init();
    try {
      // 1. Chime first — gives the driver ~0.6 s to register an
      //    incoming alert before the spoken sentence starts.
      await _player.play(AssetSource('sounds/fuel_chime.wav'));
    } catch (e) {
      debugPrint('[fuel-proximity-alert] chime failed: $e');
    }
    try {
      await _tts.setLanguage(_bcp47ForLocale(locale));
    } catch (_) {
      // Engine may not support the exact tag; fall through and speak
      // whatever the engine's current default is.
    }
    final msg = _renderMessage(
      locale: locale,
      distanceKm: distanceKm,
      outletName: outletName,
      pricePerLiter: pricePerLiter,
    );
    try {
      await _tts.speak(msg);
    } catch (e) {
      debugPrint('[fuel-proximity-alert] speak failed: $e');
    }
  }
}
