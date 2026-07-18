import 'dart:async';
import 'dart:developer' as dev;
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

/// Brutus — Eye Tracking service ("the phone's back camera becomes the robot's
/// eyes"). It runs the **back camera** as a live image stream, detects faces
/// on-device with ML Kit, and emits the position of the closest face as a
/// normalized point (0..1 in the upright/portrait frame). The robot provider
/// maps that point to the eye servos so Brutus's eyes turn toward whoever the
/// camera is looking at.
///
/// Coordinate convention emitted (upright portrait frame):
///   cx = 0.0 → target at the LEFT of the view, 1.0 → RIGHT
///   cy = 0.0 → TOP of the view,                1.0 → BOTTOM
class EyeTrackingService {
  EyeTrackingService._();
  static final EyeTrackingService instance = EyeTrackingService._();

  CameraController? _controller;
  CameraDescription? _description;
  FaceDetector? _detector;

  bool _isDetecting = false;
  bool _stopping = false;
  DateTime _lastProcess = DateTime(2000);
  static const _minInterval = Duration(milliseconds: 90); // ~11 fps detection

  EyeTrackingState _state = EyeTrackingState.stopped;

  final _targetController = StreamController<EyeTarget>.broadcast();
  final _stateController = StreamController<EyeTrackingState>.broadcast();

  Stream<EyeTarget> get targetStream => _targetController.stream;
  Stream<EyeTrackingState> get stateStream => _stateController.stream;
  EyeTrackingState get state => _state;

  /// Exposed so the UI can show a live [CameraPreview]. Null until running.
  CameraController? get controller =>
      (_controller != null && _controller!.value.isInitialized)
          ? _controller
          : null;

  void _log(String m) => dev.log('[EyeTrack] $m', name: 'BrutusAI');

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<bool> start() async {
    if (_state == EyeTrackingState.running ||
        _state == EyeTrackingState.starting) {
      return true;
    }
    _stopping = false;
    _setState(EyeTrackingState.starting);

    // Camera permission.
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      _log('camera permission denied');
      _setState(EyeTrackingState.error);
      return false;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setState(EyeTrackingState.error);
        return false;
      }
      _description = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableContours: false,
          enableClassification: false,
          enableLandmarks: false,
          enableTracking: false,
          minFaceSize: 0.1,
        ),
      );

      _controller = CameraController(
        _description!,
        ResolutionPreset.low, // low res = fast detection, plenty for tracking
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21, // single-plane → easy InputImage
      );
      await _controller!.initialize();
      if (_stopping) {
        await stop();
        return false;
      }
      await _controller!.startImageStream(_onFrame);

      _setState(EyeTrackingState.running);
      _log('started (back camera)');
      return true;
    } catch (e) {
      _log('start failed: $e');
      await stop();
      _setState(EyeTrackingState.error);
      return false;
    }
  }

  Future<void> stop() async {
    _stopping = true;
    try {
      if (_controller != null) {
        if (_controller!.value.isStreamingImages) {
          await _controller!.stopImageStream();
        }
        await _controller!.dispose();
      }
    } catch (e) {
      _log('stop error: $e');
    }
    _controller = null;
    try {
      await _detector?.close();
    } catch (_) {}
    _detector = null;
    _isDetecting = false;
    if (_state != EyeTrackingState.stopped) {
      _setState(EyeTrackingState.stopped);
    }
  }

  // ── Frame processing ───────────────────────────────────────────────────────

  Future<void> _onFrame(CameraImage image) async {
    if (_stopping || _isDetecting || _detector == null) return;
    final now = DateTime.now();
    if (now.difference(_lastProcess) < _minInterval) return;
    _lastProcess = now;
    _isDetecting = true;

    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final faces = await _detector!.processImage(input);
      if (_stopping) return;

      if (faces.isEmpty) {
        _emit(const EyeTarget(hasFace: false, cx: 0.5, cy: 0.5));
        return;
      }

      // Pick the largest (closest) face.
      Face largest = faces.first;
      double maxArea = 0;
      for (final f in faces) {
        final a = f.boundingBox.width * f.boundingBox.height;
        if (a > maxArea) {
          maxArea = a;
          largest = f;
        }
      }

      // The upright frame dimensions (width/height swap for 90/270 rotation).
      final rotation = _rotation(image);
      final rotated = rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;
      final w = (rotated ? image.height : image.width).toDouble();
      final h = (rotated ? image.width : image.height).toDouble();

      final box = largest.boundingBox;
      final cx = (box.center.dx / w).clamp(0.0, 1.0);
      final cy = (box.center.dy / h).clamp(0.0, 1.0);

      _emit(EyeTarget(hasFace: true, cx: cx, cy: cy));
    } catch (e) {
      _log('detect error: $e');
    } finally {
      _isDetecting = false;
    }
  }

  InputImageRotation _rotation(CameraImage image) {
    final sensor = _description?.sensorOrientation ?? 90;
    return InputImageRotationValue.fromRawValue(sensor) ??
        InputImageRotation.rotation90deg;
  }

  InputImage? _toInputImage(CameraImage image) {
    final plane = image.planes.isNotEmpty ? image.planes.first : null;
    if (plane == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotation(image),
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  void _emit(EyeTarget t) {
    if (!_targetController.isClosed) _targetController.add(t);
  }

  void _setState(EyeTrackingState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  void dispose() {
    stop();
    _targetController.close();
    _stateController.close();
  }
}

enum EyeTrackingState { stopped, starting, running, error }

/// A detected target position in the upright/portrait camera frame.
class EyeTarget {
  final bool hasFace;
  final double cx; // 0=left, 1=right
  final double cy; // 0=top,  1=bottom
  const EyeTarget({required this.hasFace, required this.cx, required this.cy});
}
