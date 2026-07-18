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

  // 24 kHz mono 16-bit PCM → 48 bytes per millisecond of audio.
  static const _bytesPerMs = 24000 * 2 ~/ 1000; // 48

  // Wall-clock time (ms since epoch) at which everything queued so far will
  // have finished *playing*.
  //
  // Why this matters: the native side (PcmStreamPlayer) does NOT block on
  // write — it drops each chunk into an in-memory queue that a background
  // thread feeds to the AudioTrack at real time. Gemini's native-audio model
  // streams a reply FASTER than real time, so the last chunk is *received*
  // seconds before it is actually *heard*. If we key "playback done" off the
  // last received chunk, we re-open the mic while Brutus is still talking and
  // it transcribes the tail of its own reply as user speech. Tracking the
  // cumulative audio duration lets us fire "idle" when the speaker truly goes
  // quiet.
  int _playbackClockMs = 0;

  // Fires once when playback has genuinely drained (the speaker is quiet).
  // ChatNotifier uses this to re-anchor the echo suppression guard and re-open
  // the mic — so it must reflect real audio end, not data arrival.
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

    // Advance the playback clock by this chunk's real duration. If the clock
    // is already in the past, playback had drained, so restart it from now.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final chunkMs = (bytes.length / _bytesPerMs).round();
    final base = _playbackClockMs > nowMs ? _playbackClockMs : nowMs;
    _playbackClockMs = base + chunkMs;

    try {
      await _channel.invokeMethod('write', bytes);
    } catch (e) {
      _log('write failed: $e');
    }

    // Fire "idle" only once the speaker has ACTUALLY played out every queued
    // chunk (+ a short tail for start-up latency / room reverb), not a fixed
    // delay after the last chunk was received. For a fast-arriving reply those
    // two moments are many seconds apart; keying the mic re-open off real audio
    // end is what stops Brutus from hearing the tail of its own reply.
    var remainingMs = _playbackClockMs - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs < 0) remainingMs = 0;
    _idleTimer = Timer(Duration(milliseconds: remainingMs + 300), () {
      _isPlaying = false;
      _playbackClockMs = 0;
      _emitSilent();
      // Notify ChatNotifier so it can re-anchor the echo suppression guard
      // to NOW (real playback end) and re-open the mic for the next turn.
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
    _playbackClockMs = 0;
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
    _playbackClockMs = 0;
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
