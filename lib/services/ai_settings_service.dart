import 'package:shared_preferences/shared_preferences.dart';

class AISettingsService {
  static const _geminiApiKeyKey = 'ol_gemini_api_key';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  static Future<String?> getGeminiApiKey() async {
    final p = await _prefs();
    return p.getString(_geminiApiKeyKey);
  }

  static Future<void> setGeminiApiKey(String key) async {
    final p = await _prefs();
    await p.setString(_geminiApiKeyKey, key);
  }
}
