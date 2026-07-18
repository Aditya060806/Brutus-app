import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:brutus_app/core/constants/api_constants.dart';

/// Brutus Mobile — Secure key vault
/// Uses flutter_secure_storage for encrypted API key storage
/// Mirrors Electron's safeStorage functionality
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── API Keys ──
  static Future<String?> getGeminiKey() =>
      _storage.read(key: ApiConstants.geminiApiKey);

  static Future<void> setGeminiKey(String key) =>
      _storage.write(key: ApiConstants.geminiApiKey, value: key);

  static Future<String?> getGroqKey() =>
      _storage.read(key: ApiConstants.groqApiKey);

  static Future<void> setGroqKey(String key) =>
      _storage.write(key: ApiConstants.groqApiKey, value: key);

  static Future<String?> getTavilyKey() =>
      _storage.read(key: ApiConstants.tavilyApiKey);

  static Future<void> setTavilyKey(String key) =>
      _storage.write(key: ApiConstants.tavilyApiKey, value: key);

  static Future<String?> getHuggingFaceKey() =>
      _storage.read(key: ApiConstants.huggingfaceApiKey);

  static Future<void> setHuggingFaceKey(String key) =>
      _storage.write(key: ApiConstants.huggingfaceApiKey, value: key);

  static Future<String?> getSarvamKey() =>
      _storage.read(key: ApiConstants.sarvamApiKey);

  static Future<void> setSarvamKey(String key) =>
      _storage.write(key: ApiConstants.sarvamApiKey, value: key);

  // ── Auth tokens ──
  static Future<String?> getAccessToken() =>
      _storage.read(key: ApiConstants.accessToken);

  static Future<void> setAccessToken(String token) =>
      _storage.write(key: ApiConstants.accessToken, value: token);

  static Future<String?> getRefreshToken() =>
      _storage.read(key: ApiConstants.refreshToken);

  static Future<void> setRefreshToken(String token) =>
      _storage.write(key: ApiConstants.refreshToken, value: token);

  // ── Utility ──
  static Future<void> clearAll() => _storage.deleteAll();

  static Future<Map<String, bool>> getKeyStatus() async {
    return {
      'gemini': (await getGeminiKey())?.isNotEmpty ?? false,
      'groq': (await getGroqKey())?.isNotEmpty ?? false,
      'tavily': (await getTavilyKey())?.isNotEmpty ?? false,
      'huggingface': (await getHuggingFaceKey())?.isNotEmpty ?? false,
      'sarvam': (await getSarvamKey())?.isNotEmpty ?? false,
    };
  }
}
