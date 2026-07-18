import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:brutus_app/core/constants/api_constants.dart';

/// Which engine speaks Brutus's "Speak for me" text.
enum TtsEngine {
  gemini,
  sarvam,
  system;

  String get label => switch (this) {
        TtsEngine.gemini => 'Gemini',
        TtsEngine.sarvam => 'Sarvam · Bulbul (Indic)',
        TtsEngine.system => 'System (offline)',
      };

  static TtsEngine fromName(String? s) =>
      TtsEngine.values.firstWhere((e) => e.name == s,
          orElse: () => TtsEngine.gemini);
}

/// Which engine does the text reasoning for Deep Research + Oracle synthesis.
enum LlmEngine {
  groq,
  sarvam;

  String get label => switch (this) {
        LlmEngine.groq => 'Groq · Llama 3.3 70B',
        LlmEngine.sarvam => 'Sarvam-30B (Indic)',
      };

  static LlmEngine fromName(String? s) =>
      LlmEngine.values.firstWhere((e) => e.name == s,
          orElse: () => LlmEngine.groq);
}

/// Where Brutus's live voice conversation runs.
enum BrainMode {
  cloud,
  edge;

  String get label => switch (this) {
        BrainMode.cloud => 'Cloud · Gemini Live',
        BrainMode.edge => 'On-device · EdgeBrain (NPU)',
      };

  String get blurb => switch (this) {
        BrainMode.cloud =>
          'Gemini Live over the internet. Best quality, needs a key.',
        BrainMode.edge =>
          'Runs on the phone NPU. Works with no internet. Needs the EdgeBrain service running.',
      };

  static BrainMode fromName(String? s) =>
      BrainMode.values.firstWhere((e) => e.name == s,
          orElse: () => BrainMode.cloud);
}

/// Static, synchronous access to the provider preferences (backed by the
/// Hive `preferences` box). Lets plain services read the current selection
/// without a Riverpod `ref`.
class AiEnginePrefs {
  AiEnginePrefs._();

  static const kTts = 'brutus_tts_engine';
  static const kLlm = 'brutus_llm_engine';
  static const kSarvamVoice = 'brutus_sarvam_voice';
  static const kSarvamLang = 'brutus_sarvam_lang';
  static const kBrain = 'brutus_brain_mode';
  static const kEdgeUrl = 'brutus_edge_ws_url';

  /// Default localhost endpoint the on-device EdgeBrain hub binds to.
  static const defaultEdgeWsUrl = 'ws://127.0.0.1:8765/voice';

  // Bulbul v2 speakers (stable, well-documented names).
  static const sarvamVoices = [
    'anushka', 'abhilash', 'manisha', 'vidya', 'arya', 'karun', 'hitesh',
  ];

  // BCP-47 codes Sarvam supports.
  static const sarvamLanguages = <String, String>{
    'en-IN': 'English (India)',
    'hi-IN': 'Hindi',
    'bn-IN': 'Bengali',
    'gu-IN': 'Gujarati',
    'kn-IN': 'Kannada',
    'ml-IN': 'Malayalam',
    'mr-IN': 'Marathi',
    'od-IN': 'Odia',
    'pa-IN': 'Punjabi',
    'ta-IN': 'Tamil',
    'te-IN': 'Telugu',
  };

  static Box get _box => Hive.box(ApiConstants.boxPreferences);

  static TtsEngine ttsEngine() =>
      TtsEngine.fromName(_read(kTts) as String?);
  static LlmEngine llmEngine() =>
      LlmEngine.fromName(_read(kLlm) as String?);
  static String sarvamVoice() =>
      (_read(kSarvamVoice) as String?) ?? sarvamVoices.first;
  static String sarvamLanguage() =>
      (_read(kSarvamLang) as String?) ?? 'en-IN';
  static BrainMode brainMode() => BrainMode.fromName(_read(kBrain) as String?);
  static String edgeBrainWsUrl() =>
      (_read(kEdgeUrl) as String?) ?? defaultEdgeWsUrl;

  static dynamic _read(String key) {
    try {
      return _box.get(key);
    } catch (e) {
      dev.log('[AiEngine] read $key failed: $e', name: 'BrutusAI');
      return null;
    }
  }

  static void write(String key, String value) {
    try {
      _box.put(key, value);
    } catch (e) {
      dev.log('[AiEngine] write $key failed: $e', name: 'BrutusAI');
    }
  }
}

class AiEngineState {
  final TtsEngine ttsEngine;
  final LlmEngine llmEngine;
  final String sarvamVoice;
  final String sarvamLanguage;
  final BrainMode brainMode;

  const AiEngineState({
    this.ttsEngine = TtsEngine.gemini,
    this.llmEngine = LlmEngine.groq,
    this.sarvamVoice = 'anushka',
    this.sarvamLanguage = 'en-IN',
    this.brainMode = BrainMode.cloud,
  });

  AiEngineState copyWith({
    TtsEngine? ttsEngine,
    LlmEngine? llmEngine,
    String? sarvamVoice,
    String? sarvamLanguage,
    BrainMode? brainMode,
  }) =>
      AiEngineState(
        ttsEngine: ttsEngine ?? this.ttsEngine,
        llmEngine: llmEngine ?? this.llmEngine,
        sarvamVoice: sarvamVoice ?? this.sarvamVoice,
        sarvamLanguage: sarvamLanguage ?? this.sarvamLanguage,
        brainMode: brainMode ?? this.brainMode,
      );
}

class AiEngineNotifier extends StateNotifier<AiEngineState> {
  AiEngineNotifier() : super(const AiEngineState()) {
    state = AiEngineState(
      ttsEngine: AiEnginePrefs.ttsEngine(),
      llmEngine: AiEnginePrefs.llmEngine(),
      sarvamVoice: AiEnginePrefs.sarvamVoice(),
      sarvamLanguage: AiEnginePrefs.sarvamLanguage(),
      brainMode: AiEnginePrefs.brainMode(),
    );
  }

  void setTtsEngine(TtsEngine e) {
    AiEnginePrefs.write(AiEnginePrefs.kTts, e.name);
    state = state.copyWith(ttsEngine: e);
  }

  void setLlmEngine(LlmEngine e) {
    AiEnginePrefs.write(AiEnginePrefs.kLlm, e.name);
    state = state.copyWith(llmEngine: e);
  }

  void setSarvamVoice(String v) {
    AiEnginePrefs.write(AiEnginePrefs.kSarvamVoice, v);
    state = state.copyWith(sarvamVoice: v);
  }

  void setSarvamLanguage(String code) {
    AiEnginePrefs.write(AiEnginePrefs.kSarvamLang, code);
    state = state.copyWith(sarvamLanguage: code);
  }

  void setBrainMode(BrainMode m) {
    AiEnginePrefs.write(AiEnginePrefs.kBrain, m.name);
    state = state.copyWith(brainMode: m);
  }
}

final aiEngineProvider =
    StateNotifierProvider<AiEngineNotifier, AiEngineState>((ref) {
  return AiEngineNotifier();
});
