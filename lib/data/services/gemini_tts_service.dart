import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';

import 'package:brutus_app/core/constants/app_config.dart';
import 'package:brutus_app/data/services/audio_playback_service.dart';
import 'package:brutus_app/data/services/secure_storage_service.dart';

/// Brutus Mobile — Gemini TTS service.
///
/// Uses the **Gemini Live native-audio WebSocket** (same model and voice as
/// live voice chat) to synthesize speech in Brutus's actual Puck/Aoede voice.
///
/// Why not the `gemini-2.5-flash-preview-tts` REST endpoint?
///   • Free-tier quota on that model is ~3 requests/minute, ~15/day. Users
///     hit 429 within a handful of "Speak for me" taps.
///   • The Live WebSocket model has a far more generous quota (it's the
///     same quota Brutus's voice chat already runs on, which works for
///     long conversations).
///   • Both produce identical audio (24 kHz mono 16-bit PCM in Puck's
///     voice), so there's no quality trade-off.
///
/// Flow:
///   1. Open a fresh, short-lived WebSocket to the Live endpoint.
///   2. Send a setup payload with a strict TTS-only system instruction.
///   3. Send the user's text via `clientContent`.
///   4. Pipe every `inlineData` audio chunk into [AudioPlaybackService].
///   5. Close the socket on `turnComplete` (or 30 s timeout).
class GeminiTtsService {
  GeminiTtsService._();
  static final GeminiTtsService instance = GeminiTtsService._();

  static const _liveModel =
      'models/gemini-2.5-flash-native-audio-preview-12-2025';
  static const _wsUrlBase =
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  /// Resolve the Gemini API key. Same precedence as [GeminiVoiceService]:
  /// secure storage override first, then the embedded key.
  Future<String> _resolveKey() async {
    try {
      final stored = await SecureStorageService.getGeminiKey();
      if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    } catch (_) {}
    return AppConfig.geminiApiKey.trim();
  }

  String _voiceName() {
    try {
      final box = Hive.box('preferences');
      final raw = box.get('brutus_voice_profile') as String?;
      return raw == 'FEMALE' ? 'Aoede' : 'Puck';
    } catch (_) {
      return 'Puck';
    }
  }

  void _log(String msg) => dev.log('[GeminiTTS] $msg', name: 'BrutusAI');

  /// Synthesize [text] in [lang] using Gemini Live and pipe the resulting
  /// PCM through [AudioPlaybackService]. Returns true on success.
  ///
  /// [lang] accepts BCP-47 codes (`en-US`, `hi-IN`). The native-audio model
  /// detects language from the input automatically; we pass [lang] purely
  /// to refine the system-instruction tone (Hindi vs English).
  Future<bool> speak(String text, {String lang = 'en-US'}) async {
    final clean = text.trim();
    if (clean.isEmpty) return false;

    final key = await _resolveKey();
    if (key.isEmpty) {
      _log('No Gemini key configured — skipping TTS.');
      return false;
    }

    WebSocket? socket;
    final completer = Completer<bool>();
    Timer? hardTimeout;
    var setupComplete = false;
    var queuedChunks = 0;

    try {
      final url = '$_wsUrlBase?key=$key';
      socket = await WebSocket.connect(url).timeout(
        const Duration(seconds: 8),
      );

      // Hard cap — even if the server forgets to send turnComplete, close
      // the socket and return whatever audio we've already piped.
      hardTimeout = Timer(const Duration(seconds: 30), () {
        if (!completer.isCompleted) {
          _log('TTS hard timeout — closing socket.');
          completer.complete(queuedChunks > 0);
          try { socket?.close(); } catch (_) {}
        }
      });

      socket.listen(
        (data) async {
          if (completer.isCompleted) return;
          try {
            final str = data is String ? data : utf8.decode(data as List<int>);
            final parsed = jsonDecode(str) as Map<String, dynamic>;

            // Setup ack — once received, send the actual TTS turn.
            if (parsed.containsKey('setupComplete')) {
              setupComplete = true;
              _sendTtsTurn(socket!, clean);
              return;
            }

            final serverContent =
                parsed['serverContent'] as Map<String, dynamic>?;
            if (serverContent == null) return;

            // Extract audio from modelTurn parts and queue for playback.
            final modelTurn = serverContent['modelTurn'] as Map<String, dynamic>?;
            if (modelTurn != null) {
              final parts = (modelTurn['parts'] as List?) ?? const [];
              for (final part in parts) {
                final m = part as Map<String, dynamic>;
                final inline =
                    (m['inlineData'] ?? m['inline_data']) as Map<String, dynamic>?;
                if (inline == null) continue;
                final mime = inline['mimeType'] as String? ??
                    inline['mime_type'] as String? ??
                    '';
                if (!mime.startsWith('audio/')) continue;
                final b64 = inline['data'] as String? ?? '';
                if (b64.isEmpty) continue;
                await AudioPlaybackService.instance.queueChunk(b64);
                queuedChunks++;
              }
            }

            // Done — close the socket and resolve.
            if (serverContent['turnComplete'] == true ||
                serverContent['interrupted'] == true) {
              if (!completer.isCompleted) {
                completer.complete(queuedChunks > 0);
              }
              try { socket?.close(); } catch (_) {}
            }
          } catch (e) {
            _log('parse error: $e');
          }
        },
        onError: (err) {
          _log('socket error: $err');
          if (!completer.isCompleted) completer.complete(queuedChunks > 0);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(queuedChunks > 0);
        },
      );

      // Send setup — strict TTS persona so the model speaks verbatim.
      socket.add(jsonEncode({
        'setup': {
          'model': _liveModel,
          'systemInstruction': {
            'parts': [
              {'text': _ttsSystemInstruction(lang)},
            ],
          },
          'generationConfig': {
            'responseModalities': ['AUDIO'],
            'speechConfig': {
              'voiceConfig': {
                'prebuiltVoiceConfig': {'voiceName': _voiceName()},
              },
            },
          },
        },
      }));

      final ok = await completer.future;
      if (!setupComplete) {
        _log('TTS aborted before setup completed.');
      } else if (ok) {
        _log('Spoke ${clean.length} chars in ${_voiceName()} '
            '($lang) — $queuedChunks chunk(s)');
      } else {
        _log('TTS produced no audio (queuedChunks=0).');
      }
      return ok;
    } on TimeoutException {
      _log('Live TTS connect timed out.');
      return false;
    } catch (e) {
      _log('TTS failed: $e');
      return false;
    } finally {
      hardTimeout?.cancel();
      try { await socket?.close(); } catch (_) {}
    }
  }

  /// Send the user's text as a single completed turn. The strict system
  /// instruction we set during setup ensures Gemini just speaks it back.
  void _sendTtsTurn(WebSocket socket, String text) {
    socket.add(jsonEncode({
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': text},
            ],
          },
        ],
        'turnComplete': true,
      },
    }));
  }

  /// Persona instructions that turn the Live model into a verbatim TTS
  /// engine. Critical: the model must NOT add a greeting, NOT translate,
  /// NOT comment — it must produce only the spoken version of the user's
  /// input in the chosen language.
  String _ttsSystemInstruction(String lang) {
    final isHindi = lang.startsWith('hi');
    final langLine = isHindi
        ? "The user's text may be in Hindi (Devanagari) or Hinglish; speak it in a natural Hindi voice."
        : "Speak in clear, natural English.";
    return '''
You are a Text-To-Speech engine, NOT a conversational AI.
RULES:
1. Read the user's input aloud EXACTLY as written, word-for-word.
2. Do not greet, do not introduce, do not summarise, do not translate, do not comment.
3. Do not say "Sure" or "Here is your text" or anything similar.
4. If the input contains a question, do NOT answer it — just read it aloud.
5. Speak with natural intonation appropriate to the punctuation.
6. $langLine
Your only output is the spoken audio of the user's exact text.
''';
  }

  /// Stop any in-flight playback. Doesn't cancel an HTTP/WS request that's
  /// still in flight — those finish quickly enough that it's not worth the
  /// added complexity.
  Future<void> stop() async {
    await AudioPlaybackService.instance.stop();
  }
}
