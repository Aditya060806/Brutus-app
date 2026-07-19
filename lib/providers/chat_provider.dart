import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:camera/camera.dart' show CameraLensDirection;

import 'package:brutus_app/data/services/audio_playback_service.dart';
import 'package:brutus_app/data/services/audio_recorder_service.dart';
import 'package:brutus_app/data/services/edge_brain_service.dart';
import 'package:brutus_app/data/services/gemini_tts_service.dart';
import 'package:brutus_app/data/services/gemini_voice_service.dart';
import 'package:brutus_app/data/services/sarvam_client.dart';
import 'package:brutus_app/data/services/voice_backend.dart';
import 'package:brutus_app/data/services/screen_share_service.dart';
import 'package:brutus_app/data/services/tool_dispatcher.dart';
import 'package:brutus_app/data/services/vision_service.dart';
import 'package:brutus_app/providers/ai_engine_provider.dart';
import 'package:brutus_app/providers/automation_provider.dart';
import 'package:brutus_app/providers/deep_research_provider.dart';
import 'package:brutus_app/providers/email_provider.dart';
import 'package:brutus_app/providers/gallery_provider.dart';
import 'package:brutus_app/providers/maps_provider.dart';
import 'package:brutus_app/providers/notes_provider.dart';
import 'package:brutus_app/providers/rag_oracle_provider.dart';
import 'package:brutus_app/providers/robot_provider.dart';

// Re-export the data mode enum so screens can pick it up from a single import.
export 'package:brutus_app/data/services/vision_service.dart'
    show VisionDataMode, VisionDataModeX;
export 'package:brutus_app/data/services/screen_share_service.dart'
    show ScreenShareDataMode, ScreenShareDataModeX, ScreenShareStartResult;

// ── Models ───────────────────────────────────────────────────────────────────

enum MessageRole { user, assistant, tool }

enum VoiceStatus { idle, connecting, listening, thinking, speaking, error }

/// Whose live transcript should be displayed in the input bar right now.
enum LiveTranscriptOwner { none, user, ai }

/// Vision (camera) state for sending live frames to Gemini.
enum VisionMode { off, frontCamera, backCamera }

class ChatMessage {
  final String id;
  final String text;
  final MessageRole role;
  final DateTime timestamp;
  final String? toolName;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.role,
    required this.timestamp,
    this.toolName,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'role': role.name,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'toolName': toolName,
      };

  factory ChatMessage.fromMap(Map map) {
    final roleName = map['role'] as String? ?? 'assistant';
    final role = MessageRole.values.firstWhere(
      (r) => r.name == roleName,
      orElse: () => MessageRole.assistant,
    );
    return ChatMessage(
      id: map['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      text: map['text'] as String? ?? '',
      role: role,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestamp'] as int? ?? 0,
      ),
      toolName: map['toolName'] as String?,
    );
  }
}

class ChatState {
  final List<ChatMessage> messages;
  final VoiceStatus status;
  final bool isConnected;
  final bool isMicMuted; // false = live audio flowing, true = audio dropped
  final String? currentToolName;
  final String? errorMessage;
  final String liveTranscript;
  final LiveTranscriptOwner liveOwner;
  final double audioLevel; // 0.0 to 1.0 — mic input level
  final bool needsPermissionSettings;
  final bool isLiveMode;
  // Vision
  final VisionMode visionMode;
  final bool visionNeedsSettings;
  final int visionFramesSent;
  final int visionFramesFailed;
  final VisionDataMode visionDataMode;
  // Screen share
  final bool screenShareOn;
  final int screenFramesSent;
  final int screenFramesFailed;
  final ScreenShareDataMode screenShareDataMode;
  // Robot emotion (parsed from Gemini's [EMOTION:xxx] tag)
  final String? detectedEmotion;

  const ChatState({
    this.messages = const [],
    this.status = VoiceStatus.idle,
    this.isConnected = false,
    this.isMicMuted = false,
    this.currentToolName,
    this.errorMessage,
    this.liveTranscript = '',
    this.liveOwner = LiveTranscriptOwner.none,
    this.audioLevel = 0.0,
    this.needsPermissionSettings = false,
    this.isLiveMode = false,
    this.visionMode = VisionMode.off,
    this.visionNeedsSettings = false,
    this.visionFramesSent = 0,
    this.visionFramesFailed = 0,
    this.visionDataMode = VisionDataMode.standard,
    this.screenShareOn = false,
    this.screenFramesSent = 0,
    this.screenFramesFailed = 0,
    this.screenShareDataMode = ScreenShareDataMode.standard,
    this.detectedEmotion,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    VoiceStatus? status,
    bool? isConnected,
    bool? isMicMuted,
    String? currentToolName,
    String? errorMessage,
    String? liveTranscript,
    LiveTranscriptOwner? liveOwner,
    double? audioLevel,
    bool? needsPermissionSettings,
    bool? isLiveMode,
    VisionMode? visionMode,
    bool? visionNeedsSettings,
    int? visionFramesSent,
    int? visionFramesFailed,
    VisionDataMode? visionDataMode,
    bool? screenShareOn,
    int? screenFramesSent,
    int? screenFramesFailed,
    ScreenShareDataMode? screenShareDataMode,
    String? detectedEmotion,
    bool clearEmotion = false,
    bool clearError = false,
    bool clearTool = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      status: status ?? this.status,
      isConnected: isConnected ?? this.isConnected,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      currentToolName: clearTool ? null : (currentToolName ?? this.currentToolName),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      liveTranscript: liveTranscript ?? this.liveTranscript,
      liveOwner: liveOwner ?? this.liveOwner,
      audioLevel: audioLevel ?? this.audioLevel,
      needsPermissionSettings: needsPermissionSettings ?? this.needsPermissionSettings,
      isLiveMode: isLiveMode ?? this.isLiveMode,
      visionMode: visionMode ?? this.visionMode,
      visionNeedsSettings: visionNeedsSettings ?? this.visionNeedsSettings,
      visionFramesSent: visionFramesSent ?? this.visionFramesSent,
      visionFramesFailed: visionFramesFailed ?? this.visionFramesFailed,
      visionDataMode: visionDataMode ?? this.visionDataMode,
      screenShareOn: screenShareOn ?? this.screenShareOn,
      screenFramesSent: screenFramesSent ?? this.screenFramesSent,
      screenFramesFailed: screenFramesFailed ?? this.screenFramesFailed,
      screenShareDataMode: screenShareDataMode ?? this.screenShareDataMode,
      detectedEmotion: clearEmotion ? null : (detectedEmotion ?? this.detectedEmotion),
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ChatNotifier extends StateNotifier<ChatState> {
  // The active live-conversation backend. Despite the historical name, this is
  // a [VoiceBackend]: either Gemini Live in the cloud or the on-device
  // EdgeBrain hub (NPU), chosen by BrainMode in Settings. Keeping it as one
  // field means every call site (audio, text, tools, mute, vision) stays
  // backend agnostic, and the robot + emotion layers never notice the swap.
  VoiceBackend _gemini = _buildBackend();
  BrainMode _brainMode = AiEnginePrefs.brainMode();
  final AudioRecorderService _recorder = AudioRecorderService.instance;
  final AudioPlaybackService _playback = AudioPlaybackService.instance;
  final ToolDispatcher _dispatcher = ToolDispatcher.instance;
  final VisionService _vision = VisionService.instance;
  final Ref _ref;

  // TTS for REST mode (audio fallback)
  FlutterTts? _tts;
  bool _ttsInitialized = false;

  // Live mode transcription buffers
  String _aiTranscript = '';
  String _userTranscript = '';

  // REST mode text assembly (no transcripts, just streamed text)
  String _assemblingText = '';

  StreamSubscription<Map<String, dynamic>>? _geminiSub;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<double>? _outputLevelSub;
  StreamSubscription<void>? _playbackIdleSub;

  // Safety net: if we enter "speaking" but the server never sends turnComplete
  // (e.g. a mid-turn glitch), status would stay stuck on speaking and the echo
  // guard would suppress the mic forever. This watchdog forces us back to idle
  // after a long silence. It's reset on every AI audio chunk / transcript, so
  // it only fires on a genuine hang, never during a normal (even long) reply.
  Timer? _speakingWatchdog;
  static const _speakingWatchdogTimeout = Duration(seconds: 12);

  String _uniqueId() => DateTime.now().microsecondsSinceEpoch.toString();

  /// Build the voice backend for the current BrainMode. Cloud is the default
  /// so the proven Gemini path is unchanged unless the user opts into edge.
  static VoiceBackend _buildBackend() {
    return AiEnginePrefs.brainMode() == BrainMode.edge
        ? EdgeBrainService(wsUrl: AiEnginePrefs.edgeBrainWsUrl())
        : GeminiVoiceService();
  }

  /// If the user flipped Cloud/Edge in Settings, swap the backend before the
  /// next session opens. Only ever runs while powered off, so it cannot yank a
  /// live socket out from under a conversation.
  void _syncBackendToPrefs() {
    final want = AiEnginePrefs.brainMode();
    if (want == _brainMode) return;
    _log('Switching voice backend: ${_brainMode.name} -> ${want.name}');
    try {
      _gemini.dispose();
    } catch (_) {}
    _gemini = _buildBackend();
    _brainMode = want;
  }

  ChatNotifier(this._ref) : super(const ChatState()) {
    _initTts();
    _wireDispatcher();
    _loadHistory();
    _loadVisionPrefs();
    _levelSub = _recorder.audioLevelStream.listen((level) {
      // Mic level is intentionally NOT routed to the orb's audioLevel.
      // The sphere should only react to Brutus's voice (output level).
      // We keep the subscription alive so the recorder continues producing
      // a level signal (used internally by the recorder service for AGC etc.),
      // but we don't write it into chat state.
      // This prevents the sphere from "exploding" while the user is speaking.
    });
    _outputLevelSub = _playback.outputLevelStream.listen((level) {
      if (!mounted) return;
      // Only Brutus's output drives the sphere.
      state = state.copyWith(audioLevel: level);
    });
    // Re-anchor the echo suppression guard to when playback actually goes
    // idle (600ms after last chunk). The native AudioTrack has a 2-second
    // buffer, so audio keeps playing after the last chunk is received. Without
    // this re-anchor the 2.5s guard could expire while the buffer is still
    // draining, letting Brutus's voice leak back into the mic.
    _playbackIdleSub = _playback.onIdleStream.listen((_) {
      _lastAiAudioAt = DateTime.now();
      _log('Echo guard re-anchored to playback idle');
      // Brutus's reply has finished playing — reopen the mic (with a short
      // tail so the speaker's audio tail doesn't leak back in) so it can
      // listen for the next turn.
      if (_turnCompleteAwaitingDrain) {
        _turnCompleteAwaitingDrain = false;
        _endAiTurn(delay: const Duration(milliseconds: 700));
      }
    });
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  static const _historyBoxName = 'chat_history';
  static const _historyKey = 'messages';
  static const _prefsBoxName = 'preferences';
  static const _visionDataModeKey = 'brutus_vision_data_mode';
  // Cap stored history to keep Hive disk + memory footprint sensible.
  static const _maxStoredMessages = 200;

  Timer? _persistDebounce;

  void _loadHistory() {
    try {
      final box = Hive.box(_historyBoxName);
      final raw = box.get(_historyKey) as List<dynamic>?;
      if (raw == null || raw.isEmpty) return;
      final loaded = raw
          .map((e) => ChatMessage.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      state = state.copyWith(messages: loaded);
      _log('Loaded ${loaded.length} message(s) from history');
    } catch (e) {
      _log('History load failed: $e');
    }
  }

  /// Debounced persistence — coalesces rapid message bursts (e.g. tool call
  /// + AI reply) into one write so we don't thrash Hive.
  void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 400), () {
      try {
        final box = Hive.box(_historyBoxName);
        final toStore = state.messages.length > _maxStoredMessages
            ? state.messages.sublist(state.messages.length - _maxStoredMessages)
            : state.messages;
        box.put(_historyKey, toStore.map((m) => m.toMap()).toList());
      } catch (e) {
        _log('History persist failed: $e');
      }
    });
  }

  void _loadVisionPrefs() {
    try {
      final box = Hive.box(_prefsBoxName);
      final raw = box.get(_visionDataModeKey) as String?;
      final mode = raw == 'low'
          ? VisionDataMode.low
          : VisionDataMode.standard;
      state = state.copyWith(visionDataMode: mode);
    } catch (e) {
      _log('Vision prefs load failed: $e');
    }
  }

  void _persistVisionDataMode(VisionDataMode mode) {
    try {
      Hive.box(_prefsBoxName).put(
        _visionDataModeKey,
        mode == VisionDataMode.low ? 'low' : 'standard',
      );
    } catch (e) {
      _log('Vision prefs persist failed: $e');
    }
  }

  void _log(String msg) => dev.log('[Chat] $msg', name: 'BrutusAI');

  void _wireDispatcher() {
    _dispatcher.registerNoteCreator((title, content) async {
      try {
        await _ref.read(notesProvider.notifier).createNote(
              title: title,
              content: content,
            );
        return {'success': true, 'title': title, 'message': 'Note saved successfully.'};
      } catch (e) {
        return {'success': false, 'error': '$e'};
      }
    });
    _dispatcher.registerNoteReader(() async {
      final notes = _ref.read(notesProvider);
      return notes
          .map((n) => {
                'id': n.id,
                'title': n.title,
                'content': n.content,
                'updatedAt': n.updatedAt.toIso8601String(),
              })
          .toList();
    });
    _dispatcher.registerDeepResearchRunner((query) async {
      return _ref.read(deepResearchProvider.notifier).runForTool(query);
    });
    _dispatcher.registerOracleRunner((question) async {
      return _ref.read(ragOracleProvider.notifier).runForTool(question);
    });
    _dispatcher.registerReadEmailsRunner(({int max = 5}) async {
      return _ref.read(emailProvider.notifier).runReadEmailsForTool(max: max);
    });
    _dispatcher.registerSendEmailRunner(
      ({required String to, required String subject, required String body}) async {
        return _ref.read(emailProvider.notifier).runSendEmailForTool(
              to: to,
              subject: subject,
              body: body,
            );
      },
    );
    _dispatcher.registerGenerateImageRunner((prompt) async {
      return _ref.read(galleryProvider.notifier).runForTool(prompt);
    });
    _dispatcher.registerFindPlaceRunner((query) async {
      return _ref.read(mapsProvider.notifier).runForTool(query);
    });

    // ── Phase 4: Phone Automation runners ─────────────────────────────
    _dispatcher.registerOpenAppRunner((name) async {
      return _ref.read(automationProvider.notifier).runOpenApp(name);
    });
    _dispatcher.registerToggleFlashlightRunner((on) async {
      return _ref.read(automationProvider.notifier).runFlashlight(on);
    });
    _dispatcher.registerOpenSettingsPanelRunner((panel) async {
      return _ref.read(automationProvider.notifier).runOpenSettingsPanel(panel);
    });
    _dispatcher.registerSetRingerModeRunner((mode) async {
      return _ref.read(automationProvider.notifier).runRingerMode(mode);
    });
    _dispatcher.registerSendWhatsAppRunner(
      ({required String phone, required String message}) async {
        return _ref
            .read(automationProvider.notifier)
            .runWhatsApp(phone: phone, message: message);
      },
    );
    _dispatcher.registerPlaySpotifyRunner((query) async {
      return _ref.read(automationProvider.notifier).runSpotify(query);
    });
    _dispatcher.registerReadNotificationsRunner(() async {
      return _ref.read(automationProvider.notifier).runReadNotifications();
    });
    _dispatcher.registerGhostTypeRunner((text) async {
      return _ref.read(automationProvider.notifier).runGhostType(text);
    });
    _dispatcher.registerClickByTextRunner((query) async {
      return _ref.read(automationProvider.notifier).runClickByText(query);
    });
    _dispatcher.registerReadScreenTextRunner(() async {
      return _ref.read(automationProvider.notifier).runReadScreen();
    });
    _dispatcher.registerOcrRunner(() async {
      return _ref.read(automationProvider.notifier).runOcr();
    });
    _dispatcher.registerGlobalActionRunner((action) async {
      return _ref.read(automationProvider.notifier).runGlobalAction(action);
    });
    _dispatcher.registerSendSmsRunner(
      ({required String to, required String body}) async {
        return _ref.read(automationProvider.notifier).runSendSms(
              to: to,
              body: body,
            );
      },
    );
    _dispatcher.registerCallRunner((to) async {
      return _ref.read(automationProvider.notifier).runCall(to);
    });
    _dispatcher.registerFindContactRunner((name) async {
      return _ref.read(automationProvider.notifier).runFindContact(name);
    });
    _dispatcher.registerSetTimerRunner((minutes) async {
      return _ref.read(automationProvider.notifier).runSetTimer(minutes);
    });

    // ── Phase 5: Robot animation / trick runners ─────────────────────
    _dispatcher.registerPlayAnimationRunner((index) async {
      try {
        await _ref.read(robotProvider.notifier).playAnimation(index);
        final name = (index >= 0 && index < RobotAnimation.labels.length)
            ? RobotAnimation.labels[index]
            : 'Animation $index';
        return {'success': true, 'message': 'Playing animation: $name'};
      } catch (e) {
        return {'success': false, 'error': '$e'};
      }
    });
    _dispatcher.registerPlayMovementTrickRunner((index) async {
      try {
        await _ref.read(robotProvider.notifier).playMovementTrick(index);
        final name = (index >= 0 && index < RobotMovementTrick.labels.length)
            ? RobotMovementTrick.labels[index]
            : 'Trick $index';
        return {'success': true, 'message': 'Playing movement trick: $name'};
      } catch (e) {
        return {'success': false, 'error': '$e'};
      }
    });

    // Eagerly warm up the providers that have async initialisation work
    // (Gmail silent restore, RAG library load, notification listener
    // subscription). Riverpod creates notifiers lazily on first .read;
    // without this, the first voice tool that hits these providers races
    // with their _initialise() Future and fails.
    _ref.read(emailProvider.notifier);
    _ref.read(ragOracleProvider.notifier);
    _ref.read(galleryProvider.notifier);
    _ref.read(automationProvider.notifier);
  }

  // ── TTS (REST fallback) ────────────────────────────────────────────────────

  Future<void> _initTts() async {
    try {
      _tts = FlutterTts();
      await _tts!.setLanguage('en-US');
      await _tts!.setSpeechRate(0.5);
      await _tts!.setPitch(1.0);
      await _tts!.setVolume(1.0);
      // On Android, route TTS as a media-style stream so it plays through the
      // loudspeaker. (REST fallback uses TTS; Live mode uses native audio
      // and never hits this path.)
      try {
        await _tts!.setQueueMode(0); // QUEUE_FLUSH
      } catch (_) {}

      _tts!.setStartHandler(() {
        if (mounted) {
          state = state.copyWith(status: VoiceStatus.speaking);
        }
      });
      _tts!.setCompletionHandler(() {
        if (mounted && state.status == VoiceStatus.speaking) {
          state = state.copyWith(status: VoiceStatus.idle);
        }
      });

      _ttsInitialized = true;
      _log('TTS initialized');
    } catch (e) {
      _log('TTS init failed: $e');
      _ttsInitialized = false;
    }
  }

  Future<void> _speak(String text) async {
    if (!_ttsInitialized || _tts == null || text.trim().isEmpty) return;
    try {
      // Strip markdown/special chars that TTS engines stumble on
      final cleanText = text
          .replaceAll(RegExp(r'\*\*'), '')
          .replaceAll(RegExp(r'[*_`#>]'), '')
          .trim();
      if (cleanText.isEmpty) return;
      await _tts!.speak(cleanText);
    } catch (e) {
      _log('TTS speak error: $e');
    }
  }

  /// Speak arbitrary [text] aloud in [lang] (e.g. 'en-US', 'hi-IN').
  ///
  /// Used by the "Speak for me" feature in the chat input bar.
  ///
  /// The engine is picked by the user in Settings → AI Providers
  /// ([AiEnginePrefs.ttsEngine]):
  ///   • **Gemini** — Live native-audio in Puck/Aoede voice. Returns 24 kHz
  ///     mono PCM piped through the native AudioTrack, so it sounds *exactly*
  ///     like Brutus during a live conversation.
  ///   • **Sarvam** — Bulbul Indic voices. We fetch the clip, resample it to
  ///     24 kHz mono PCM, and push it through the same AudioTrack pipeline.
  ///   • **System** — flutter_tts (Android system TTS). Offline, robotic.
  ///
  /// Gemini and Sarvam both fall back to system TTS if their network call
  /// fails (no network, quota, empty response).
  ///
  /// While Brutus is speaking, we **mute the live mic** so the playback audio
  /// can't leak back into the running Gemini Live session and trigger an
  /// unwanted reply. The mic resumes once playback has fully drained.
  Future<void> speakText(String text, {String lang = 'en-US'}) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    final engine = AiEnginePrefs.ttsEngine();

    // Stop any in-flight system-TTS fallback (flutter_tts) — fine, doesn't
    // touch our native AudioTrack.
    await _stopSpeaking();

    // Force a fresh AudioTrack for the TTS turn (Gemini + Sarvam use it).
    //
    // On Flutter hot restart, Dart's `_started` flag resets but the Kotlin
    // PcmStreamPlayer keeps the previous AudioTrack object — and the
    // underlying IAudioTrack binder is dead (its Dart owner is gone). The
    // next `write` call hits `restoreTrack_l: dead IAudioTrack` and silently
    // drops the first burst of audio. For a 6-chunk TTS clip that's the
    // entire payload, so the user hears nothing.
    //
    // [release()] now always invokes the native 'stop' method (even if Dart
    // thinks the track isn't started), so calling it here is the cheapest
    // way to guarantee we write into a fresh, healthy track. The next
    // `queueChunk` will lazily call `start` and create a new AudioTrack.
    try {
      await _playback.release();
    } catch (_) {}

    // Snapshot mic state and mute it for the duration of this TTS turn so
    // the running Live WebSocket doesn't hear Brutus's own voice through
    // the speaker and treat it as a fresh user turn.
    final wasMicLive = state.isConnected && !state.isMicMuted;
    if (wasMicLive) {
      _gemini.setMute(true);
    }

    if (mounted) {
      state = state.copyWith(
        status: VoiceStatus.speaking,
        isMicMuted: wasMicLive ? true : state.isMicMuted,
        clearError: true,
      );
    }

    // Cancel any prior pending resume from an earlier Speak-for-me call.
    _speakResumeSub?.cancel();
    _speakResumeSub = null;
    _speakResumeFallback?.cancel();
    _speakResumeFallback = null;

    // ── Gemini ────────────────────────────────────────────────────────────
    if (engine == TtsEngine.gemini) {
      // Subscribe to playback-idle BEFORE kicking off the WS so we don't
      // miss the event for super-short clips. We only resume the mic on
      // the FIRST idle event after this point, then unsubscribe.
      if (wasMicLive) {
        _speakResumeSub = _playback.onIdleStream.listen((_) {
          _speakResumeSub?.cancel();
          _speakResumeSub = null;
          // Add a small safety drain after the idle signal — the
          // AudioTrack ring buffer may still have a tail playing.
          Timer(const Duration(milliseconds: 800), _doMicResume);
        });
        // Hard fallback if idle never fires.
        _speakResumeFallback = Timer(const Duration(seconds: 15), _doMicResume);
      }

      // Try Gemini's native voice — give it up to 2 attempts because the Live
      // socket occasionally returns 0 chunks on the first call after a recent
      // session.
      var ok = await GeminiTtsService.instance.speak(clean, lang: lang);
      if (!ok) {
        _log('Speak-for-me: first attempt returned no audio, retrying once...');
        ok = await GeminiTtsService.instance.speak(clean, lang: lang);
      }
      if (ok) {
        _log('Speak-for-me: Gemini TTS ($lang, ${clean.length} chars) — '
            'waiting for playback drain to unmute mic');
        // The onIdleStream subscription set up above handles mic resume once
        // the AudioTrack actually finishes playing.
        return;
      }
      // Gemini produced nothing — drop the idle waiter and fall through to the
      // system-TTS fallback below.
      _speakResumeSub?.cancel();
      _speakResumeSub = null;
      _speakResumeFallback?.cancel();
      _speakResumeFallback = null;
    }

    // ── Sarvam (Bulbul) ─────────────────────────────────────────────────────
    else if (engine == TtsEngine.sarvam) {
      final ok = await _speakSarvam(clean, lang: lang);
      if (ok) {
        _log('Speak-for-me: Sarvam Bulbul TTS ($lang, ${clean.length} chars)');
        return;
      }
      // Fall through to system-TTS fallback below.
    }

    // ── System TTS (chosen engine, or Gemini/Sarvam fallback) ───────────────
    if (!_ttsInitialized || _tts == null) {
      _scheduleMicResume(wasMicLive);
      return;
    }
    try {
      await _tts!.stop();
      await _tts!.setLanguage(lang);
      await _tts!.setSpeechRate(lang.startsWith('hi') ? 0.45 : 0.5);
      await _tts!.speak(clean);
      _log('Speak-for-me: system TTS ($lang)');
    } catch (e) {
      _log('speakText fallback error: $e');
      if (mounted) {
        state = state.copyWith(status: VoiceStatus.idle);
      }
    }
    _scheduleMicResume(wasMicLive);
  }

  /// Synthesize [text] with Sarvam Bulbul and pipe the resulting 24 kHz mono
  /// PCM through the native AudioTrack (the same pipeline Gemini uses). Returns
  /// true if audio was produced and queued.
  ///
  /// Unlike Gemini (whose chunks arrive paced over a WebSocket), Sarvam returns
  /// the whole clip at once. We compute the true playback duration from the PCM
  /// length and schedule the mic-resume off that, rather than the 600ms idle
  /// timer — which would fire long before a multi-second clip finishes and
  /// unmute the mic straight into Brutus's own voice.
  Future<bool> _speakSarvam(String text, {required String lang}) async {
    try {
      final voice = AiEnginePrefs.sarvamVoice();
      // Hindi input forces hi-IN; otherwise honour the saved Sarvam language.
      final langCode =
          lang.startsWith('hi') ? 'hi-IN' : AiEnginePrefs.sarvamLanguage();

      final pcm = await SarvamClient().synthesizeToPcm24k(
        text: text,
        speaker: voice,
        languageCode: langCode,
      );
      if (pcm.isEmpty) return false;

      // 24 kHz mono 16-bit → 48000 bytes/sec. Feed in ~200ms slices so the
      // level meter animates and the AudioTrack ring buffer stays fed.
      const bytesPerSec = 24000 * 2;
      const chunkBytes = bytesPerSec ~/ 5;
      final start = DateTime.now();
      for (int i = 0; i < pcm.length; i += chunkBytes) {
        final end = (i + chunkBytes < pcm.length) ? i + chunkBytes : pcm.length;
        await _playback.queueChunk(
          base64Encode(Uint8List.sublistView(pcm, i, end)),
        );
      }

      // Schedule mic resume / status reset once the audio has actually played
      // out. If the native `write` blocked (paced by playback) the loop
      // already consumed ~duration, so subtract elapsed to avoid waiting
      // twice; if it didn't block, elapsed≈0 and we wait the full duration.
      final durationMs = (pcm.length * 1000) ~/ bytesPerSec;
      final elapsedMs = DateTime.now().difference(start).inMilliseconds;
      var remainingMs = durationMs - elapsedMs;
      if (remainingMs < 0) remainingMs = 0;
      _scheduleMicResumeAfter(Duration(milliseconds: remainingMs + 800));
      return true;
    } on SarvamException catch (e) {
      _log('Sarvam TTS failed: $e');
      return false;
    } catch (e) {
      _log('Sarvam TTS error: $e');
      return false;
    }
  }

  /// Resume the live mic AFTER playback is fully drained.
  StreamSubscription<void>? _speakResumeSub;
  Timer? _speakResumeFallback;

  void _doMicResume() {
    _speakResumeFallback?.cancel();
    _speakResumeFallback = null;
    _speakResumeSub?.cancel();
    _speakResumeSub = null;
    if (!mounted) return;
    if (state.isConnected && state.isMicMuted) {
      _gemini.setMute(false);
      if (mounted) {
        state = state.copyWith(isMicMuted: false, status: VoiceStatus.idle);
      }
      _log('Speak-for-me: mic resumed after playback drained');
    } else if (state.status == VoiceStatus.speaking) {
      state = state.copyWith(status: VoiceStatus.idle);
    }
  }

  /// Fallback resume used when Gemini TTS fails entirely and we drop to
  /// flutter_tts. The system TTS plays through its own audio pipeline so
  /// we just use a fixed delay.
  void _scheduleMicResume(bool wasMicLive) {
    if (!wasMicLive) return;
    _speakResumeSub?.cancel();
    _speakResumeSub = null;
    _speakResumeFallback?.cancel();
    _speakResumeFallback = Timer(const Duration(milliseconds: 2500), () {
      _doMicResume();
    });
  }

  /// Resume the mic (and/or reset the "speaking" status) after a known [delay].
  /// Used by the Sarvam path, where the exact playback duration is computed
  /// up-front from the PCM length — a more accurate anchor than the 600ms
  /// idle-timer proxy the Gemini path leans on. Unlike [_scheduleMicResume]
  /// this always fires (even when the mic wasn't live) so a standalone
  /// "Speak for me" still transitions the status back to idle.
  void _scheduleMicResumeAfter(Duration delay) {
    _speakResumeSub?.cancel();
    _speakResumeSub = null;
    _speakResumeFallback?.cancel();
    _speakResumeFallback = Timer(delay, _doMicResume);
  }

  Future<void> _stopSpeaking() async {
    if (_ttsInitialized && _tts != null) {
      try {
        await _tts!.stop();
      } catch (_) {}
    }
  }

  // ── System power & mic ─────────────────────────────────────────────────────

  /// Full system power on: connect WebSocket, start continuous mic streaming.
  /// Mirrors desktop `toggleSystem()` when going from off → on.
  Future<void> powerOn() async {
    if (state.isConnected) return;
    if (state.status == VoiceStatus.connecting) return;

    // Honour a Cloud/Edge switch made in Settings since the last session.
    _syncBackendToPrefs();

    state = state.copyWith(
      status: VoiceStatus.connecting,
      clearError: true,
    );
    _log('System POWER ON — connecting...');

    try {
      _listenToGemini();
      await _gemini.connect();
    } catch (e) {
      _log('Connection failed: $e');
      state = state.copyWith(
        status: VoiceStatus.error,
        errorMessage: 'Connection failed: $e',
      );
      return;
    }

    // Connection didn't surface (e.g. no API key) — bail with the error already
    // pushed onto the message stream by the service.
    if (!_gemini.isConnected) {
      state = state.copyWith(status: VoiceStatus.error);
      return;
    }

    // Default mute state on system power-on: unmuted, like the desktop reference.
    _gemini.setMute(false);

    state = state.copyWith(
      isConnected: true,
      isMicMuted: false,
      status: VoiceStatus.idle,
      isLiveMode: _gemini.isLiveMode,
    );
    _log('System ON — Live mode: ${_gemini.isLiveMode}');

    if (state.isLiveMode) {
      await _startContinuousMic();
    } else {
      _log('REST mode — mic is text-only, talk via the keyboard.');
    }
  }

  /// Full system power off: stop mic, drop WebSocket, clear playback.
  Future<void> powerOff() async {
    _log('System POWER OFF');
    _cancelSpeakingWatchdog();
    _resetAiTurn();
    _geminiSub?.cancel();
    _geminiSub = null;
    await _recorder.stopStreaming();
    await _vision.stop();
    if (state.screenShareOn) {
      await ScreenShareService.instance.stop();
    }
    _gemini.disconnect();
    await _playback.release();
    await _stopSpeaking();
    state = state.copyWith(
      isConnected: false,
      isMicMuted: false,
      status: VoiceStatus.idle,
      audioLevel: 0.0,
      isLiveMode: false,
      liveTranscript: '',
      visionMode: VisionMode.off,
      visionFramesSent: 0,
      visionFramesFailed: 0,
      screenShareOn: false,
      screenFramesSent: 0,
      screenFramesFailed: 0,
    );
  }

  /// Toggle mute while system stays powered on.
  /// Like the desktop `toggleMic()` — flips the mute flag, doesn't stop the
  /// recorder. Audio continues to flow into the recorder; the service drops
  /// chunks while muted.
  void toggleMic() {
    if (!state.isConnected) return;
    final newMuted = !state.isMicMuted;
    _gemini.setMute(newMuted);
    state = state.copyWith(
      isMicMuted: newMuted,
      audioLevel: newMuted ? 0.0 : state.audioLevel,
    );
  }

  // ── Vision (camera frames → Gemini) ────────────────────────────────────────

  /// Stable callback identity passed to VisionService. Capturing
  /// `state` would mean restarts cache stale snapshots; this closure always
  /// reads the freshest state via `this.state`.
  void _onVisionFrame(String b64) {
    // Drop frames if the system has been turned off mid-flight.
    if (!state.isConnected) return;

    // ── Guard: skip frame while Brutus is speaking ──
    // Same protection the screen-share path has: a large JPEG mid-reply
    // competes with the audio stream on the WebSocket and can make Gemini
    // stutter or interrupt itself. Camera frames arrive every 2-4s, so
    // skipping a few during speech costs nothing.
    if (_playback.isPlaying || state.status == VoiceStatus.speaking) {
      return;
    }

    // ── Guard: skip frame while the user is mid-utterance ──
    // A frame landing between speech chunks can confuse Gemini's VAD.
    if (_recorder.audioLevel > 0.08) {
      return;
    }

    final ok = _gemini.sendVideoFrame(b64);
    if (ok) {
      state = state.copyWith(
        visionFramesSent: state.visionFramesSent + 1,
      );
    } else {
      state = state.copyWith(
        visionFramesFailed: state.visionFramesFailed + 1,
      );
    }
  }

  /// Feed an external camera frame (the ESP32-CAM "robot eyes") to Gemini,
  /// reusing the exact same guards as the phone-camera vision path (skip while
  /// speaking / while the user is talking / when the system is off).
  /// [base64Jpeg] is a base64-encoded JPEG. Safe to call at any rate — it's
  /// throttled upstream by the robot-eyes provider.
  void sendExternalVisionFrame(String base64Jpeg) {
    _onVisionFrame(base64Jpeg);
  }

  /// Start vision mode with the requested lens. The system must be powered on
  /// (Gemini WS connected); if not, this is a no-op that surfaces an error.
  Future<void> startVision({
    bool front = false,
    VisionDataMode? mode,
  }) async {
    if (!state.isConnected) {
      state = state.copyWith(
        errorMessage: 'Power on Brutus before enabling vision.',
      );
      return;
    }
    final lens =
        front ? CameraLensDirection.front : CameraLensDirection.back;
    final useMode = mode ?? state.visionDataMode;

    state = state.copyWith(
      visionMode: front ? VisionMode.frontCamera : VisionMode.backCamera,
      visionNeedsSettings: false,
      visionFramesSent: 0,
      visionFramesFailed: 0,
      visionDataMode: useMode,
      clearError: true,
    );

    // Persist whenever the user explicitly picks a mode at start time.
    if (mode != null) _persistVisionDataMode(useMode);

    final result = await _vision.start(
      lens: lens,
      mode: useMode,
      onFrame: _onVisionFrame,
    );

    if (result != VisionStartResult.started) {
      _log('Vision start failed: $result');
      state = state.copyWith(
        visionMode: VisionMode.off,
        visionNeedsSettings:
            result == VisionStartResult.permissionPermanentlyDenied,
        errorMessage: switch (result) {
          VisionStartResult.permissionDenied =>
            'Camera permission denied.',
          VisionStartResult.permissionPermanentlyDenied =>
            'Camera permanently denied. Tap Settings to grant access.',
          VisionStartResult.noCamera => 'No camera detected on this device.',
          VisionStartResult.failed => 'Could not open the camera.',
          VisionStartResult.disposed => null,
          VisionStartResult.started => null,
        },
      );
    }
  }

  Future<void> stopVision() async {
    await _vision.stop();
    state = state.copyWith(
      visionMode: VisionMode.off,
      visionFramesSent: 0,
      visionFramesFailed: 0,
    );
  }

  /// Flip between front/back camera while vision is running.
  Future<void> switchVisionLens() async {
    if (state.visionMode == VisionMode.off) return;
    final ok = await _vision.switchLens(_onVisionFrame);
    if (ok) {
      state = state.copyWith(
        visionMode: _vision.activeLens == CameraLensDirection.front
            ? VisionMode.frontCamera
            : VisionMode.backCamera,
      );
    }
  }

  /// Switch the bandwidth profile. If vision is currently running, the camera
  /// restarts in-place at the new resolution. Otherwise the choice is just
  /// remembered for the next vision session.
  Future<void> setVisionDataMode(VisionDataMode mode) async {
    if (state.visionDataMode == mode &&
        _vision.activeMode == mode) {
      return;
    }
    _persistVisionDataMode(mode);
    state = state.copyWith(visionDataMode: mode);
    if (state.visionMode == VisionMode.off) return;
    final ok = await _vision.switchMode(mode, _onVisionFrame);
    if (!ok) {
      _log('Vision mode switch failed — vision stopped or busy.');
    }
  }

  void openVisionPermissionSettings() {
    _vision.openSettings();
  }

  // ── Screen share ──────────────────────────────────────────────────────

  StreamSubscription<ScreenShareFrame>? _screenFrameSub;
  StreamSubscription<ScreenShareEvent>? _screenEventSub;

  /// Timestamp of the last screen frame successfully sent to Gemini.
  /// Used to enforce a minimum cooldown between frames so audio chunks
  /// get uncontested access to the WebSocket between image sends.
  DateTime _lastScreenFrameSent = DateTime(2000);

  /// Minimum gap between screen frame sends. Even if the native capture
  /// service delivers faster, we hold frames to let audio breathe.
  static const _screenFrameCooldown = Duration(seconds: 4);

  /// Reconcile state with the native foreground service. Call on app resume —
  /// if the service is still running (e.g. app was killed and reopened) we
  /// flip our state back to "on" so the panel shows. If consent was revoked
  /// while the app was dead, we'll receive the `onScreenCaptureStopped` event
  /// once the channel handler is wired again.
  Future<void> reconcileScreenShare() async {
    if (!mounted) return;
    final running = await ScreenShareService.instance.queryRunning();
    if (running == state.screenShareOn) return;

    if (!running) {
      // Service stopped while we were away. Reset counters.
      state = state.copyWith(
        screenShareOn: false,
        screenFramesSent: 0,
        screenFramesFailed: 0,
      );
      return;
    }

    // Native service is running but our state says off. If Brutus is
    // disconnected (WebSocket dead), every captured frame is wasted —
    // just stop the foreground service. Otherwise flip the UI on so the
    // panel reflects reality.
    if (!state.isConnected) {
      _log('reconcile: service running but Brutus offline — stopping');
      await ScreenShareService.instance.stop();
      state = state.copyWith(
        screenShareOn: false,
        screenFramesSent: 0,
        screenFramesFailed: 0,
      );
    } else {
      state = state.copyWith(screenShareOn: true);
    }
  }

  /// Start sharing the device screen with Gemini. Pops the system
  /// MediaProjection consent dialog on first call. Frames stream up to
  /// Gemini at the cadence of [mode] (or whatever's persisted).
  Future<ScreenShareStartResult> startScreenShare({
    ScreenShareDataMode? mode,
  }) async {
    if (state.screenShareOn) return ScreenShareStartResult.started;
    if (!state.isConnected) {
      state = state.copyWith(
        errorMessage: 'Power on Brutus before sharing your screen.',
      );
      return ScreenShareStartResult.failed;
    }
    final useMode = mode ?? state.screenShareDataMode;

    // Ensure the channel handler is installed before we ask the system
    // for capture consent. Reading the automation provider triggers
    // PhoneAutomationService's constructor (idempotent — singleton).
    _ref.read(automationProvider.notifier);

    // Wire the frame + event streams once, the first time we start.
    _screenFrameSub ??= ScreenShareService.instance.frames.listen((f) {
      if (!mounted) return;
      if (!state.isConnected) return;

      // ── Guard: skip frame while Brutus is speaking ──
      // Sending a large JPEG mid-reply competes with audio output and can
      // cause Gemini to interrupt itself or stall the session.
      if (_playback.isPlaying || state.status == VoiceStatus.speaking) {
        _log('Screen frame skipped — Brutus is speaking');
        return;
      }

      // ── Guard: skip frame while user is actively speaking ──
      // If the mic level is above a threshold, the user is mid-utterance.
      // Sending a frame now would confuse Gemini's VAD — it might think
      // the user is still providing input and never trigger a response.
      if (_recorder.audioLevel > 0.08) {
        _log('Screen frame skipped — user speaking (level=${_recorder.audioLevel.toStringAsFixed(2)})');
        return;
      }

      // ── Guard: cooldown between frames ──
      // Enforce a minimum gap so audio chunks flow uncontested between
      // image sends. Without this, back-to-back frames starve the VAD.
      final now = DateTime.now();
      if (now.difference(_lastScreenFrameSent) < _screenFrameCooldown) {
        return;
      }

      final ok = _gemini.sendVideoFrame(f.base64Jpeg);
      if (ok) {
        _lastScreenFrameSent = now;
        state = state.copyWith(
          screenFramesSent: state.screenFramesSent + 1,
        );
      } else {
        state = state.copyWith(
          screenFramesFailed: state.screenFramesFailed + 1,
        );
      }
    });
    _screenEventSub ??= ScreenShareService.instance.events.listen((event) {
      if (!mounted) return;
      // Native side stopped (user revoked consent / system killed).
      if (!event.started) {
        state = state.copyWith(
          screenShareOn: false,
        );
      }
    });

    final result = await ScreenShareService.instance.start(mode: useMode);
    if (result == ScreenShareStartResult.started) {
      state = state.copyWith(
        screenShareOn: true,
        screenShareDataMode: useMode,
        screenFramesSent: 0,
        screenFramesFailed: 0,
        clearError: true,
      );
    } else {
      final msg = switch (result) {
        ScreenShareStartResult.denied => 'Screen-sharing consent denied.',
        ScreenShareStartResult.busy =>
          'Screen-sharing consent dialog is already up.',
        ScreenShareStartResult.failed =>
          'Could not start screen sharing — try again.',
        ScreenShareStartResult.started => null,
      };
      if (msg != null) state = state.copyWith(errorMessage: msg);
    }
    return result;
  }

  Future<void> stopScreenShare() async {
    await ScreenShareService.instance.stop();
    state = state.copyWith(
      screenShareOn: false,
      screenFramesSent: 0,
      screenFramesFailed: 0,
    );
  }

  Future<void> setScreenShareDataMode(ScreenShareDataMode mode) async {
    if (mode == state.screenShareDataMode &&
        ScreenShareService.instance.activeMode == mode) {
      return;
    }
    state = state.copyWith(screenShareDataMode: mode);
    if (!state.screenShareOn) return;
    final ok = await ScreenShareService.instance.setMode(mode);
    if (!ok) {
      // Mode switch failed (consent denied on re-prompt). Stop sharing
      // so the UI reflects reality.
      state = state.copyWith(
        screenShareOn: false,
        screenFramesSent: 0,
        screenFramesFailed: 0,
      );
    }
  }

  /// Timestamp of the last audio chunk Gemini sent (queued to playback).
  /// This is the most reliable echo-suppression anchor because it tracks
  /// the actual SOURCE event, not a timer-derived playback state that can
  /// flicker between audio bursts.
  DateTime _lastAiAudioAt = DateTime(2000);

  /// Residual echo cover applied AFTER playback truly ends. Now that
  /// AudioPlaybackService fires its idle event at real audio end (not when the
  /// last chunk arrived) and [_aiTurnActive] hard-gates the mic for the whole
  /// reply, this only needs to cover the room reverb tail — 1.5s is plenty for
  /// a phone speaker. (It used to be 2.5s to paper over the premature-idle bug
  /// that let Brutus hear the tail of its own reply.)
  static const _echoGuardDuration = Duration(milliseconds: 1500);

  // ── Half-duplex turn-taking ────────────────────────────────────────────────
  // Brutus owns the conversation turn from the moment it starts thinking/
  // replying until its audio has fully drained. While it owns the turn the
  // mic is HARD-gated (every chunk dropped) — Brutus hears the user's full
  // utterance, replies to THAT turn, and only then listens again. This closes
  // the gap the time-based echo guard misses: the "thinking" phase before the
  // first audio chunk, and any pause longer than the guard window. Paired with
  // the server-side NO_INTERRUPTION setting so a stray sound can't derail a
  // reply.
  bool _aiTurnActive = false;
  bool _turnCompleteAwaitingDrain = false;
  Timer? _aiTurnEndTimer;

  /// Brutus is starting (or continuing) its turn — gate the mic.
  void _beginAiTurn() {
    _aiTurnEndTimer?.cancel();
    _aiTurnEndTimer = null;
    _turnCompleteAwaitingDrain = false;
    if (_aiTurnActive) return;
    _aiTurnActive = true;
    _log('AI turn started — mic gated (half-duplex)');
  }

  /// Reopen the mic [delay] after the turn ends. The delay lets the AudioTrack
  /// ring buffer finish draining so the speaker tail doesn't leak straight back
  /// into the mic the instant we reopen.
  void _endAiTurn({Duration delay = const Duration(milliseconds: 500)}) {
    if (!_aiTurnActive && _aiTurnEndTimer == null) return;
    _turnCompleteAwaitingDrain = false;
    _aiTurnEndTimer?.cancel();
    _aiTurnEndTimer = Timer(delay, () {
      _aiTurnEndTimer = null;
      _aiTurnActive = false;
      _log('AI turn ended — mic live again');
    });
  }

  /// Immediately drop the turn gate (barge-in / power-off / disconnect).
  void _resetAiTurn() {
    _aiTurnEndTimer?.cancel();
    _aiTurnEndTimer = null;
    _turnCompleteAwaitingDrain = false;
    _aiTurnActive = false;
  }

  Future<void> _startContinuousMic() async {
    _log('Starting continuous mic stream...');
    _aiTranscript = '';
    _userTranscript = '';

    final result = await _recorder.startStreaming(
      onChunk: (base64Chunk) {
        // ── Echo suppression ──
        // Drop ALL mic audio while Brutus is speaking or recently spoke.
        // Without this, the speaker output leaks into the mic, Gemini
        // transcribes it as user speech, and responds to itself in an
        // infinite loop.
        //
        // We use _lastAiAudioAt (updated every time Gemini sends an audio
        // chunk) as the anchor. This is more reliable than checking
        // _playback.isPlaying which uses a 600ms idle timer that can
        // flicker between audio bursts.
        //
        // Suppression lasts 2.5s after the LAST AI audio chunk — enough
        // for speaker echo/reverb to fully dissipate. The mic stream
        // stays alive (no restart cost), and Gemini won't time out
        // because it knows it's the one speaking during this window.
        //
        // Primary gate: half-duplex turn-taking. While Brutus owns the turn
        // (thinking → replying → audio draining) we don't listen at all.
        if (_aiTurnActive) return;
        if (state.status == VoiceStatus.speaking) return;
        final sinceLastAiAudio = DateTime.now().difference(_lastAiAudioAt);
        if (sinceLastAiAudio < _echoGuardDuration) return;
        _gemini.sendAudioChunk(base64Chunk);
      },
    );

    if (result == RecordingStartResult.alreadyRecording) return;

    if (result != RecordingStartResult.started) {
      _log('Mic start failed: $result');
      state = state.copyWith(
        status: VoiceStatus.error,
        isMicMuted: true,
        errorMessage: result == RecordingStartResult.permissionDenied
            ? 'Microphone permission denied.'
            : result == RecordingStartResult.permissionPermanentlyDenied
                ? 'Microphone permanently denied. Tap Settings to grant access.'
                : 'Failed to start microphone.',
        needsPermissionSettings:
            result == RecordingStartResult.permissionPermanentlyDenied,
      );
      _gemini.setMute(true);
    }
  }

  void openPermissionSettings() {
    _recorder.openSettings();
  }

  // ── Text ───────────────────────────────────────────────────────────────────

  Future<void> sendText(String text) async {
    if (text.trim().isEmpty) return;
    _log('User text: $text');

    final msg = ChatMessage(
      id: _uniqueId(),
      text: text.trim(),
      role: MessageRole.user,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, msg],
      status: VoiceStatus.thinking,
      clearError: true,
    );
    _schedulePersist();

    if (!state.isConnected) {
      // Auto power-on so the user can chat without first hitting the power button.
      await powerOn();
    }

    if (state.isConnected) {
      _gemini.sendText(text.trim());
    } else {
      final errorMsg = ChatMessage(
        id: _uniqueId(),
        text: 'Failed to connect. Check your internet and Gemini API key, then try again.',
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(
        messages: [...state.messages, errorMsg],
        status: VoiceStatus.idle,
      );
      _schedulePersist();
    }
  }

  /// Inject a message that arrived from a paired desktop over the bridge.
  /// [id] is supplied by the bridge provider so it can tag it as remote and
  /// avoid echoing it straight back (loop-safe mirroring).
  void injectRemoteMessage({
    required MessageRole role,
    required String text,
    String? id,
  }) {
    if (text.trim().isEmpty) return;
    final msg = ChatMessage(
      id: id ?? _uniqueId(),
      text: text.trim(),
      role: role,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(messages: [...state.messages, msg]);
    _schedulePersist();
  }

  // ── Gemini event handler ───────────────────────────────────────────────────

  void _listenToGemini() {
    _geminiSub?.cancel();
    _geminiSub = _gemini.messages.listen((event) {
      if (!mounted) return;
      if (event.containsKey('setupComplete')) {
        state = state.copyWith(isConnected: true, status: VoiceStatus.idle);
        return;
      }

      // Live: input transcription (what the user said)
      if (event.containsKey('inputTranscription')) {
        final text = event['inputTranscription'] as String;
        _userTranscript += text;
        // While the user is speaking we show their transcript live
        state = state.copyWith(
          liveTranscript: _userTranscript,
          liveOwner: LiveTranscriptOwner.user,
        );
        return;
      }

      // Live: output transcription (what Brutus is saying)
      if (event.containsKey('outputTranscription')) {
        // Brutus has started its turn — gate the mic until the reply drains.
        _beginAiTurn();
        // The moment Brutus starts replying, commit the user's accumulated
        // transcript as a chat bubble so it appears BEFORE Brutus's response.
        _commitUserTranscriptIfPending();

        String text = event['outputTranscription'] as String;

        // Phase 4: Parse [EMOTION:xxx] tag from Gemini's response.
        // The tag appears at the start of the first transcription chunk.
        String? emotion;
        final tagPattern = RegExp(r'\[EMOTION:(\w+)\]\s*');
        if (_aiTranscript.isEmpty) {
          // First chunk — check for emotion tag
          final match = tagPattern.firstMatch(text);
          if (match != null) {
            emotion = match.group(1);
            text = text.replaceFirst(tagPattern, ''); // strip from display
          }
        }

        _aiTranscript += text;
        state = state.copyWith(
          status: VoiceStatus.speaking,
          liveTranscript: _aiTranscript,
          liveOwner: LiveTranscriptOwner.ai,
          detectedEmotion: emotion,
        );
        _kickSpeakingWatchdog();
        return;
      }

      final serverContent = event['serverContent'] as Map<String, dynamic>?;
      if (serverContent != null) {
        _handleServerContent(serverContent);
        return;
      }

      final toolCall = event['toolCall'] as Map<String, dynamic>?;
      if (toolCall != null) {
        _handleToolCall(toolCall);
        return;
      }

      // Transparent session recovery (connection/context limit, goAway, or a
      // transient drop). Keep the session "on" — the mic stream stays alive
      // and the service drops chunks until the socket returns — but show the
      // user we're re-establishing the link.
      if (event['type'] == 'reconnecting') {
        _cancelSpeakingWatchdog();
        if (state.isConnected) {
          state = state.copyWith(status: VoiceStatus.connecting);
        }
        return;
      }
      if (event['type'] == 'reconnected') {
        // Session resumed. Drop any half-finished turn buffers so the next
        // real turn doesn't append onto a stale partial transcript.
        _resetAiTurn();
        _aiTranscript = '';
        _userTranscript = '';
        _assemblingText = '';
        state = state.copyWith(
          isConnected: true,
          status: VoiceStatus.idle,
          liveTranscript: '',
          liveOwner: LiveTranscriptOwner.none,
          clearError: true,
        );
        return;
      }
      if (event['type'] == 'error') {
        state = state.copyWith(
          status: VoiceStatus.error,
          errorMessage: event['message'] as String?,
        );
        return;
      }
      if (event['type'] == 'disconnected') {
        // Only reached after the user powered off or reconnection was fully
        // exhausted. Tear the mic/vision/playback down so nothing keeps
        // streaming into a dead socket.
        _teardownAfterDisconnect();
        return;
      }
    });
  }

  /// Clean up the live pipeline after the connection is permanently lost
  /// (reconnection exhausted). Unlike [powerOff] it doesn't re-close the
  /// already-dead WebSocket, but it DOES stop the mic/vision/playback so
  /// nothing keeps streaming into a closed socket and the orb settles.
  void _teardownAfterDisconnect() {
    _cancelSpeakingWatchdog();
    _resetAiTurn();
    _recorder.stopStreaming();
    _vision.stop();
    _playback.release();
    if (state.screenShareOn) {
      ScreenShareService.instance.stop();
    }
    if (!mounted) return;
    state = state.copyWith(
      isConnected: false,
      isMicMuted: false,
      audioLevel: 0.0,
      // Preserve an error message set by the preceding 'error' event so the
      // user learns why the session ended.
      status: state.errorMessage != null ? VoiceStatus.error : VoiceStatus.idle,
      isLiveMode: false,
      liveTranscript: '',
      liveOwner: LiveTranscriptOwner.none,
      visionMode: VisionMode.off,
      visionFramesSent: 0,
      visionFramesFailed: 0,
      screenShareOn: false,
      screenFramesSent: 0,
      screenFramesFailed: 0,
    );
  }

  void _commitUserTranscriptIfPending() {
    final text = _userTranscript.trim();
    if (text.isEmpty) return;
    final userMsg = ChatMessage(
      id: _uniqueId(),
      text: text,
      role: MessageRole.user,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(messages: [...state.messages, userMsg]);
    _userTranscript = '';
    _schedulePersist();
  }

  /// (Re)arm the speaking watchdog. Called on every AI audio chunk / output
  /// transcript. If no further AI activity arrives within the timeout while
  /// still in the speaking state, we assume the turn silently stalled and
  /// recover to idle so the mic starts listening again.
  void _kickSpeakingWatchdog() {
    _speakingWatchdog?.cancel();
    _speakingWatchdog = Timer(_speakingWatchdogTimeout, () {
      if (!mounted) return;
      if (state.status != VoiceStatus.speaking) return; // already moved on
      _log('Speaking watchdog fired — no turnComplete; forcing idle');
      _resetAiTurn();
      // Preserve whatever Brutus managed to say as a committed message.
      final responseText =
          _aiTranscript.isNotEmpty ? _aiTranscript : _assemblingText;
      if (responseText.trim().isNotEmpty) {
        final aiMsg = ChatMessage(
          id: _uniqueId(),
          text: responseText.trim(),
          role: MessageRole.assistant,
          timestamp: DateTime.now(),
        );
        state = state.copyWith(messages: [...state.messages, aiMsg]);
        _schedulePersist();
      }
      _aiTranscript = '';
      _assemblingText = '';
      _userTranscript = '';
      state = state.copyWith(
        status: VoiceStatus.idle,
        liveTranscript: '',
        liveOwner: LiveTranscriptOwner.none,
      );
    });
  }

  void _cancelSpeakingWatchdog() {
    _speakingWatchdog?.cancel();
    _speakingWatchdog = null;
  }

  void _handleServerContent(Map<String, dynamic> serverContent) {
    // Barge-in: stop playback immediately and reset buffers
    if (serverContent['interrupted'] == true) {
      _cancelSpeakingWatchdog();
      _resetAiTurn();
      _playback.stop();
      _assemblingText = '';
      _aiTranscript = '';
      _userTranscript = '';
      state = state.copyWith(
        status: VoiceStatus.idle,
        liveTranscript: '',
        liveOwner: LiveTranscriptOwner.none,
      );
      return;
    }

    final modelTurn = serverContent['modelTurn'] as Map<String, dynamic>?;
    final turnComplete = serverContent['turnComplete'] as bool? ?? false;

    if (modelTurn != null) {
      final parts = (modelTurn['parts'] as List<dynamic>?) ?? [];
      for (final part in parts) {
        final partMap = part as Map<String, dynamic>;

        // Text response (REST mode primarily). Mark it as AI-owned so the
        // live bubble in chat shows it streaming.
        final text = partMap['text'] as String?;
        if (text != null && text.isNotEmpty) {
          _assemblingText += text;
          state = state.copyWith(
            status: VoiceStatus.thinking,
            liveTranscript: _assemblingText,
            liveOwner: LiveTranscriptOwner.ai,
          );
        }

        // Audio response — both 'inlineData' and 'inline_data' show up in
        // the wild. Accept either.
        final inlineData = (partMap['inlineData'] ?? partMap['inline_data'])
            as Map<String, dynamic>?;
        if (inlineData != null) {
          final audioData = inlineData['data'] as String?;
          if (audioData != null && audioData.isNotEmpty) {
            // First audio chunk → user has finished, commit their transcript
            // before Brutus's voice starts.
            _commitUserTranscriptIfPending();
            // Brutus is speaking — gate the mic for the rest of its turn.
            _beginAiTurn();
            // Update echo suppression anchor — onChunk uses this to
            // suppress mic audio for 2.5s after the last AI audio.
            _lastAiAudioAt = DateTime.now();
            _gemini.notifyAiAudioActive();
            _playback.queueChunk(audioData);
            state = state.copyWith(status: VoiceStatus.speaking);
            _kickSpeakingWatchdog();
          }
        }
      }
    }

    if (turnComplete) {
      _log('Turn complete.');
      _cancelSpeakingWatchdog();

      bool persistNeeded = false;

      // User transcript should already be committed (when Brutus started),
      // but if Gemini somehow turned-complete without ever speaking, flush it.
      if (_userTranscript.trim().isNotEmpty) {
        _commitUserTranscriptIfPending();
        persistNeeded = true;
      }

      // Persist AI response (prefer the live transcript, fall back to assembled text)
      final responseText =
          _aiTranscript.isNotEmpty ? _aiTranscript : _assemblingText;
      if (responseText.trim().isNotEmpty) {
        final aiMsg = ChatMessage(
          id: _uniqueId(),
          text: responseText.trim(),
          role: MessageRole.assistant,
          timestamp: DateTime.now(),
        );
        state = state.copyWith(
          messages: [...state.messages, aiMsg],
          liveTranscript: '',
          liveOwner: LiveTranscriptOwner.none,
          status: VoiceStatus.idle,
        );

        // REST mode has no native audio, so speak via local TTS
        if (!state.isLiveMode && _assemblingText.isNotEmpty) {
          _speak(_assemblingText.trim());
        }
        persistNeeded = true;
      } else {
        state = state.copyWith(
          status: VoiceStatus.idle,
          liveTranscript: '',
          liveOwner: LiveTranscriptOwner.none,
        );
      }

      _assemblingText = '';
      _aiTranscript = '';
      if (persistNeeded) _schedulePersist();

      // Half-duplex: hold the mic gated until Brutus's audio has fully drained,
      // then reopen it for the next turn. If there's no audio playing (text /
      // tool-only turn) reopen after a short grace period.
      if (_aiTurnActive) {
        if (_playback.isPlaying) {
          _turnCompleteAwaitingDrain = true; // onIdleStream reopens the mic
        } else {
          _endAiTurn();
        }
      }
    }
  }

  Future<void> _handleToolCall(Map<String, dynamic> toolCall) async {
    final functionCalls = (toolCall['functionCalls'] as List<dynamic>?) ?? [];
    for (final call in functionCalls) {
      final callMap = call as Map<String, dynamic>;
      final id = callMap['id'] as String? ?? callMap['name'] as String? ?? '';
      final name = callMap['name'] as String? ?? '';
      final args = (callMap['args'] as Map<String, dynamic>?) ?? const {};

      _log('Tool call: $name($args)');
      state = state.copyWith(currentToolName: name, status: VoiceStatus.thinking);

      final result = await _dispatcher.dispatch(name, args);
      _log('Tool result keys: ${result.keys.toList()}');

      final toolMsg = ChatMessage(
        id: _uniqueId(),
        text: '🔧 $name: ${_summarize(name, result)}',
        role: MessageRole.tool,
        timestamp: DateTime.now(),
        toolName: name,
      );
      state = state.copyWith(
        messages: [...state.messages, toolMsg],
        clearTool: true,
      );
      _schedulePersist();

      // Send the structured result back to Gemini.
      _gemini.sendToolResponse(id, name, result);
    }
  }

  String _summarize(String tool, Map<String, dynamic> r) {
    if (r.containsKey('error')) return r['error'].toString();
    switch (tool) {
      case 'get_weather':
        return '${r['city']}: ${r['temperature']}°C, ${r['condition']}';
      case 'get_stock_price':
        return '${r['symbol']}: ${r['price']} (${r['change']})';
      case 'get_time':
        return '${r['time']} — ${r['date']}';
      case 'save_note':
      case 'create_note':
        return '${r['title'] ?? 'Note saved'}';
      case 'read_notes':
        return '${r['count'] ?? 0} note(s) loaded';
      case 'web_search':
        final n = (r['results'] as List?)?.length ?? 0;
        return '$n web result${n == 1 ? '' : 's'}';
      case 'deep_research':
        final src = (r['sources'] as List?)?.length ?? 0;
        return 'Researched • $src source${src == 1 ? '' : 's'}';
      case 'ask_oracle':
        final cites = (r['citations'] as List?)?.length ?? 0;
        return cites == 0
            ? 'Answered from your notes'
            : 'Answered from $cites chunk${cites == 1 ? '' : 's'}';
      case 'read_emails':
        final cnt = r['count'] as int? ?? 0;
        return '$cnt email${cnt == 1 ? '' : 's'}';
      case 'send_email':
        return r['success'] == true
            ? (r['message'] as String? ?? 'Sent')
            : (r['error']?.toString() ?? 'Send failed');
      case 'generate_image':
        return r['success'] == true ? 'Image generated' : 'Generation failed';
      case 'find_place':
        final top = (r['top'] as Map?)?['name'] as String?;
        if (top != null) return 'Pinned ${top.split(',').first}';
        return r['message']?.toString() ?? 'No match';
      case 'open_app':
        return r['success'] == true
            ? (r['message'] as String? ?? 'App launched')
            : (r['message'] as String? ?? 'App not found');
      case 'toggle_flashlight':
        return r['success'] == true
            ? 'Flashlight ${r['state'] ?? ''}'.trim()
            : (r['message'] as String? ?? 'Failed');
      case 'open_settings_panel':
        return 'Opened ${r['panel'] ?? 'panel'}';
      case 'set_ringer_mode':
        return r['success'] == true
            ? 'Ringer → ${r['mode'] ?? ''}'.trim()
            : 'Could not change ringer';
      case 'play_spotify':
        return r['success'] == true
            ? 'Now playing: ${r['query'] ?? ''}'.trim()
            : 'Spotify failed';
      case 'read_notifications':
        final n = r['count'] as int? ?? 0;
        return '$n notification${n == 1 ? '' : 's'}';
      case 'ghost_type':
      case 'type_text':
        return r['success'] == true
            ? (r['message']?.toString() ?? 'Typed')
            : (r['message']?.toString() ?? 'Typing failed');
      case 'tap_text':
      case 'click_button':
        return r['success'] == true
            ? 'Tapped "${r['query'] ?? ''}"'
            : (r['message']?.toString() ?? 'No match');
      case 'read_screen':
        if (r['success'] != true) {
          return r['message']?.toString() ?? 'Could not read screen';
        }
        final c = r['characters'] as int? ?? 0;
        return 'Read $c char${c == 1 ? '' : 's'} from screen';
      case 'ocr':
      case 'read_with_camera':
        if (r['success'] != true) {
          return r['message']?.toString() ?? 'OCR failed';
        }
        final c = r['characters'] as int? ?? 0;
        final b = r['blocks'] as int? ?? 0;
        return 'OCR: $c char${c == 1 ? '' : 's'} across $b block${b == 1 ? '' : 's'}';
      case 'global_action':
      case 'press_back':
      case 'press_home':
        return r['success'] == true
            ? (r['message']?.toString() ?? 'Done')
            : 'Failed';
      case 'send_sms':
      case 'text_message':
        return r['success'] == true
            ? (r['message']?.toString() ?? 'SMS opened')
            : (r['message']?.toString() ?? 'SMS failed');
      case 'call':
      case 'make_call':
        return r['success'] == true
            ? (r['message']?.toString() ?? 'Calling')
            : (r['message']?.toString() ?? 'Call failed');
      case 'find_contact':
      case 'lookup_contact':
        return r['message']?.toString() ?? 'No match';
      case 'send_whatsapp':
        if (r['success'] != true) {
          return r['message']?.toString() ?? 'WhatsApp failed';
        }
        final who = r['recipient'] as String? ?? 'recipient';
        return r['autoSent'] == true
            ? 'Sent on WhatsApp to $who'
            : 'WhatsApp opened for $who — tap send';
      default:
        final s = r.toString();
        return s.length > 80 ? '${s.substring(0, 80)}...' : s;
    }
  }

  void clearHistory() {
    state = state.copyWith(messages: [], liveTranscript: '');
    _assemblingText = '';
    _aiTranscript = '';
    _userTranscript = '';
    try {
      Hive.box(_historyBoxName).delete(_historyKey);
    } catch (e) {
      _log('History wipe failed: $e');
    }
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _speakingWatchdog?.cancel();
    _aiTurnEndTimer?.cancel();
    _geminiSub?.cancel();
    _levelSub?.cancel();
    _outputLevelSub?.cancel();
    _playbackIdleSub?.cancel();
    _speakResumeSub?.cancel();
    _speakResumeFallback?.cancel();
    _screenFrameSub?.cancel();
    _screenEventSub?.cancel();
    _gemini.dispose();
    _recorder.stopStreaming();
    _vision.dispose();
    ScreenShareService.instance.stop();
    _playback.release();
    try {
      _tts?.stop();
    } catch (_) {}
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final notifier = ChatNotifier(ref);
  ref.onDispose(() => notifier.dispose());
  return notifier;
});
