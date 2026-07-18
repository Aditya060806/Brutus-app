import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:brutus_app/core/constants/api_constants.dart';
import 'package:brutus_app/data/services/esp_cam_service.dart';
import 'package:brutus_app/providers/chat_provider.dart';

export 'package:brutus_app/data/services/esp_cam_service.dart'
    show EspCamState;

/// Brutus's eyes — ties the ESP32-CAM MJPEG stream to the app.
///
/// - Owns the camera URL (persisted) and connection lifecycle.
/// - "Brutus sees": throttles the live frames and forwards them to Gemini via
///   [ChatNotifier.sendExternalVisionFrame], so Brutus can see through the
///   robot's eyes and talk about it (router mode → phone keeps internet).
/// - Flash LED control.
///
/// The live image itself is NOT stored in state (that would rebuild the whole
/// tree ~15×/s). The screen listens to [EspCamService.frameStream] directly.
class RobotEyesState {
  final String camUrl;
  final EspCamState connection;
  final bool brutusSees;
  final bool flashOn;
  final int framesToBrutus;
  final String? errorMessage;

  const RobotEyesState({
    this.camUrl = '',
    this.connection = EspCamState.stopped,
    this.brutusSees = false,
    this.flashOn = false,
    this.framesToBrutus = 0,
    this.errorMessage,
  });

  bool get isStreaming => connection == EspCamState.streaming;
  bool get isConnecting => connection == EspCamState.connecting;
  bool get hasUrl => camUrl.trim().isNotEmpty;

  RobotEyesState copyWith({
    String? camUrl,
    EspCamState? connection,
    bool? brutusSees,
    bool? flashOn,
    int? framesToBrutus,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RobotEyesState(
      camUrl: camUrl ?? this.camUrl,
      connection: connection ?? this.connection,
      brutusSees: brutusSees ?? this.brutusSees,
      flashOn: flashOn ?? this.flashOn,
      framesToBrutus: framesToBrutus ?? this.framesToBrutus,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class RobotEyesNotifier extends StateNotifier<RobotEyesState> {
  RobotEyesNotifier(this._ref) : super(const RobotEyesState()) {
    _bind();
  }

  static const _kCamUrl = 'brutus_cam_url';

  final Ref _ref;
  final EspCamService _cam = EspCamService.instance;

  StreamSubscription<EspCamState>? _stateSub;
  StreamSubscription<Uint8List>? _frameSub;

  // Throttle for feeding Gemini (frames arrive ~15×/s; we only need ~1 / 1.5s).
  DateTime _lastSentToBrutus = DateTime(2000);
  static const _brutusInterval = Duration(milliseconds: 1500);

  void _log(String m) => dev.log('[RobotEyes] $m', name: 'BrutusAI');

  void _bind() {
    _restorePrefs();

    _stateSub = _cam.stateStream.listen((s) {
      state = state.copyWith(
        connection: s,
        clearError: s != EspCamState.error,
        errorMessage: s == EspCamState.error
            ? 'Cannot reach the camera. Check the IP and that the phone is on '
                'the same WiFi as the ESP32-CAM.'
            : null,
      );
    });

    // One persistent frame subscription; the handler decides what to do with
    // each frame based on the current toggles.
    _frameSub = _cam.frameStream.listen(_onFrame);
  }

  void _onFrame(Uint8List jpeg) {
    // Feed Gemini (throttled) when "Brutus sees" is on.
    if (state.brutusSees) {
      final now = DateTime.now();
      if (now.difference(_lastSentToBrutus) >= _brutusInterval) {
        _lastSentToBrutus = now;
        _ref
            .read(chatProvider.notifier)
            .sendExternalVisionFrame(base64Encode(jpeg));
        state = state.copyWith(framesToBrutus: state.framesToBrutus + 1);
      }
    }
    // (Object detection hooks in here in Phase C.)
  }

  // ── Actions ──

  void setUrl(String url) {
    final trimmed = url.trim();
    state = state.copyWith(camUrl: trimmed, clearError: true);
    _persist(_kCamUrl, trimmed);
  }

  Future<void> connect() async {
    if (!state.hasUrl) {
      state = state.copyWith(errorMessage: 'Enter the camera IP first.');
      return;
    }
    state = state.copyWith(clearError: true);
    await _cam.start(state.camUrl);
  }

  Future<void> disconnect() async {
    await _cam.stop();
    state = state.copyWith(framesToBrutus: 0);
  }

  void setBrutusSees(bool on) {
    if (on && !_ref.read(chatProvider).isConnected) {
      state = state.copyWith(
        errorMessage: 'Power on Brutus (the AI) first so he can see.',
      );
      return;
    }
    state = state.copyWith(
      brutusSees: on,
      framesToBrutus: on ? 0 : state.framesToBrutus,
      clearError: true,
    );
  }

  Future<void> setFlash(bool on) async {
    state = state.copyWith(flashOn: on);
    await _cam.setFlash(on);
  }

  /// Grab a single frame and hand it to Brutus with a nudge to describe it.
  Future<void> askBrutusWhatHeSees() async {
    final chat = _ref.read(chatProvider.notifier);
    if (!_ref.read(chatProvider).isConnected) {
      state = state.copyWith(errorMessage: 'Power on Brutus first.');
      return;
    }
    final frame = await _cam.capture();
    if (frame != null) {
      chat.sendExternalVisionFrame(base64Encode(frame));
    }
    chat.sendText('What do you see through your eyes right now?');
  }

  void _restorePrefs() {
    try {
      final box = Hive.box(ApiConstants.boxPreferences);
      final url = box.get(_kCamUrl) as String?;
      if (url != null && url.isNotEmpty) {
        state = state.copyWith(camUrl: url);
      }
    } catch (e) {
      _log('restore prefs failed: $e');
    }
  }

  void _persist(String key, dynamic value) {
    try {
      Hive.box(ApiConstants.boxPreferences).put(key, value);
    } catch (e) {
      _log('persist $key failed: $e');
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _frameSub?.cancel();
    _cam.stop();
    super.dispose();
  }
}

final robotEyesProvider =
    StateNotifierProvider<RobotEyesNotifier, RobotEyesState>((ref) {
  return RobotEyesNotifier(ref);
});
