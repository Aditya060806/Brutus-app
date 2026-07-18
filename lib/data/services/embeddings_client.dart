import 'dart:developer' as dev;

import 'package:dio/dio.dart';

import 'package:brutus_app/core/constants/api_constants.dart';
import 'package:brutus_app/data/services/api_keys.dart';
import 'package:brutus_app/data/services/network_guard.dart';

/// Embedding task types as understood by Gemini's embedContent endpoint.
/// Use [retrievalDocument] when indexing, [retrievalQuery] when asking.
enum EmbeddingTaskType {
  retrievalDocument('RETRIEVAL_DOCUMENT'),
  retrievalQuery('RETRIEVAL_QUERY'),
  semanticSimilarity('SEMANTIC_SIMILARITY');

  const EmbeddingTaskType(this.value);
  final String value;
}

/// Typed exception. Surfaces the Gemini status + error string.
class EmbeddingException implements Exception {
  final int? statusCode;
  final String message;
  const EmbeddingException(this.statusCode, this.message);
  @override
  String toString() => statusCode == null
      ? message
      : 'Embedding error $statusCode: $message';
}

/// Brutus Mobile — Gemini text-embedding-004 client.
///
/// Returns 768-dim float vectors. Uses the same Gemini key as the voice
/// service (secure storage → embedded fallback).
class EmbeddingsClient {
  final Dio _dio;

  EmbeddingsClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              headers: {'Content-Type': 'application/json'},
            ));

  void _log(String msg) => dev.log('[Embed] $msg', name: 'BrutusAI');

  /// Single-text embed.
  Future<List<double>> embed(
    String text, {
    EmbeddingTaskType taskType = EmbeddingTaskType.retrievalDocument,
    CancelToken? cancelToken,
  }) async {
    if (text.trim().isEmpty) {
      throw const EmbeddingException(null, 'Empty text');
    }
    final apiKey = await ApiKeys.gemini();
    if (apiKey == null) throw const MissingApiKeyException('Gemini');
    await NetworkGuard.ensureOnline();

    // Key goes in a header, not the URL — query strings end up in logs,
    // proxies, and DioException messages.
    final url =
        '${ApiConstants.geminiRestBase}/models/${ApiConstants.geminiEmbedModel}:embedContent';

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        url,
        options: Options(headers: {'x-goog-api-key': apiKey}),
        data: {
          'model': 'models/${ApiConstants.geminiEmbedModel}',
          'taskType': taskType.value,
          'content': {
            'parts': [
              {'text': text}
            ],
          },
        },
        cancelToken: cancelToken,
      );
      final values =
          (res.data?['embedding'] as Map?)?['values'] as List? ?? const [];
      return values.map((v) => (v as num).toDouble()).toList(growable: false);
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Batched embed — uses Gemini's batchEmbedContents endpoint. Up to 100
  /// inputs per call. We chunk larger lists internally.
  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    EmbeddingTaskType taskType = EmbeddingTaskType.retrievalDocument,
    CancelToken? cancelToken,
  }) async {
    if (texts.isEmpty) return const [];
    final apiKey = await ApiKeys.gemini();
    if (apiKey == null) throw const MissingApiKeyException('Gemini');
    await NetworkGuard.ensureOnline();

    final url =
        '${ApiConstants.geminiRestBase}/models/${ApiConstants.geminiEmbedModel}:batchEmbedContents';

    const maxPerCall = 100;
    final out = <List<double>>[];

    for (var i = 0; i < texts.length; i += maxPerCall) {
      final batch = texts.sublist(
        i,
        (i + maxPerCall).clamp(0, texts.length),
      );
      _log('batch ${i ~/ maxPerCall + 1}: ${batch.length} texts');

      try {
        final res = await _dio.post<Map<String, dynamic>>(
          url,
          options: Options(headers: {'x-goog-api-key': apiKey}),
          data: {
            'requests': batch
                .map((t) => {
                      'model': 'models/${ApiConstants.geminiEmbedModel}',
                      'taskType': taskType.value,
                      'content': {
                        'parts': [
                          {'text': t}
                        ]
                      },
                    })
                .toList(),
          },
          cancelToken: cancelToken,
        );
        final embeddings =
            (res.data?['embeddings'] as List?) ?? const <dynamic>[];
        for (final e in embeddings) {
          final values = (e as Map)['values'] as List? ?? const [];
          out.add(
            values.map((v) => (v as num).toDouble()).toList(growable: false),
          );
        }
      } on DioException catch (e) {
        throw _toException(e);
      }
    }

    if (out.length != texts.length) {
      throw EmbeddingException(
        null,
        'Embedding count mismatch (got ${out.length}, expected ${texts.length})',
      );
    }
    return out;
  }

  EmbeddingException _toException(DioException e) {
    if (CancelToken.isCancel(e)) {
      return const EmbeddingException(null, 'Cancelled');
    }
    final code = e.response?.statusCode;
    final body = e.response?.data;
    String detail;
    if (body is Map && body['error'] is Map) {
      detail = (body['error'] as Map)['message']?.toString() ?? body.toString();
    } else {
      detail = body?.toString() ?? e.message ?? 'Network error';
    }
    _log('error $code: $detail');
    return EmbeddingException(code, detail);
  }
}
