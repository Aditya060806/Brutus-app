import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/services.dart';

/// Bandwidth profile for screen sharing — mirrors VisionDataMode for parity.
enum ScreenShareDataMode { standard, low }

extension ScreenShareDataModeX on ScreenShareDataMode {
  /// Cadence between frames sent up to Gemini.
  /// Must be generous — large JPEGs compete with mic audio on the same
  /// WebSocket and Gemini's VAD stalls when frames arrive too frequently.
  /// The Dart-side ChatNotifier also enforces a 4s cooldown and skips
  /// frames while audio is active, so the effective rate is even lower.
  Duration get interval => switch (this) {
        ScreenShareDataMode.standard => const Duration(seconds: 5),
        ScreenShareDataMode.low => const Duration(seconds: 7),
      };

  /// JPEG quality 0-100. Lower = smaller payload, less WebSocket contention.
  int get jpegQuality => switch (this) {
        ScreenShareDataMode.standard => 40,
        ScreenShareDataMode.low => 30,
      };

  /// Longest-edge resolution for the captured framebuffer.
  /// Kept small to minimize payload — Gemini only needs enough detail to
  /// read text and identify UI elements, not pixel-perfect fidelity.
  int get maxDimension => switch (this) {
        ScreenShareDataMode.standard => 720,
        ScreenShareDataMode.low => 480,
      };

  String get label => switch (this) {
        ScreenShareDataMode.standard => 'Standard (720px · 5s)',
        ScreenShareDataMode.low => 'Low data (480px · 7s)',
      };
}

/// Brutus — Screen share service.
///
/// Wraps the native MediaProjection capture pipeline. Once running, frames
/// arrive on [frames] as base64 JPEG strings ready to forward to Gemini's
/// `realtimeInput.mediaChunks` channel.
///
/// One-shot consent model: every call to [start] re-prompts the system
/// dialog because Android revokes MediaProjection grants when the foreground
/// service ends. Consent flow lives natively (MainActivity intercepts
/// `requestScreenCapture` to drive the consent intent).
class ScreenShareService {
  ScreenShareService._();
  static final ScreenShareService instance = ScreenShareService._();

  static const _channel =
      MethodChannel('com.adityapandey.brutus_app/phone_automation');

  final _frames = StreamController<ScreenShareFrame>.broadcast();
  Stream<ScreenShareFrame> get frames => _frames.stream;

  final _events = StreamController<ScreenShareEvent>.broadcast();
  Stream<ScreenShareEvent> get events => _events.stream;

  bool _running = false;
  bool get isRunning => _running;
  ScreenShareDataMode _activeMode = ScreenShareDataMode.standard;
  ScreenShareDataMode get activeMode => _activeMode;

  /// True once [PhoneAutomationService] has been touched and is forwarding
  /// our channel events. We can't install our own handler (the channel
  /// allows only one), so we depend on the automation service for routing.
  bool _routingReady = false;
  void markRoutingReady() {
    _routingReady = true;
  }

  bool get isRoutingReady => _routingReady;

  void _log(String msg) => dev.log('[ScreenShare] $msg', name: 'BrutusAI');

  /// Called by PhoneAutomationService when a `onScreenCapture*` MethodCall
  /// arrives on the shared channel. PhoneAutomationService owns the
  /// MethodCallHandler since it's constructed first; it forwards screen
  /// capture events to us.
  void onChannelCall(MethodCall call) {
    switch (call.method) {
      case 'onScreenCaptureFrame':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        final data = m['data'] as String? ?? '';
        if (data.isEmpty) return;
        final frame = ScreenShareFrame(
          base64Jpeg: data,
          width: (m['width'] as num?)?.toInt() ?? 0,
          height: (m['height'] as num?)?.toInt() ?? 0,
          bytes: (m['bytes'] as num?)?.toInt() ?? 0,
        );
        if (!_frames.isClosed) _frames.add(frame);
        break;
      case 'onScreenCaptureStarted':
        _running = true;
        if (!_events.isClosed) _events.add(const ScreenShareEvent.started());
        break;
      case 'onScreenCaptureStopped':
        _running = false;
        if (!_events.isClosed) _events.add(const ScreenShareEvent.stopped());
        break;
    }
  }

  /// Ask the system for MediaProjection consent and start capturing.
  /// Returns:
  ///   • [ScreenShareStartResult.started] — running, frames will arrive
  ///   • [ScreenShareStartResult.denied]  — user dismissed the dialog
  ///   • [ScreenShareStartResult.busy]    — another consent already in flight
  ///   • [ScreenShareStartResult.failed]  — native error
  Future<ScreenShareStartResult> start({
    ScreenShareDataMode mode = ScreenShareDataMode.standard,
  }) async {
    _activeMode = mode;
    if (!_routingReady) {
      _log('routing not ready — frames may drop until automation service boots');
    }
    try {
      final ok = (await _channel.invokeMethod<bool>(
            'requestScreenCapture',
            {
              'intervalMs': mode.interval.inMilliseconds,
              'jpegQuality': mode.jpegQuality,
              'maxDimension': mode.maxDimension,
            },
          )) ??
          false;
      if (ok) {
        _running = true;
        return ScreenShareStartResult.started;
      }
      return ScreenShareStartResult.denied;
    } on PlatformException catch (e) {
      if (e.code == 'BUSY') return ScreenShareStartResult.busy;
      _log('start failed: ${e.message}');
      return ScreenShareStartResult.failed;
    } catch (e) {
      _log('start failed: $e');
      return ScreenShareStartResult.failed;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopScreenCapture');
    } catch (e) {
      _log('stop failed: $e');
    }
    _running = false;
  }

  Future<bool> queryRunning() async {
    try {
      return (await _channel.invokeMethod<bool>('isScreenCapturing')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Restart with a different mode while sharing is active.
  Future<bool> setMode(ScreenShareDataMode mode) async {
    if (mode == _activeMode && _running) return true;
    if (!_running) {
      _activeMode = mode;
      return true;
    }
    await stop();
    // Small gap so the foreground service has time to wind down before we
    // re-prompt for consent.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final r = await start(mode: mode);
    return r == ScreenShareStartResult.started;
  }

  void dispose() {
    _frames.close();
    _events.close();
  }
}

class ScreenShareFrame {
  final String base64Jpeg;
  final int width;
  final int height;
  final int bytes;

  const ScreenShareFrame({
    required this.base64Jpeg,
    required this.width,
    required this.height,
    required this.bytes,
  });
}

enum ScreenShareStartResult { started, denied, busy, failed }

class ScreenShareEvent {
  final bool started;
  const ScreenShareEvent.started() : started = true;
  const ScreenShareEvent.stopped() : started = false;
}
