import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';

import 'package:brutus_app/core/constants/api_constants.dart';
import 'package:brutus_app/data/services/api_keys.dart';
import 'package:brutus_app/data/services/network_guard.dart';

/// One message in a Groq chat conversation.
class GroqMessage {
  final String role; // 'system' | 'user' | 'assistant'
  final String content;
  const GroqMessage(this.role, this.content);
  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// Typed Groq exception — surfaces the HTTP status + the API's own error
/// string so the UI can show "model not found" verbatim.
class GroqException implements Exception {
  final int? statusCode;
  final String message;
  const GroqException(this.statusCode, this.message);
  @override
  String toString() =>
      statusCode == null ? message : 'Groq error $statusCode: $message';
}

/// Brutus Mobile — Groq chat-completions client.
///
/// Used for:
///   • Deep-Research planner + synthesis (streaming)
///   • RAG Oracle synthesis (streaming)
///
/// Default model is `llama-3.3-70b-versatile`. The streaming variant returns
/// incremental token deltas parsed from OpenAI-style SSE.
class GroqClient {
  final Dio _dio;

  GroqClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              headers: {'Content-Type': 'application/json'},
            ));

  void _log(String msg) => dev.log('[Groq] $msg', name: 'BrutusAI');

  /// Non-streaming completion. Returns the full assistant content string.
  Future<String> complete({
    required List<GroqMessage> messages,
    String model = ApiConstants.groqDefaultModel,
    double temperature = 0.4,
    int? maxTokens,
    CancelToken? cancelToken,
  }) async {
    final apiKey = await ApiKeys.groq();
    if (apiKey == null) throw const MissingApiKeyException('Groq');
    await NetworkGuard.ensureOnline();

    final stopwatch = Stopwatch()..start();
    _log('complete model=$model msgs=${messages.length} temp=$temperature');

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiConstants.groqChatCompletions,
        data: {
          'model': model,
          'messages': messages.map((m) => m.toJson()).toList(),
          'temperature': temperature,
          'max_tokens': ?maxTokens,
          'stream': false,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
        ),
        cancelToken: cancelToken,
      );
      final choices = (res.data?['choices'] as List?) ?? const [];
      if (choices.isEmpty) {
        throw const GroqException(null, 'Groq returned no choices');
      }
      final msg = (choices.first as Map)['message'] as Map?;
      final content = msg?['content']?.toString() ?? '';
      stopwatch.stop();
      _log('ok — ${content.length} chars in ${stopwatch.elapsedMilliseconds}ms');
      return content;
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Streaming completion — yields each token delta as it arrives.
  ///
  /// Cancellation propagates through [cancelToken]. The stream ends with
  /// either a clean close, a [GroqException], or an [OfflineException]
  /// before the first request fires.
  Stream<String> stream({
    required List<GroqMessage> messages,
    String model = ApiConstants.groqDefaultModel,
    double temperature = 0.4,
    int? maxTokens,
    CancelToken? cancelToken,
  }) async* {
    final apiKey = await ApiKeys.groq();
    if (apiKey == null) throw const MissingApiKeyException('Groq');
    await NetworkGuard.ensureOnline();

    _log('stream model=$model msgs=${messages.length}');

    final Response<ResponseBody> res;
    try {
      res = await _dio.post<ResponseBody>(
        ApiConstants.groqChatCompletions,
        data: {
          'model': model,
          'messages': messages.map((m) => m.toJson()).toList(),
          'temperature': temperature,
          'max_tokens': ?maxTokens,
          'stream': true,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw _toException(e);
    }

    final body = res.data;
    if (body == null) {
      throw const GroqException(null, 'No response body');
    }

    // Buffer because SSE events are delimited by \n\n but each TCP chunk
    // can split mid-event.
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

        // An SSE event is one or more `field: value` lines. We only care
        // about `data:` lines for OpenAI-compatible streams.
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
          } catch (e) {
            _log('SSE parse skipped: $e');
            // Tolerate one bad event; servers occasionally emit garbage.
          }
        }
      }
    }
  }

  GroqException _toException(DioException e) {
    if (CancelToken.isCancel(e)) return const GroqException(null, 'Cancelled');
    final code = e.response?.statusCode;
    final body = e.response?.data;
    String detail;
    if (body is Map) {
      final err = body['error'];
      if (err is Map && err['message'] != null) {
        detail = err['message'].toString();
      } else if (err != null) {
        detail = err.toString();
      } else {
        detail = body.toString();
      }
    } else {
      detail = body?.toString() ?? e.message ?? 'Network error';
    }
    _log('error $code: $detail');
    return GroqException(code, detail);
  }
}
