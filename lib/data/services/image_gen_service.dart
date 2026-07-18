import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:brutus_app/data/services/api_keys.dart';
import 'package:brutus_app/data/services/network_guard.dart';

/// Available text-to-image models routed via HuggingFace's `hf-inference`
/// provider on `router.huggingface.co`.
///
/// Default is FLUX.1-schnell to mirror the desktop Brutus implementation —
/// fast, reliable on the free tier, good at "imagine X" prompts.
enum HfImageModel {
  fluxSchnell(
    id: 'black-forest-labs/FLUX.1-schnell',
    label: 'FLUX.1 schnell',
    description: 'Default · fastest · stylised illustrations and concept art',
  ),
  stableDiffusionXl(
    id: 'stabilityai/stable-diffusion-xl-base-1.0',
    label: 'SDXL Base 1.0',
    description: 'Crisp photoreal · landscapes and portraits',
  ),
  realisticVision(
    id: 'SG161222/Realistic_Vision_V6.0_B1_noVAE',
    label: 'Realistic Vision',
    description: 'Photorealistic faces and lifestyle scenes',
  );

  const HfImageModel({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

/// Typed exception. Surfaces the HF status + body so callers can show e.g.
/// the "model loading" cold-start message verbatim.
class ImageGenException implements Exception {
  final int? statusCode;
  final String message;
  const ImageGenException(this.statusCode, this.message);
  @override
  String toString() => statusCode == null
      ? message
      : 'Image generation error $statusCode: $message';
}

/// Brutus Mobile — HuggingFace text-to-image client.
///
/// Mirrors the protocol of the official `@huggingface/inference` SDK that
/// the desktop Brutus uses:
///
///   `POST https://router.huggingface.co/hf-inference/models/{modelId}`
///   - `Authorization: Bearer {token}`
///   - `Content-Type: application/json`
///   - Body: `{"inputs": "{prompt}"}`
///
/// Response: image bytes (Content-Type: image/png|jpeg) on success,
/// JSON `{error: ...}` on failure.
///
/// Cold starts (HTTP 503) are retried once internally — same as the SDK.
class ImageGenService {
  ImageGenService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 120),
            ));

  final Dio _dio;

  static const _routerBase = 'https://router.huggingface.co/hf-inference';

  void _log(String msg) => dev.log('[ImageGen] $msg', name: 'BrutusAI');

  /// Generate one image. Returns the raw PNG/JPEG bytes.
  Future<Uint8List> generate(
    String prompt, {
    HfImageModel model = HfImageModel.fluxSchnell,
    String? negativePrompt,
    CancelToken? cancelToken,
  }) async {
    final clean = prompt.trim();
    if (clean.isEmpty) {
      throw const ImageGenException(null, 'Prompt is empty');
    }
    final apiKey = await ApiKeys.huggingFace();
    if (apiKey == null) throw const MissingApiKeyException('HuggingFace');
    await NetworkGuard.ensureOnline();

    _log('generate "$clean" model=${model.id}');

    return _attempt(
      prompt: clean,
      model: model,
      negativePrompt: negativePrompt,
      apiKey: apiKey,
      cancelToken: cancelToken,
      isRetry: false,
    );
  }

  Future<Uint8List> _attempt({
    required String prompt,
    required HfImageModel model,
    required String? negativePrompt,
    required String apiKey,
    required CancelToken? cancelToken,
    required bool isRetry,
  }) async {
    final url = '$_routerBase/models/${model.id}';

    // Body shape matches @huggingface/inference SDK exactly.
    final body = <String, dynamic>{
      'inputs': prompt,
      if (negativePrompt != null && negativePrompt.trim().isNotEmpty)
        'parameters': {'negative_prompt': negativePrompt.trim()},
    };

    try {
      final res = await _dio.post<List<int>>(
        url,
        data: body,
        options: Options(
          // We ask for bytes; the router still emits JSON on errors and Dio
          // hands those through as a List<int> we decode below.
          responseType: ResponseType.bytes,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            // No `Accept` header — matches the SDK. The router decides what to
            // return based on the model's task; sending Accept: image/png
            // sometimes confuses the router into returning 415.
          },
          // We handle 503 ourselves with our retry rather than letting Dio
          // throw on it.
          validateStatus: (status) => status != null && status < 600,
        ),
        cancelToken: cancelToken,
      );

      final status = res.statusCode ?? 0;
      final contentType = (res.headers.value('content-type') ?? '').toLowerCase();
      final raw = res.data ?? const [];

      // Cold start — retry once. The SDK does the same.
      if (status == 503 && !isRetry) {
        _log('503 cold start — retrying once after a short wait');
        await Future.delayed(const Duration(seconds: 6));
        return _attempt(
          prompt: prompt,
          model: model,
          negativePrompt: negativePrompt,
          apiKey: apiKey,
          cancelToken: cancelToken,
          isRetry: true,
        );
      }

      if (status >= 200 && status < 300) {
        // Successful response. Could be image bytes OR JSON with a base64
        // payload (some providers return the latter). Dispatch based on
        // Content-Type.
        if (contentType.startsWith('application/json')) {
          final json = _decodeJson(raw);
          if (json == null) {
            throw const ImageGenException(null, 'Empty JSON response');
          }
          // Look for a few known wrappings.
          final dataList = json['data'];
          if (dataList is List && dataList.isNotEmpty) {
            final first = dataList.first;
            if (first is Map && first['b64_json'] is String) {
              return base64Decode(first['b64_json'] as String);
            }
          }
          if (json['error'] != null) {
            final msg = json['error'].toString();
            if (msg.toLowerCase().contains('loading') && !isRetry) {
              await Future.delayed(const Duration(seconds: 6));
              return _attempt(
                prompt: prompt,
                model: model,
                negativePrompt: negativePrompt,
                apiKey: apiKey,
                cancelToken: cancelToken,
                isRetry: true,
              );
            }
            throw ImageGenException(status, msg);
          }
          throw ImageGenException(status,
              'Unexpected JSON response: ${json.keys.join(", ")}');
        }
        // Binary image — just return the bytes.
        if (raw.isEmpty) {
          throw const ImageGenException(null, 'Empty image response');
        }
        return Uint8List.fromList(raw);
      }

      // Non-2xx — surface a useful message. HF tends to return JSON.
      final detail = _decodeError(raw, contentType, status);
      _log('error $status: $detail');
      throw ImageGenException(status, detail);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw const ImageGenException(null, 'Cancelled');
      }
      // No response at all — DNS, TLS, server unreachable.
      final detail = e.message ?? 'No response (${e.type.name})';
      _log('dio error: $detail');
      throw ImageGenException(null, detail);
    }
  }

  Map<String, dynamic>? _decodeJson(List<int> raw) {
    if (raw.isEmpty) return null;
    try {
      final str = utf8.decode(raw, allowMalformed: true);
      final v = jsonDecode(str);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  String _decodeError(List<int> raw, String contentType, int status) {
    if (raw.isEmpty) return 'HTTP $status with empty body';
    if (contentType.startsWith('application/json')) {
      final json = _decodeJson(raw);
      if (json != null) {
        final err = json['error'];
        if (err is String) {
          if (err.toLowerCase().contains('loading')) {
            return 'Model is warming up (Free Tier). Try again in 20 seconds.';
          }
          return err;
        }
        if (err != null) return err.toString();
        if (json['message'] is String) return json['message'] as String;
      }
    }
    try {
      final str = utf8.decode(raw, allowMalformed: true);
      return str.length > 240 ? '${str.substring(0, 240)}…' : str;
    } catch (_) {
      return 'Could not decode response (HTTP $status)';
    }
  }
}
