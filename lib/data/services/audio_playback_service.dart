import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';

import 'package:flutter/services.dart';

/// Brutus Mobile — Audio Playback Service
///
/// Plays the 24kHz mono 16-bit PCM chunks Gemini Live streams back through a
/// **single persistent native AudioTrack** (Kotlin side). This avoids the
/// `audioplayers` MediaPlayer reset/prepareAsync cycle that was happening
/// every ~400ms — which was both choppy and stealing audio focus from the mic
/// recorder, eventually killing STT after a few turns.
///
/// Behaviour:
///   • One AudioTrack stays open the whole "system on" session
///   • Writes are streamed continuously, no gaps
///   • `stop()` is the only thing that releases the track (called on power off)
///   • `flush()` clears the queue + replays, used on Gemini barge-in (interrupted)
class AudioPlaybackService {
  static final AudioPlaybackService _instance = AudioPlaybackService._();
  static AudioPlaybackService get instance => _instance;
  AudioPlaybackService._();

  static const _channel =
      MethodChannel('com.adityapandey.brutus_app/pcm_player');

  bool _started = false;
  bool _isPlaying = false;
  Timer? _idleTimer;

  // Fires once when playback transitions from active → idle (600ms after last
  // chunk). ChatNotifier uses this to re-anchor the echo suppression guard so
  // the 2.5s window starts from when audio actually stops, not when the last
  // chunk was received (the native AudioTrack has a 2-second buffer, so audio
  // keeps playing well after the last chunk arrives).
  final _idleNotifyController = StreamController<void>.broadcast();

  // Output level (0..1) computed from the most recently queued PCM chunks.
  // Mirrors what `analyser.getByteFrequencyData` gives the desktop reference.
  double _outputLevel = 0.0;
  final _levelController = StreamController<double>.broadcast();
  Timer? _levelDecayTimer;

  bool get isPlaying => _isPlaying;
  double get outputLevel => _outputLevel;
  Stream<double> get outputLevelStream => _levelController.stream;
  Stream<void> get onIdleStream => _idleNotifyController.stream;

  /// Queue a base64-encoded PCM chunk arriving from Gemini. Pushes straight to
  /// the native AudioTrack; no buffering/debouncing in Dart.
  Future<void> queueChunk(String base64Chunk) async {
    Uint8List bytes;
    try {
      bytes = base64Decode(base64Chunk);
    } catch (e) {
      _log('decode failed: $e');
      return;
    }
    if (bytes.isEmpty) return;

    // Compute output level (RMS of the 16-bit PCM) for the sphere visualizer.
    _emitLevel(bytes);

    if (!_started) {
      try {
        await _channel.invokeMethod('start');
        _started = true;
      } catch (e) {
        _log('start failed: $e');
        return;
      }
    }

    _isPlaying = true;
    _idleTimer?.cancel();

    try {
      await _channel.invokeMethod('write', bytes);
    } catch (e) {
      _log('write failed: $e');
    }

    // After ~600ms with no new chunks we consider playback done — used by
    // the chat UI to flip the speaking → idle status. AudioTrack itself
    // keeps running until the next chunk arrives.
    _idleTimer = Timer(const Duration(milliseconds: 600), () {
      _isPlaying = false;
      _emitSilent();
      // Notify ChatNotifier so it can re-anchor the echo suppression guard
      // to NOW (playback end) rather than when the last chunk was received.
      if (!_idleNotifyController.isClosed) _idleNotifyController.add(null);
    });
  }

  void _emitLevel(Uint8List pcm) {
    if (pcm.length < 2) return;
    double sumSquares = 0;
    int sampleCount = 0;
    // Sample every 8 frames to keep cost low; PCM is 16-bit little-endian
    for (int i = 0; i < pcm.length - 1; i += 16) {
      int sample = pcm[i] | (pcm[i + 1] << 8);
      if (sample > 32767) sample -= 65536;
      sumSquares += sample * sample;
      sampleCount++;
    }
    if (sampleCount == 0) return;
    final rms = sqrt(sumSquares / sampleCount);
    // Normalize: typical speech RMS hovers around 3000-8000 on 16-bit PCM
    final level = (rms / 9000.0).clamp(0.0, 1.0);
    _outputLevel = level;
    if (!_levelController.isClosed) {
      _levelController.add(level);
    }
    // Schedule a smooth decay to zero so the orb settles after each chunk
    _levelDecayTimer?.cancel();
    _levelDecayTimer = Timer.periodic(const Duration(milliseconds: 80), (t) {
      _outputLevel *= 0.7;
      if (!_levelController.isClosed) _levelController.add(_outputLevel);
      if (_outputLevel < 0.02) {
        _outputLevel = 0;
        if (!_levelController.isClosed) _levelController.add(0);
        t.cancel();
      }
    });
  }

  void _emitSilent() {
    _outputLevel = 0;
    _levelDecayTimer?.cancel();
    if (!_levelController.isClosed) _levelController.add(0);
  }

  /// Drop everything pending (used on Gemini "interrupted" / user barge-in).
  Future<void> stop() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _isPlaying = false;
    _emitSilent();
    if (!_started) return;
    try {
      await _channel.invokeMethod('flush');
    } catch (e) {
      _log('flush failed: $e');
    }
  }

  /// Tear down the native AudioTrack entirely. Called on system power-off
  /// or before a fresh TTS turn (Speak-for-me) to ensure we don't write
  /// into a stale/dead track left over from a previous session or hot
  /// restart.
  ///
  /// We always invoke the native 'stop' method even if Dart's [_started]
  /// flag is false: after a Flutter hot restart, Dart loses its sense of
  /// started state but the Kotlin singleton keeps the AudioTrack open. The
  /// underlying IAudioTrack binder is dead (the Dart engine that owned it
  /// is gone), so the next write triggers `restoreTrack_l` recovery that
  /// silently drops the first burst of audio. Forcing native 'stop' here
  /// ensures the next queueChunk creates a fresh, healthy track.
  Future<void> release() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _levelDecayTimer?.cancel();
    _levelDecayTimer = null;
    _isPlaying = false;
    _emitSilent();
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      _log('release failed: $e');
    }
    _started = false;
  }

  /// Backward-compat alias used by callers that did setVolume on audioplayers.
  /// AudioTrack volume is set globally via the OS media stream; this is a no-op.
  Future<void> setVolume(double volume) async {}

  void dispose() {
    release();
    _idleNotifyController.close();
  }

  void _log(String msg) => dev.log('[Playback] $msg', name: 'BrutusAI');
}
