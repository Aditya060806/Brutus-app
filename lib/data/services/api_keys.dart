import 'package:brutus_app/core/constants/app_config.dart';
import 'package:brutus_app/data/services/secure_storage_service.dart';

/// Brutus Mobile — Centralised API key resolver.
///
/// Resolves an API key with the priority:
///   1. flutter_secure_storage (user-supplied via Settings → API Keys)
///   2. Embedded default in [AppConfig] (so the APK ships ready-to-go)
///   3. `null` — caller surfaces "Add your &lt;provider&gt; key in Settings".
///
/// Each call hits secure storage fresh so a key the user just cleared
/// doesn't accidentally stay alive in memory across requests.
class ApiKeys {
  ApiKeys._();

  static Future<String?> _resolve(
    Future<String?> Function() reader,
    String embedded,
  ) async {
    try {
      final stored = await reader();
      if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    } catch (_) {
      // secure-storage I/O can throw on broken keystores — fall through.
    }
    final fallback = embedded.trim();
    return fallback.isEmpty ? null : fallback;
  }

  static Future<String?> gemini() =>
      _resolve(SecureStorageService.getGeminiKey, AppConfig.geminiApiKey);

  static Future<String?> groq() =>
      _resolve(SecureStorageService.getGroqKey, AppConfig.groqApiKey);

  static Future<String?> tavily() =>
      _resolve(SecureStorageService.getTavilyKey, AppConfig.tavilyApiKey);

  static Future<String?> huggingFace() => _resolve(
        SecureStorageService.getHuggingFaceKey,
        AppConfig.huggingFaceApiKey,
      );
}

/// Thrown by services when no key (stored or embedded) is available. The
/// message is shaped for direct display in the UI's inline error card.
class MissingApiKeyException implements Exception {
  final String provider;
  const MissingApiKeyException(this.provider);
  @override
  String toString() =>
      'Add your $provider key in Settings → API Keys to use this feature.';
}
