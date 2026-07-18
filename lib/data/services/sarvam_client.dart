import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:brutus_app/core/constants/api_constants.dart';
import 'package:brutus_app/data/services/api_keys.dart';
import 'package:brutus_app/data/services/groq_client.dart' show GroqMessage;
import 'package:brutus_app/data/services/network_guard.dart';

/// Typed Sarvam error surfacing the HTTP status + API message.
class SarvamException implements Exception {
  final int? statusCode;
  final String message;
  const SarvamException(this.statusCode, this.message);
  @override
  String toString() =>
      statusCode == null ? message : 'Sarvam error $statusCode: $message';
}

/// Brutus — Sarvam AI client (Indic STT · TTS · LLM).
///
/// Phase 1 uses:
///   • Chat completions (`sarvam-30b` / `sarvam-105b`) — OpenAI-compatible,
///     same message shape as Groq, so we reuse [GroqMessage].
///   • Text-to-speech (Bulbul) — returns base64 WAV which we decode + resample
///     to 24 kHz mono PCM so it plays through the existing AudioTrack pipeline.
///
/// Auth: chat uses `Authorization: Bearer <key>`; speech uses the
/// `api-subscription-key` header. The key comes from secure storage.
class SarvamClient {
  final Dio _dio;

  SarvamClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
            ));

  void _log(String m) => dev.log('[Sarvam] $m', name: 'BrutusAI');

  Future<String> _key() async {
    final k = await ApiKeys.sarvam();
    if (k == null) throw const MissingApiKeyException('Sarvam');
    return k;
  }

  // ── Chat / LLM ─────────────────────────────────────────────────────────────

  Future<String> complete({
    required List<GroqMessage> messages,
    String model = ApiConstants.sarvamDefaultChatModel,
    double temperature = 0.4,
    int? maxTokens,
    CancelToken? cancelToken,
  }) async {
    final key = await _key();
    await NetworkGuard.ensureOnline();
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiConstants.sarvamChatCompletions,
        data: {
          'model': model,
          'messages': messages.map((m) => m.toJson()).toList(),
          'temperature': temperature,
          'max_tokens': ?maxTokens,
          'stream': false,
        },
        options: Options(headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        }),
        cancelToken: cancelToken,
      );
      final choices = (res.data?['choices'] as List?) ?? const [];
      if (choices.isEmpty) {
        throw const SarvamException(null, 'Sarvam returned no choices');
      }
      final msg = (choices.first as Map)['message'] as Map?;
      return msg?['content']?.toString() ?? '';
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  Stream<String> stream({
    required List<GroqMessage> messages,
    String model = ApiConstants.sarvamDefaultChatModel,
    double temperature = 0.4,
    int? maxTokens,
    CancelToken? cancelToken,
  }) async* {
    final key = await _key();
    await NetworkGuard.ensureOnline();
    _log('stream model=$model msgs=${messages.length}');

    final Response<ResponseBody> res;
    try {
      res = await _dio.post<ResponseBody>(
        ApiConstants.sarvamChatCompletions,
        data: {
          'model': model,
          'messages': messages.map((m) => m.toJson()).toList(),
          'temperature': temperature,
          'max_tokens': ?maxTokens,
          'stream': true,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw _toException(e);
    }

    final body = res.data;
    if (body == null) throw const SarvamException(null, 'No response body');

    final buffer = StringBuffer();
    await for (final chunk in body.stream) {
      if (cancelToken?.isCancelled ?? false) return;
      buffer.write(utf8.decode(chunk, allowMalformed: true));
      while (true) {
        final raw = buffer.toString();
        final boundary = raw.indexOf('\n\n');
        if (boundary < 0) break;
        final event = raw.substring(0, boundary);
        buffer
          ..clear()
          ..write(raw.substring(boundary + 2));
        for (final line in event.split('\n')) {
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload.isEmpty) continue;
          if (payload == '[DONE]') return;
          try {
            final json = jsonDecode(payload) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;
            final delta = (choices.first as Map)['delta'] as Map?;
            final content = delta?['content']?.toString();
            if (content != null && content.isNotEmpty) yield content;
          } catch (_) {/* tolerate one bad SSE event */}
        }
      }
    }
  }

  // ── Text-to-speech (Bulbul) ─────────────────────────────────────────────────

  /// Synthesize [text] and return **24 kHz mono 16-bit PCM** bytes, ready to
  /// hand to [AudioPlaybackService.queueChunk] (base64). Handles Sarvam's WAV
  /// container and resamples if the model's rate differs from 24 kHz.
  Future<Uint8List> synthesizeToPcm24k({
    required String text,
    String speaker = 'anushka',
    String languageCode = 'en-IN',
    String model = ApiConstants.sarvamTtsModel,
    double pace = 1.0,
  }) async {
    final key = await _key();
    await NetworkGuard.ensureOnline();

    // Bulbul caps at ~2500 chars/request.
    final input = text.length > 2400 ? text.substring(0, 2400) : text;

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiConstants.sarvamTtsUrl,
        data: {
          'text': input,
          'target_language_code': languageCode,
          'speaker': speaker,
          'model': model,
          'pace': pace,
          'speech_sample_rate': ApiConstants.sarvamTtsSampleRate,
        },
        options: Options(headers: {
          'api-subscription-key': key,
          'Content-Type': 'application/json',
        }),
      );
      final audios = res.data?['audios'] as List?;
      if (audios == null || audios.isEmpty) {
        throw const SarvamException(null, 'Sarvam TTS returned no audio');
      }
      final wav = base64Decode(audios.first.toString());
      return _wavToPcm24kMono(wav);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  // ── WAV → 24 kHz mono PCM ────────────────────────────────────────────────────

  Uint8List _wavToPcm24kMono(Uint8List wav) {
    int rd16(int o) => wav[o] | (wav[o + 1] << 8);
    int rd32(int o) =>
        wav[o] | (wav[o + 1] << 8) | (wav[o + 2] << 16) | (wav[o + 3] << 24);

    int channels = 1, sampleRate = ApiConstants.sarvamTtsSampleRate, bits = 16;
    Uint8List? data;

    // Walk RIFF chunks (skip the 12-byte RIFF/WAVE header).
    if (wav.length > 12 &&
        String.fromCharCodes(wav.sublist(0, 4)) == 'RIFF') {
      int pos = 12;
      while (pos + 8 <= wav.length) {
        final id = String.fromCharCodes(wav.sublist(pos, pos + 4));
        final size = rd32(pos + 4);
        final bodyStart = pos + 8;
        if (id == 'fmt ' && bodyStart + 16 <= wav.length) {
          channels = rd16(bodyStart + 2);
          sampleRate = rd32(bodyStart + 4);
          bits = rd16(bodyStart + 14);
        } else if (id == 'data') {
          final end =
              (bodyStart + size <= wav.length) ? bodyStart + size : wav.length;
          data = Uint8List.sublistView(wav, bodyStart, end);
          break;
        }
        pos = bodyStart + size + (size & 1); // word-align
      }
    }

    // Fallback: treat everything after a canonical 44-byte header as PCM.
    data ??= wav.length > 44 ? Uint8List.sublistView(wav, 44) : wav;
    if (bits != 16 || channels < 1) channels = 1;

    // Decode → mono int16 samples.
    final frames = data.length ~/ (2 * channels);
    final mono = List<int>.filled(frames, 0);
    for (int i = 0; i < frames; i++) {
      int sum = 0;
      for (int c = 0; c < channels; c++) {
        final o = (i * channels + c) * 2;
        int s = data[o] | (data[o + 1] << 8);
        if (s > 32767) s -= 65536;
        sum += s;
      }
      mono[i] = (sum / channels).round();
    }

    const target = 24000;
    if (sampleRate == target) return _int16ToBytes(mono);

    // Linear resample to 24 kHz.
    final ratio = target / sampleRate;
    final outLen = (mono.length * ratio).floor();
    final out = List<int>.filled(outLen, 0);
    for (int i = 0; i < outLen; i++) {
      final srcPos = i / ratio;
      final i0 = srcPos.floor();
      final i1 = (i0 + 1 < mono.length) ? i0 + 1 : i0;
      final frac = srcPos - i0;
      out[i] = (mono[i0] * (1 - frac) + mono[i1] * frac).round();
    }
    return _int16ToBytes(out);
  }

  Uint8List _int16ToBytes(List<int> samples) {
    final b = Uint8List(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      int s = samples[i].clamp(-32768, 32767);
      if (s < 0) s += 65536;
      b[i * 2] = s & 0xFF;
      b[i * 2 + 1] = (s >> 8) & 0xFF;
    }
    return b;
  }

  SarvamException _toException(DioException e) {
    if (CancelToken.isCancel(e)) return const SarvamException(null, 'Cancelled');
    final code = e.response?.statusCode;
    final body = e.response?.data;
    String detail;
    if (body is Map) {
      final err = body['error'];
      detail = (err is Map ? err['message']?.toString() : err?.toString()) ??
          body.toString();
    } else {
      detail = body?.toString() ?? e.message ?? 'Network error';
    }
    _log('error $code: $detail');
    return SarvamException(code, detail);
  }
}
