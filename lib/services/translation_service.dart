import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:flutter/foundation.dart';

class TranslationService {
  static final TranslationService _instance = TranslationService._internal();

  factory TranslationService() {
    return _instance;
  }

  TranslationService._internal();

  // Cache translators to avoid recreating them constantly
  final Map<String, OnDeviceTranslator> _translators = {};

  Future<String> translate(String text, String targetLanguageCode) async {
    // English is the source, skipping translation if target is English
    if (targetLanguageCode == 'en') return text;

    try {
      final translator = await _getTranslator(targetLanguageCode);
      final translatedText = await translator.translateText(text);
      return translatedText;
    } catch (e) {
      debugPrint('Translation Error: $e');
      return text; // Fallback to original text
    }
  }

  Future<OnDeviceTranslator> _getTranslator(String targetLang) async {
    if (_translators.containsKey(targetLang)) {
      return _translators[targetLang]!;
    }

    // Map ISO codes if necessary (ML Kit uses BCP 47 tags mostly)
    // Our app uses: hi, te, ml, kn, ta
    TranslateLanguage target;
    switch (targetLang) {
      case 'hi': target = TranslateLanguage.hindi; break;
      case 'te': target = TranslateLanguage.telugu; break;
      case 'ml': 
        // ML Kit (v0.10.1) does not support Malayalam
        debugPrint('Malayalam not supported by ML Kit');
        return _getTranslator('en');
      case 'kn': target = TranslateLanguage.kannada; break;
      case 'ta': target = TranslateLanguage.tamil; break;
      case 'mr': target = TranslateLanguage.marathi; break;
      case 'bn': target = TranslateLanguage.bengali; break;
      default: 
        debugPrint('Unsupported language for ML Kit: $targetLang');
        throw Exception('Unsupported language: $targetLang');
    }

    final modelManager = OnDeviceTranslatorModelManager();
    final bool isDownloaded = await modelManager.isModelDownloaded(target.bcpCode);
    
    if (!isDownloaded) {
      debugPrint('Downloading model for $targetLang...');
      try {
         await modelManager.downloadModel(target.bcpCode);
         debugPrint('Downloaded model for $targetLang');
      } catch (e) {
         debugPrint('Failed to download model for $targetLang: $e');
         // Can't translate without model
         throw e; 
      }
    }

    final translator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: target,
    );
    
    _translators[targetLang] = translator;
    return translator;
  }

  void dispose() {
    for (var translator in _translators.values) {
      translator.close();
    }
    _translators.clear();
  }
}
