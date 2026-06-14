import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

/// Brutus — Audio Recorder Service
/// Streams PCM 16kHz mono chunks to Gemini Live API
/// Provides audio level feedback for UI visualization
class AudioRecorderService {
  static final AudioRecorderService _instance = AudioRecorderService._();
  static AudioRecorderService get instance => _instance;
  AudioRecorderService._();

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  bool _isRecording = false;

  // Audio level for UI visualization (0.0 to 1.0)
  double _audioLevel = 0.0;
  double get audioLevel => _audioLevel;
  final _levelController = StreamController<double>.broadcast();
  Stream<double> get audioLevelStream => _levelController.stream;
  Timer? _levelTimer;

  bool get isRecording => _isRecording;

  static const _automationChannel =
      MethodChannel('com.adityapandey.brutus_app/phone_automation');

  void _log(String msg) => dev.log('[Recorder] $msg', name: 'BrutusAI');

  /// Check if a Bluetooth audio device (SCO or A2DP) is connected.
  Future<bool> _isBluetoothAudioConnected() async {
    try {
      final result = await _automationChannel
          .invokeMethod<bool>('isBluetoothAudioConnected');
      return result ?? false;
    } catch (e) {
      _log('BT audio check failed: $e');
      return false;
    }
  }

  /// Request microphone permission with full error handling
  Future<PermissionResult> requestPermission() async {
    _log('Requesting microphone permission...');

    // First check with the record package itself
    final hasRecordPerm = await _recorder.hasPermission();
    if (hasRecordPerm) {
      _log('Record package says permission granted');
      return PermissionResult.granted;
    }

    // Try using permission_handler
    final status = await Permission.microphone.status;
    _log('Current permission status: $status');

    if (status.isGranted) {
      return PermissionResult.granted;
    }

    if (status.isPermanentlyDenied) {
      _log('Permission permanently denied — need to open settings');
      return PermissionResult.permanentlyDenied;
    }

    // Request the permission
    final result = await Permission.microphone.request();
    _log('Permission request result: $result');

    if (result.isGranted) {
      return PermissionResult.granted;
    } else if (result.isPermanentlyDenied) {
      return PermissionResult.permanentlyDenied;
    } else {
      return PermissionResult.denied;
    }
  }

  /// Start streaming PCM 16kHz chunks
  Future<RecordingStartResult> startStreaming({
    required void Function(String base64Chunk) onChunk,
  }) async {
    if (_isRecording) return RecordingStartResult.alreadyRecording;

    final permResult = await requestPermission();
    if (permResult != PermissionResult.granted) {
      _log('Permission not granted: $permResult');
      return permResult == PermissionResult.permanentlyDenied
          ? RecordingStartResult.permissionPermanentlyDenied
          : RecordingStartResult.permissionDenied;
    }

    try {
      _log('Starting audio stream...');

      // Always stay in MODE_NORMAL. Setting MODE_IN_COMMUNICATION on
      // Samsung One UI hijacks the entire audio policy: it routes our
      // MEDIA AudioTrack to the earpiece (or to BT SCO, which is mono
      // and reserved for voice calls — our 24 kHz MUSIC stream cannot
      // even write to it, hence the silent BT case). The phone mic
      // captures fine without comm-mode; if the user has a BT headset,
      // A2DP playback still works. Echo suppression is handled in
      // ChatNotifier (mic chunks dropped while Brutus speaks).
      const audioMode = AudioManagerMode.modeNormal;
      final btConnected = await _isBluetoothAudioConnected();
      _log('Audio mode: ${audioMode.name} (BT=$btConnected)');

      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
          // Disable hardware AGC/NS/AEC entirely. On Samsung devices the
          // hardware AEC adapts so aggressively after a few seconds of
          // speaker playback that it starts cancelling the user's actual
          // voice (mic level pinned at 0.00 even while the user speaks).
          // Echo suppression is handled in ChatNotifier — mic chunks are
          // dropped for 2.5s after the last AI audio chunk.
          // Gemini Live's server-side VAD handles background noise just
          // fine, so noise suppression isn't critical at the encoder layer.
          autoGain: false,
          noiseSuppress: false,
          echoCancel: false,
          // mic source = the raw, unprocessed microphone. This bypasses
          // every Samsung-specific DSP path that was breaking us.
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.mic,
            audioManagerMode: audioMode,
            speakerphone: false,
            // Don't manage BT — that requires comm-mode, which we no
            // longer want. The mic captures fine from the phone even
            // when a BT headset is connected for output.
            manageBluetooth: false,
          ),
        ),
      );

      _isRecording = true;
      _log('Audio stream started successfully');

      // Start polling amplitude for UI
      _startLevelMonitoring();

      int chunkCount = 0;
      int totalBytes = 0;
      final firstChunkTimer = Stopwatch()..start();

      _subscription = stream.listen(
        (chunk) {
          if (chunk.isNotEmpty) {
            chunkCount++;
            totalBytes += chunk.length;
            if (chunkCount == 1) {
              _log('First chunk received after '
                  '${firstChunkTimer.elapsedMilliseconds}ms (${chunk.length} bytes)');
            } else if (chunkCount % 50 == 0) {
              _log('Streaming healthy — $chunkCount chunks, '
                  '${(totalBytes / 1024).toStringAsFixed(1)} KB total, '
                  'level=${_audioLevel.toStringAsFixed(2)}');
            }
            // Calculate RMS level from PCM data for visualization
            _updateLevel(chunk);
            onChunk(base64Encode(chunk));
          }
        },
        onDone: () {
          _log('Stream done — sent $chunkCount chunks '
              '(${(totalBytes / 1024).toStringAsFixed(1)} KB)');
          _isRecording = false;
          _stopLevelMonitoring();
        },
        onError: (e) {
          _log('Stream error: $e');
          _isRecording = false;
          _stopLevelMonitoring();
        },
        cancelOnError: false,
      );

      return RecordingStartResult.started;
    } catch (e) {
      _log('Failed to start stream: $e');
      _isRecording = false;
      return RecordingStartResult.failed;
    }
  }

  /// Calculate audio level from PCM 16-bit data
  void _updateLevel(Uint8List chunk) {
    if (chunk.length < 2) return;

    // Read PCM 16-bit little-endian samples
    double sumSquares = 0;
    int sampleCount = 0;
    for (int i = 0; i < chunk.length - 1; i += 2) {
      // Little-endian 16-bit signed
      int sample = chunk[i] | (chunk[i + 1] << 8);
      if (sample > 32767) sample -= 65536;
      sumSquares += sample * sample;
      sampleCount++;
    }

    if (sampleCount > 0) {
      final rms = sqrt(sumSquares / sampleCount);
      // Normalize: 16-bit max is 32768, but typical speech is much lower
      _audioLevel = (rms / 8000.0).clamp(0.0, 1.0);
      _levelController.add(_audioLevel);
    }
  }

  void _startLevelMonitoring() {
    _levelTimer?.cancel();
    // Decay the level smoothly when no chunks arrive
    _levelTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_audioLevel > 0.01) {
        _audioLevel *= 0.85;
        _levelController.add(_audioLevel);
      }
    });
  }

  void _stopLevelMonitoring() {
    _levelTimer?.cancel();
    _audioLevel = 0.0;
    _levelController.add(0.0);
  }

  /// Stop recording. Idempotent — safe to call multiple times.
  Future<void> stopStreaming() async {
    if (!_isRecording && _subscription == null) return;
    _log('Stopping stream...');
    _stopLevelMonitoring();
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    _isRecording = false;
  }

  /// Open app settings for permission
  Future<void> openSettings() => openAppSettings();

  void dispose() {
    stopStreaming();
    _levelController.close();
    _recorder.dispose();
  }
}

enum PermissionResult { granted, denied, permanentlyDenied }

enum RecordingStartResult {
  started,
  alreadyRecording,
  permissionDenied,
  permissionPermanentlyDenied,
  failed,
}
