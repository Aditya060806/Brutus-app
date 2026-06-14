import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

/// Brutus — on-device OCR.
///
/// Two ways in:
///
///   1. [recognizeFromCamera] — opens the back camera, snaps a still, runs
///      ML Kit's text recognizer, returns the consolidated text. This is the
///      voice-tool path: "read this for me" / "what does that sign say".
///
///   2. [recognizeFromFile] — same recognizer but on an arbitrary image path.
///      Useful for "read this screenshot" workflows once we wire up the
///      gallery picker (Phase 5+).
///
/// The recognizer is created lazily and reused; `dispose()` is called from
/// the Riverpod provider lifecycle.
class ScreenOcrService {
  ScreenOcrService._();
  static final ScreenOcrService instance = ScreenOcrService._();

  TextRecognizer? _recognizer;
  TextRecognizer _r() {
    return _recognizer ??=
        TextRecognizer(script: TextRecognitionScript.latin);
  }

  void _log(String msg) => dev.log('[OCR] $msg', name: 'BrutusAI');

  /// Open a temporary back-camera session, snap one frame, run OCR.
  Future<OcrResult> recognizeFromCamera() async {
    // Permission gate. Camera permission may already be granted from the
    // Vision feature, but the call is cheap and idempotent.
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      return const OcrResult(
        text: '',
        blockCount: 0,
        success: false,
        error: 'Camera permission denied.',
      );
    }

    CameraController? controller;
    String? tempPath;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        return const OcrResult(
          text: '',
          blockCount: 0,
          success: false,
          error: 'No camera found on this device.',
        );
      }
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      controller = CameraController(
        cam,
        // High enough for legible text, low enough for fast capture.
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      // Lock auto-focus + exposure briefly so the still is sharp.
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setExposureMode(ExposureMode.auto);
      } catch (_) {}
      // Tiny settle delay so AF / AE can do their work before the shutter.
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final shot = await controller.takePicture();
      tempPath = shot.path;

      final input = InputImage.fromFilePath(shot.path);
      final recognized = await _r().processImage(input);

      final blockCount = recognized.blocks.length;
      return OcrResult(
        text: recognized.text.trim(),
        blockCount: blockCount,
        success: true,
      );
    } on CameraException catch (e) {
      _log('camera failure: ${e.code} ${e.description}');
      return OcrResult(
        text: '',
        blockCount: 0,
        success: false,
        error: 'Camera error: ${e.description ?? e.code}',
      );
    } catch (e) {
      _log('OCR failure: $e');
      return OcrResult(
        text: '',
        blockCount: 0,
        success: false,
        error: 'OCR failed: $e',
      );
    } finally {
      try {
        await controller?.dispose();
      } catch (_) {}
      // Clean up the temp JPEG. We've already extracted the text; the file
      // serves no further purpose and the OS won't reliably GC the cache dir.
      if (tempPath != null) {
        try {
          await File(tempPath).delete();
        } catch (_) {}
      }
    }
  }

  Future<OcrResult> recognizeFromFile(String path) async {
    try {
      final input = InputImage.fromFilePath(path);
      final r = await _r().processImage(input);
      return OcrResult(
        text: r.text.trim(),
        blockCount: r.blocks.length,
        success: true,
      );
    } catch (e) {
      _log('OCR (file) failure: $e');
      return OcrResult(
        text: '',
        blockCount: 0,
        success: false,
        error: '$e',
      );
    }
  }

  Future<void> dispose() async {
    try {
      await _recognizer?.close();
    } catch (_) {}
    _recognizer = null;
  }
}

class OcrResult {
  final String text;
  final int blockCount;
  final bool success;
  final String? error;

  const OcrResult({
    required this.text,
    required this.blockCount,
    required this.success,
    this.error,
  });
}
