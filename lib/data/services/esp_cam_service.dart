import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Brutus — ESP32-CAM service ("Brutus's eyes").
///
/// Consumes the MJPEG stream served by `esp32cam_stream.ino` at
/// `http://<ip>:81/stream` and emits individual JPEG frames. Because we parse
/// the frames ourselves (rather than handing the URL to an <img>-style widget),
/// the same frames can be **displayed** in the UI, **forwarded to Gemini**
/// (so Brutus sees through the robot's eyes), and **fed to on-device
/// detection** — all from one connection.
///
/// Endpoints (router mode — phone + cam on the same WiFi, so the phone keeps
/// internet for Gemini):
///   GET /stream   — multipart/x-mixed-replace MJPEG (continuous)
///   GET /capture  — one JPEG (cheap, for on-demand snapshots)
///   GET /status   — JSON {name, ip, flash, psram}
///   GET /flash?on=1|0 — toggle the on-board LED
class EspCamService {
  EspCamService._();
  static final EspCamService instance = EspCamService._();

  http.Client? _client;
  String? _baseUrl; // e.g. http://192.168.1.50:81
  EspCamState _state = EspCamState.stopped;
  bool _stopping = false;

  final _frameController = StreamController<Uint8List>.broadcast();
  final _stateController = StreamController<EspCamState>.broadcast();

  /// Latest JPEG frames from the MJPEG stream.
  Stream<Uint8List> get frameStream => _frameController.stream;

  /// Connection lifecycle.
  Stream<EspCamState> get stateStream => _stateController.stream;

  EspCamState get state => _state;
  bool get isStreaming => _state == EspCamState.streaming;
  String? get baseUrl => _baseUrl;

  // Rolling byte buffer for JPEG marker extraction.
  final List<int> _buf = [];
  static const _maxBuf = 512 * 1024; // safety cap (~QVGA JPEG ≪ this)

  void _log(String m) => dev.log('[EspCam] $m', name: 'BrutusAI');

  /// Accepts "192.168.1.50", "192.168.1.50:81", or a full URL and normalises
  /// it to a scheme+host+port base with no trailing path.
  static String normalizeBase(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    // Drop any known trailing path so we can append our own.
    s = s.replaceAll(RegExp(r'/(stream|capture|status|flash).*$'), '');
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    var uri = Uri.parse(s);
    if (!uri.hasPort) {
      uri = uri.replace(port: 81); // ESP32-CAM stream server default
    }
    return '${uri.scheme}://${uri.host}:${uri.port}';
  }

  // ── Streaming ──────────────────────────────────────────────────────────

  /// Start (or restart) streaming from [urlOrIp]. Auto-reconnects until [stop].
  Future<void> start(String urlOrIp) async {
    await stop();
    final base = normalizeBase(urlOrIp);
    if (base.isEmpty) {
      _setState(EspCamState.error);
      return;
    }
    _baseUrl = base;
    _stopping = false;
    _runLoop(); // fire-and-forget; loop manages its own lifecycle
  }

  Future<void> _runLoop() async {
    while (!_stopping) {
      try {
        _setState(EspCamState.connecting);
        _client = http.Client();
        final req = http.Request('GET', Uri.parse('$_baseUrl/stream'));
        final resp = await _client!
            .send(req)
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }
        _setState(EspCamState.streaming);
        _buf.clear();
        await for (final chunk in resp.stream) {
          if (_stopping) break;
          _parse(chunk);
        }
      } catch (e) {
        if (!_stopping) {
          _log('stream error: $e');
          _setState(EspCamState.error);
        }
      } finally {
        _client?.close();
        _client = null;
      }
      if (_stopping) break;
      await Future.delayed(const Duration(seconds: 2)); // backoff before retry
    }
    _setState(EspCamState.stopped);
  }

  /// Extract complete JPEGs from the byte stream by scanning for the SOI
  /// (0xFFD8) and EOI (0xFFD9) markers — robust regardless of the multipart
  /// boundary formatting.
  void _parse(List<int> chunk) {
    _buf.addAll(chunk);

    while (true) {
      final soi = _indexOfMarker(_buf, 0xD8, 0);
      if (soi < 0) {
        if (_buf.length > _maxBuf) _buf.clear();
        return;
      }
      final eoi = _indexOfMarker(_buf, 0xD9, soi + 2);
      if (eoi < 0) {
        // Incomplete frame — drop junk before SOI to save memory, keep the rest.
        if (soi > 0) _buf.removeRange(0, soi);
        if (_buf.length > _maxBuf) _buf.clear();
        return;
      }
      final frame = Uint8List.fromList(_buf.sublist(soi, eoi + 2));
      _buf.removeRange(0, eoi + 2);
      if (!_frameController.isClosed) _frameController.add(frame);
    }
  }

  /// Find `0xFF <second>` starting at [from].
  int _indexOfMarker(List<int> b, int second, int from) {
    for (int i = from; i < b.length - 1; i++) {
      if (b[i] == 0xFF && b[i + 1] == second) return i;
    }
    return -1;
  }

  Future<void> stop() async {
    _stopping = true;
    try {
      _client?.close(); // interrupts the in-flight await-for
    } catch (_) {}
    _client = null;
    _buf.clear();
    if (_state != EspCamState.stopped) _setState(EspCamState.stopped);
  }

  // ── One-off requests ─────────────────────────────────────────────────────

  /// Grab a single JPEG frame (uses /capture; falls back to nothing on error).
  Future<Uint8List?> capture() async {
    final base = _baseUrl;
    if (base == null) return null;
    try {
      final resp = await http
          .get(Uri.parse('$base/capture'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        return resp.bodyBytes;
      }
    } catch (e) {
      _log('capture failed: $e');
    }
    return null;
  }

  Future<void> setFlash(bool on) async {
    final base = _baseUrl;
    if (base == null) return;
    try {
      await http
          .get(Uri.parse('$base/flash?on=${on ? 1 : 0}'))
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      _log('flash failed: $e');
    }
  }

  /// Quick reachability probe against /status (used before streaming).
  Future<bool> ping(String urlOrIp) async {
    final base = normalizeBase(urlOrIp);
    if (base.isEmpty) return false;
    try {
      final resp = await http
          .get(Uri.parse('$base/status'))
          .timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      // Some builds may not answer /status; fall back to a short stream probe.
      try {
        final c = http.Client();
        final req = http.Request('GET', Uri.parse('$base/capture'));
        final resp = await c.send(req).timeout(const Duration(seconds: 5));
        c.close();
        return resp.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
  }

  void _setState(EspCamState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  void dispose() {
    stop();
    _frameController.close();
    _stateController.close();
  }
}

enum EspCamState { stopped, connecting, streaming, error }
