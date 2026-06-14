/// Brutus Mobile — Embedded API keys and configuration (TEMPLATE)
///
/// Copy this file to `app_config.dart` and fill in your own keys.
/// `app_config.dart` is git-ignored so real keys never get committed.
///
/// Keys can also be supplied at runtime via Settings → API Keys
/// (stored in flutter_secure_storage), in which case the embedded
/// values below may be left empty.
class AppConfig {
  AppConfig._();

  // ── Gemini (Voice + Text AI) ──
  static const geminiApiKey = '';

  // ── Groq (Deep Research, RAG) ──
  static const groqApiKey = '';

  // ── Tavily (Web Search) ──
  static const tavilyApiKey = '';

  // ── HuggingFace (Image Gen) ──
  static const huggingFaceApiKey = '';

  // ── Notion ──
  static const notionApiKey = '';
  static const notionDatabaseId = '';

  // ── Backend URLs ──
  static const backendUrl = 'https://brutus-web1002.vercel.app';
  static const frontendUrl = 'https://brutus-ai-1002.vercel.app';
}
