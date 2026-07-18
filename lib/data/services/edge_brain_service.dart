import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:brutus_app/data/services/voice_backend.dart';

/// On-device [VoiceBackend]. Talks to the EdgeBrain hub, a foreground service
/// running on the phone itself that wraps the NPU models (Gemma3-1B for chat,
/// FastVLM for vision, a small function-calling path for intent) with on-device
/// speech-to-text and text-to-speech. The hub exposes a WebSocket voice channel
/// on localhost, so from the app's point of view it is a drop-in for Gemini
/// Live: same PCM up, same PCM down, same `[EMOTION:xxx]` tags.
///
/// Nothing here reaches the internet. When the phone is in airplane mode with
/// only WiFi off, this backend still works because the hub and the app live on
/// the same device.
///
/// ## Hub wire protocol (JSON text frames over the WebSocket)
///
/// App to hub:
///   * `{"type":"start","user":"Aditya"}`  open a session
///   * `{"type":"audio","pcm16":"<base64 16kHz mono>"}`  a mic chunk
///   * `{"type":"text","text":"..."}`  a typed turn
///   * `{"type":"image","jpeg":"<base64>"}`  a vision frame for FastVLM
///   * `{"type":"tool_result","id":"..","name":"..","result":{..}}`
///   * `{"type":"mute","muted":true}`  optional, app also just stops sending
///
/// Hub to app:
///   * `{"type":"ready"}`                       becomes setupComplete
///   * `{"type":"stt","text":".."}`             becomes inputTranscription
///   * `{"type":"token","text":".."}`           becomes outputTranscription
///   * `{"type":"audio","pcm24":"<base64>"}`    becomes a 24kHz PCM voice chunk
///   * `{"type":"turn_complete"}`               becomes turnComplete
///   * `{"type":"interrupted"}`                 becomes interrupted
///   * `{"type":"tool_call","id":"..","name":"..","args":{..}}`
///   * `{"type":"error","message":".."}`
///
/// The hub owns the Brutus persona (system prompt, the `[EMOTION:xxx]` rule, and
/// the "reply in the user's language" rule), so those behaviours match the
/// cloud brain without the app resending them.
class EdgeBrainService implements VoiceBackend {
  EdgeBrainService({String? wsUrl})
      : _wsUrl = wsUrl ?? _defaultWsUrl;

  /// Default hub endpoint. The EdgeBrain foreground service binds here.
  static const _defaultWsUrl = 'ws://127.0.0.1:8765/voice';

  final String _wsUrl;

  WebSocket? _socket;
  bool _connected = false;
  bool _ready = false;
  bool _muted = false;
  bool _disposed = false;

  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  @override
  bool get isConnected => _connected && _ready;

  /// The hub is always a live audio channel.
  @override
  bool get isLiveMode => true;

  @override
  bool get isMicMuted => _muted;

  void _log(String msg) => dev.log('[EdgeBrain] $msg', name: 'BrutusAI');

  @override
  Future<void> connect() async {
    if (_disposed || _connected) return;
    _log('Connecting to hub at $_wsUrl ...');
    try {
      final socket =
          await WebSocket.connect(_wsUrl).timeout(const Duration(seconds: 5));
      if (_disposed) {
        try {
          await socket.close();
        } catch (_) {}
        return;
      }
      _socket = socket;
      _connected = true;

      socket.listen(
        _onFrame,
        onDone: () {
          _log('Hub socket closed');
          _connected = false;
          _ready = false;
          if (!_messageController.isClosed) {
            _messageController.add({'type': 'disconnected'});
          }
        },
        onError: (Object e) {
          _log('Hub socket error: $e');
          if (!_messageController.isClosed) {
            _messageController.add({'type': 'error', 'message': '$e'});
          }
        },
        cancelOnError: false,
      );

      _send({'type': 'start'});

      // The hub should answer with {"type":"ready"} quickly. If it does not,
      // surface a friendly error instead of hanging.
      Timer(const Duration(seconds: 8), () {
        if (!_ready && _connected && !_messageController.isClosed) {
          _messageController.add({
            'type': 'error',
            'message':
                'EdgeBrain hub did not report ready. Is the on-device service running?',
          });
        }
      });
    } catch (e) {
      _log('Hub connect failed: $e');
      _connected = false;
      if (!_messageController.isClosed) {
        _messageController.add({
          'type': 'error',
          'message':
              'Could not reach the EdgeBrain hub on $_wsUrl. Start the on-device brain, then try again.',
        });
      }
    }
  }

  void _onFrame(dynamic data) {
    if (_disposed) return;
    Map<String, dynamic> frame;
    try {
      final str = data is String ? data : utf8.decode(data as List<int>);
      frame = jsonDecode(str) as Map<String, dynamic>;
    } catch (e) {
      _log('bad frame: $e');
      return;
    }

    final type = frame['type'] as String?;
    switch (type) {
      case 'ready':
        _ready = true;
        _log('Hub ready');
        _emit({'setupComplete': true});
        break;
      case 'stt':
        final text = frame['text'] as String?;
        if (text != null && text.isNotEmpty) {
          _emit({'inputTranscription': text});
        }
        break;
      case 'token':
        final text = frame['text'] as String?;
        if (text != null && text.isNotEmpty) {
          // Streamed AI text. The first chunk may carry a leading
          // [EMOTION:xxx] tag; ChatNotifier strips and routes it exactly as it
          // does for Gemini, so the robot layer is untouched.
          _emit({'outputTranscription': text});
        }
        break;
      case 'audio':
        final pcm24 = frame['pcm24'] as String?;
        if (pcm24 != null && pcm24.isNotEmpty) {
          _emit({
            'serverContent': {
              'modelTurn': {
                'parts': [
                  {
                    'inlineData': {'data': pcm24},
                  },
                ],
              },
            },
          });
        }
        break;
      case 'turn_complete':
        _emit({
          'serverContent': {'turnComplete': true},
        });
        break;
      case 'interrupted':
        _emit({
          'serverContent': {'interrupted': true},
        });
        break;
      case 'tool_call':
        _emit({
          'toolCall': {
            'functionCalls': [
              {
                'id': frame['id'] ?? frame['name'] ?? '',
                'name': frame['name'] ?? '',
                'args': (frame['args'] as Map<String, dynamic>?) ??
                    <String, dynamic>{},
              },
            ],
          },
        });
        break;
      case 'error':
        _emit({'type': 'error', 'message': frame['message'] ?? 'Hub error'});
        break;
      default:
        _log('unknown frame type: $type');
    }
  }

  void _emit(Map<String, dynamic> event) {
    if (!_messageController.isClosed) _messageController.add(event);
  }

  void _send(Map<String, dynamic> frame) {
    final socket = _socket;
    if (socket == null || !_connected) return;
    try {
      socket.add(jsonEncode(frame));
    } catch (e) {
      _log('send failed (socket dead): $e');
      _connected = false;
      _ready = false;
      _emit({'type': 'disconnected'});
    }
  }

  @override
  void setMute(bool muted) {
    _muted = muted;
    _log(muted ? 'mic muted' : 'mic unmuted');
    _send({'type': 'mute', 'muted': muted});
  }

  @override
  void sendAudioChunk(String base64Audio) {
    if (!isConnected || _muted) return;
    _send({'type': 'audio', 'pcm16': base64Audio});
  }

  @override
  bool sendVideoFrame(String base64Jpeg) {
    if (!isConnected) return false;
    _send({'type': 'image', 'jpeg': base64Jpeg});
    return true;
  }

  @override
  void sendText(String text) {
    _send({'type': 'text', 'text': text});
  }

  @override
  void sendToolResponse(
    String functionCallId,
    String functionName,
    dynamic result,
  ) {
    _send({
      'type': 'tool_result',
      'id': functionCallId,
      'name': functionName,
      'result': result,
    });
  }

  /// The hub tracks its own playback, so this is a no-op on device.
  @override
  void notifyAiAudioActive() {}

  @override
  void disconnect() {
    _log('Disconnecting from hub');
    _connected = false;
    _ready = false;
    _muted = false;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    disconnect();
    _messageController.close();
  }
}
