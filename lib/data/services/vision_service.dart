import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io' show File;

import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

/// Bandwidth profile for vision streaming.
///
///   • [standard] — 720p at 2 s/frame (~150-300 KB/frame, ~75-150 KB/s).
///     Best on WiFi.
///   • [low]      — 480p at 4 s/frame (~40-80 KB/frame, ~10-20 KB/s).
///     Roughly 4× less bandwidth, suitable for cellular.
enum VisionDataMode { standard, low }

extension VisionDataModeX on VisionDataMode {
  ResolutionPreset get resolution => switch (this) {
        VisionDataMode.standard => ResolutionPreset.medium,
        VisionDataMode.low => ResolutionPreset.low,
      };

  Duration get frameInterval => switch (this) {
        VisionDataMode.standard => const Duration(seconds: 2),
        VisionDataMode.low => const Duration(seconds: 4),
      };

  String get label => switch (this) {
        VisionDataMode.standard => 'Standard (720p · 2s)',
        VisionDataMode.low => 'Low data (480p · 4s)',
      };
}

/// Brutus Mobile — Vision Service
///
/// Manages a single [CameraController] lifecycle for "vision mode" — sending
/// JPEG frames to Gemini Live so Brutus can see what the camera sees.
///
/// Flow:
///   1. [start] → check permission, list cameras, open the requested lens,
///      begin capturing JPEGs at the [VisionDataMode] cadence
///   2. Each capture → JPEG bytes → base64 → forwarded to [onFrame]
///   3. [stop] → release the controller cleanly
///
/// Edge cases handled:
///   • Permission denied / permanently denied (separate signals)
///   • No camera available on device
///   • Capture in flight when stop is called
///   • Switch lens while running (front ↔ back), preserving data mode
///   • Switch data mode while running (in-place restart with same lens)
///   • Disposal during in-flight initialise / capture
class VisionService {
  static final VisionService instance = VisionService._();
  VisionService._();

  CameraController? _controller;
  Timer? _captureTimer;
  bool _isCapturing = false;
  bool _disposed = false;

  // Cameras list cached after first enumeration.
  List<CameraDescription>? _cameras;
  CameraLensDirection _activeLens = CameraLensDirection.back;
  VisionDataMode _activeMode = VisionDataMode.standard;

  bool get isRunning => _controller != null && _controller!.value.isInitialized;
  CameraLensDirection get activeLens => _activeLens;
  VisionDataMode get activeMode => _activeMode;
  CameraController? get controller => _controller;

  void _log(String msg) => dev.log('[Vision] $msg', name: 'BrutusAI');

  Future<VisionPermissionResult> requestPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return VisionPermissionResult.granted;
    if (status.isPermanentlyDenied) {
      return VisionPermissionResult.permanentlyDenied;
    }
    final result = await Permission.camera.request();
    if (result.isGranted) return VisionPermissionResult.granted;
    if (result.isPermanentlyDenied) {
      return VisionPermissionResult.permanentlyDenied;
    }
    return VisionPermissionResult.denied;
  }

  Future<void> openSettings() => openAppSettings();

  /// Initialise (or re-initialise) the camera with the requested lens and
  /// data mode. Returns the result of the operation.
  Future<VisionStartResult> start({
    required CameraLensDirection lens,
    required void Function(String base64Jpeg) onFrame,
    VisionDataMode mode = VisionDataMode.standard,
  }) async {
    if (_disposed) return VisionStartResult.disposed;

    final perm = await requestPermission();
    if (perm != VisionPermissionResult.granted) {
      return perm == VisionPermissionResult.permanentlyDenied
          ? VisionStartResult.permissionPermanentlyDenied
          : VisionStartResult.permissionDenied;
    }

    try {
      _cameras ??= await availableCameras();
    } catch (e) {
      _log('availableCameras failed: $e');
      return VisionStartResult.failed;
    }
    if (_cameras == null || _cameras!.isEmpty) {
      _log('No cameras on device');
      return VisionStartResult.noCamera;
    }

    final selected = _cameras!.firstWhere(
      (c) => c.lensDirection == lens,
      orElse: () => _cameras!.first,
    );
    _activeLens = selected.lensDirection;
    _activeMode = mode;

    // Tear down any prior controller before opening a new one.
    await _disposeController();
    if (_disposed) return VisionStartResult.disposed;

    final controller = CameraController(
      selected,
      mode.resolution,
      enableAudio: false, // mic is owned by AudioRecorderService
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
    } catch (e) {
      _log('initialize failed: $e');
      try {
        await controller.dispose();
      } catch (_) {}
      return VisionStartResult.failed;
    }

    if (_disposed) {
      try {
        await controller.dispose();
      } catch (_) {}
      return VisionStartResult.disposed;
    }

    _controller = controller;
    _log(
      'Camera ready (${selected.lensDirection.name}, '
      '${mode.label}, preview=${controller.value.previewSize})',
    );

    // Drive the capture loop at the data-mode cadence.
    _captureTimer = Timer.periodic(mode.frameInterval, (_) async {
      await _captureOnce(onFrame);
    });
    // Fire one immediately so the UI doesn't wait for the first interval tick.
    unawaited(_captureOnce(onFrame));

    return VisionStartResult.started;
  }

  /// Switch between front/back lens while running, preserving the active
  /// data mode.
  Future<bool> switchLens(void Function(String base64Jpeg) onFrame) async {
    if (!isRunning) return false;
    final newLens = _activeLens == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final res = await start(
      lens: newLens,
      onFrame: onFrame,
      mode: _activeMode,
    );
    return res == VisionStartResult.started;
  }

  /// Switch the bandwidth profile while running (in-place restart on the
  /// currently active lens). No-op if vision isn't running.
  Future<bool> switchMode(
    VisionDataMode mode,
    void Function(String base64Jpeg) onFrame,
  ) async {
    if (!isRunning) return false;
    if (mode == _activeMode) return true;
    final res = await start(
      lens: _activeLens,
      onFrame: onFrame,
      mode: mode,
    );
    return res == VisionStartResult.started;
  }

  Future<void> _captureOnce(void Function(String base64Jpeg) onFrame) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_isCapturing) return; // skip overlapping captures
    _isCapturing = true;
    XFile? shot;
    try {
      shot = await c.takePicture();
      final bytes = await shot.readAsBytes();
      if (_disposed) return;
      // Encode and forward
      final b64 = base64Encode(bytes);
      onFrame(b64);
    } catch (e) {
      _log('capture failed: $e');
    } finally {
      _isCapturing = false;
      // takePicture() writes the JPEG to a temp file on every call. At
      // 30 captures/min this fills the app cache fast — delete after we've
      // read the bytes. Best-effort; failures here are non-fatal.
      if (shot != null) {
        try {
          await File(shot.path).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> stop() async {
    _log('Stopping vision...');
    _captureTimer?.cancel();
    _captureTimer = null;
    await _disposeController();
  }

  Future<void> _disposeController() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      // Wait for any in-flight capture before disposing
      while (_isCapturing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      await c.dispose();
    } catch (e) {
      _log('controller dispose error: $e');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
  }
}

enum VisionPermissionResult { granted, denied, permanentlyDenied }

enum VisionStartResult {
  started,
  permissionDenied,
  permissionPermanentlyDenied,
  noCamera,
  failed,
  disposed,
}
