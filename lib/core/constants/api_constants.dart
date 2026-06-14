/// Brutus Mobile — API endpoint constants
class ApiConstants {
  ApiConstants._();

  // ── Backend ──
  static const backendBaseUrl = 'https://brutus-web1002.vercel.app';
  static const authLogin = '/api/v1/auth/login';
  static const authRefresh = '/api/v1/auth/refresh-token';
  static const authProfile = '/api/v1/auth/profile';
  static const syncNotes = '/api/v1/sync/notes';
  static const syncMemory = '/api/v1/sync/memory';

  // ── Gemini ──
  static const geminiWsBase = 'wss://generativelanguage.googleapis.com/ws';
  static const geminiModel = 'models/gemini-2.5-flash-native-audio-preview-12-2025';
  static const geminiRestBase =
      'https://generativelanguage.googleapis.com/v1beta';
  static const geminiEmbedModel = 'text-embedding-004';
  static const geminiEmbedDims = 768;

  // ── Tavily (Web Search · Deep Research) ──
  static const tavilySearchUrl = 'https://api.tavily.com/search';

  // ── Groq (Synthesis · Oracle) ──
  static const groqBaseUrl = 'https://api.groq.com/openai/v1';
  static const groqChatCompletions = '$groqBaseUrl/chat/completions';
  static const groqDefaultModel = 'llama-3.3-70b-versatile';

  // ── Weather (Open-Meteo — free, no key) ──
  static const weatherGeoUrl = 'https://geocoding-api.open-meteo.com/v1/search';
  static const weatherUrl = 'https://api.open-meteo.com/v1/forecast';

  // ── Stocks (Yahoo Finance) ──
  static const yahooFinanceUrl = 'https://query1.finance.yahoo.com/v8/finance/chart';

  // ── Desktop Bridge ──
  static const desktopBridgePort = 9876;

  // ── Storage keys ──
  static const geminiApiKey = 'gemini_api_key';
  static const groqApiKey = 'groq_api_key';
  static const tavilyApiKey = 'tavily_api_key';
  static const huggingfaceApiKey = 'huggingface_api_key';
  static const accessToken = 'access_token';
  static const refreshToken = 'refresh_token';

  // ── Hive box names ──
  static const boxChatHistory = 'chat_history';
  static const boxNotes = 'notes';
  static const boxPreferences = 'preferences';
  static const boxResearchHistory = 'research_history';
  static const boxRagDocuments = 'rag_documents';
  static const boxOracleHistory = 'oracle_history';
}
