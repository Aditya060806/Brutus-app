import 'dart:developer' as dev;

import 'package:dio/dio.dart';

import 'package:brutus_app/core/constants/api_constants.dart';
import 'package:brutus_app/data/services/api_keys.dart';
import 'package:brutus_app/data/services/network_guard.dart';

/// One web result from Tavily.
class TavilySource {
  final String title;
  final String url;
  final String content; // snippet (always present)
  final String? rawContent; // full page text (only when requested)
  final double score;

  const TavilySource({
    required this.title,
    required this.url,
    required this.content,
    required this.score,
    this.rawContent,
  });

  /// Domain extracted from [url], used for chip labels.
  String get domain {
    try {
      final host = Uri.parse(url).host;
      return host.startsWith('www.') ? host.substring(4) : host;
    } catch (_) {
      return url;
    }
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'content': content,
        if (rawContent != null) 'rawContent': rawContent,
        'score': score,
      };

  factory TavilySource.fromJson(Map<String, dynamic> json) => TavilySource(
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
        content: json['content'] as String? ?? '',
        rawContent: json['raw_content'] as String? ?? json['rawContent'] as String?,
        score: (json['score'] as num?)?.toDouble() ?? 0.0,
      );
}

/// The full response from a Tavily search.
class TavilyResult {
  final String query;
  final String? answer;
  final List<TavilySource> results;
  final int latencyMs;

  const TavilyResult({
    required this.query,
    required this.results,
    required this.latencyMs,
    this.answer,
  });

  Map<String, dynamic> toJson() => {
        'query': query,
        if (answer != null) 'answer': answer,
        'results': results.map((r) => r.toJson()).toList(),
        'latencyMs': latencyMs,
      };

  factory TavilyResult.fromJson(Map<String, dynamic> json) => TavilyResult(
        query: json['query'] as String? ?? '',
        answer: json['answer'] as String?,
        results: ((json['results'] as List?) ?? const [])
            .map((e) => TavilySource.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 0,
      );
}

/// Typed exception so callers can branch on the HTTP status.
class TavilyException implements Exception {
  final int? statusCode;
  final String message;
  const TavilyException(this.statusCode, this.message);
  @override
  String toString() =>
      statusCode == null ? message : 'Tavily error $statusCode: $message';
}

/// Tavily search depth — `basic` is fast (1-2s), `advanced` is slower but
/// more thorough and is what we use inside Deep Research.
enum TavilyDepth { basic, advanced }

extension on TavilyDepth {
  String get value => name;
}

/// Brutus Mobile — Tavily Search client.
///
/// Used by both the standalone Web Search screen and the Deep Research
/// pipeline. Cancellable via [Dio]'s `CancelToken`.
class TavilyClient {
  final Dio _dio;

  TavilyClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              headers: {'Content-Type': 'application/json'},
            ));

  void _log(String msg) => dev.log('[Tavily] $msg', name: 'BrutusAI');

  /// Run a Tavily search.
  ///
  /// Throws:
  ///   • [MissingApiKeyException] if no key is set or embedded.
  ///   • [OfflineException] if the device is offline.
  ///   • [TavilyException] on any non-2xx response.
  Future<TavilyResult> search(
    String query, {
    int maxResults = 5,
    bool includeAnswer = true,
    bool includeRawContent = false,
    TavilyDepth searchDepth = TavilyDepth.basic,
    CancelToken? cancelToken,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      throw const TavilyException(null, 'Empty query');
    }

    final apiKey = await ApiKeys.tavily();
    if (apiKey == null) throw const MissingApiKeyException('Tavily');

    await NetworkGuard.ensureOnline();

    final stopwatch = Stopwatch()..start();
    _log('search "$trimmed" depth=${searchDepth.value} max=$maxResults');

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiConstants.tavilySearchUrl,
        data: {
          'api_key': apiKey,
          'query': trimmed,
          'max_results': maxResults,
          'include_answer': includeAnswer,
          'include_raw_content': includeRawContent,
          'search_depth': searchDepth.value,
        },
        cancelToken: cancelToken,
      );

      final data = res.data ?? const <String, dynamic>{};
      final results = ((data['results'] as List?) ?? const [])
          .map((e) => TavilySource.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      stopwatch.stop();
      _log('ok — ${results.length} sources in ${stopwatch.elapsedMilliseconds}ms');

      return TavilyResult(
        query: trimmed,
        answer: data['answer'] as String?,
        results: results,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw const TavilyException(null, 'Cancelled');
      }
      final code = e.response?.statusCode;
      final body = e.response?.data;
      final detail = body is Map && body['error'] != null
          ? body['error'].toString()
          : (body?.toString() ?? e.message ?? 'Network error');
      _log('error $code: $detail');
      throw TavilyException(code, detail);
    }
  }
}
