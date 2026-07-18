import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'package:brutus_app/data/services/api_keys.dart';
import 'package:brutus_app/data/services/groq_client.dart';
import 'package:brutus_app/data/services/network_guard.dart';
import 'package:brutus_app/data/services/sarvam_client.dart';
import 'package:brutus_app/data/tools/tavily_client.dart';
import 'package:brutus_app/providers/ai_engine_provider.dart';

/// Re-export shared types so providers can import a single file.
export 'package:brutus_app/data/tools/tavily_client.dart' show TavilySource;

/// Bandwidth/quality preset for a deep-research run.
///
/// `quick` → 1 sub-query (effectively basic web search synthesis).
/// `standard` → 3 sub-queries (default).
/// `deep` → 5 sub-queries (slower but more thorough).
enum DeepResearchDepth { quick, standard, deep }

extension DeepResearchDepthX on DeepResearchDepth {
  int get subQueryCount => switch (this) {
        DeepResearchDepth.quick => 1,
        DeepResearchDepth.standard => 3,
        DeepResearchDepth.deep => 5,
      };

  String get label => switch (this) {
        DeepResearchDepth.quick => 'Quick',
        DeepResearchDepth.standard => 'Standard',
        DeepResearchDepth.deep => 'Deep',
      };
}

// ── Streaming events ─────────────────────────────────────────────────────────

sealed class DeepResearchEvent {
  const DeepResearchEvent();
}

class DeepResearchPlanning extends DeepResearchEvent {
  final List<String> subQueries;
  const DeepResearchPlanning(this.subQueries);
}

class DeepResearchSearching extends DeepResearchEvent {
  final String subQuery;
  const DeepResearchSearching(this.subQuery);
}

class DeepResearchSearchResult extends DeepResearchEvent {
  final String subQuery;
  final List<TavilySource> sources;
  const DeepResearchSearchResult(this.subQuery, this.sources);
}

class DeepResearchSynthesizing extends DeepResearchEvent {
  final int totalSources;
  const DeepResearchSynthesizing(this.totalSources);
}

class DeepResearchToken extends DeepResearchEvent {
  final String delta;
  const DeepResearchToken(this.delta);
}

class DeepResearchComplete extends DeepResearchEvent {
  final DeepResearchResult result;
  const DeepResearchComplete(this.result);
}

class DeepResearchError extends DeepResearchEvent {
  final String message;
  final bool needsKey;
  final bool offline;
  const DeepResearchError(
    this.message, {
    this.needsKey = false,
    this.offline = false,
  });
}

// ── Final result ─────────────────────────────────────────────────────────────

class DeepResearchResult {
  final String id;
  final String query;
  final List<String> subQueries;
  final List<TavilySource> sources;
  final String markdownAnswer;
  final int runMs;
  final DateTime createdAt;

  const DeepResearchResult({
    required this.id,
    required this.query,
    required this.subQueries,
    required this.sources,
    required this.markdownAnswer,
    required this.runMs,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'query': query,
        'subQueries': subQueries,
        'sources': sources.map((s) => s.toJson()).toList(),
        'markdownAnswer': markdownAnswer,
        'runMs': runMs,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory DeepResearchResult.fromMap(Map map) => DeepResearchResult(
        id: map['id'] as String? ?? const Uuid().v4(),
        query: map['query'] as String? ?? '',
        subQueries:
            (map['subQueries'] as List?)?.cast<String>() ?? const <String>[],
        sources: ((map['sources'] as List?) ?? const [])
            .map((e) => TavilySource.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        markdownAnswer: map['markdownAnswer'] as String? ?? '',
        runMs: (map['runMs'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['createdAt'] as num?)?.toInt() ?? 0,
        ),
      );
}

// ── Service ──────────────────────────────────────────────────────────────────

/// Brutus Mobile — Deep Research pipeline.
///
/// Plan → Search (parallel) → Dedupe → Synthesize (streaming).
/// Emits a typed event stream that both the screen and the voice tool
/// subscribe to.
class DeepResearchService {
  DeepResearchService({
    TavilyClient? tavily,
    GroqClient? groq,
    SarvamClient? sarvam,
  })  : _tavily = tavily ?? TavilyClient(),
        _groq = groq ?? GroqClient(),
        _sarvam = sarvam ?? SarvamClient();

  final TavilyClient _tavily;
  final GroqClient _groq;
  final SarvamClient _sarvam;

  /// Route synthesis/planning through the user-selected text-LLM engine.
  Stream<String> _llmStream({
    required List<GroqMessage> messages,
    double temperature = 0.4,
    CancelToken? cancelToken,
  }) {
    if (AiEnginePrefs.llmEngine() == LlmEngine.sarvam) {
      return _sarvam.stream(
        messages: messages,
        temperature: temperature,
        cancelToken: cancelToken,
      );
    }
    return _groq.stream(
      messages: messages,
      temperature: temperature,
      cancelToken: cancelToken,
    );
  }

  Future<String> _llmComplete({
    required List<GroqMessage> messages,
    double temperature = 0.4,
    CancelToken? cancelToken,
  }) {
    if (AiEnginePrefs.llmEngine() == LlmEngine.sarvam) {
      return _sarvam.complete(
        messages: messages,
        temperature: temperature,
        cancelToken: cancelToken,
      );
    }
    return _groq.complete(
      messages: messages,
      temperature: temperature,
      cancelToken: cancelToken,
    );
  }

  void _log(String msg) => dev.log('[DeepResearch] $msg', name: 'BrutusAI');

  static const _plannerSystemPrompt = '''
You are a research planner. Decompose the user's topic into focused
sub-queries that, together, would give a journalist enough material to write
a definitive 500-word piece.

RULES:
- Output MUST be valid JSON of exactly this shape: {"sub_queries": [string, string, ...]}.
- Provide EXACTLY {{N}} sub-queries.
- Each sub-query is a short search-engine string, no commentary.
- Cover distinct angles (background, current state, key players, opposing
  views, future outlook) — do not duplicate.
- Do NOT include any text outside the JSON object.
''';

  static const _synthesisSystemPrompt = '''
You are Brutus, a sharp research analyst. Using ONLY the numbered sources
provided, write a clear, well-organised answer to the user's question.

RULES:
- Cite every factual claim with bracket numbers like [1], [2], [3] referring
  to the source list. Multiple citations per claim allowed.
- Do not invent facts; if the sources don't cover something, say so.
- Note explicitly when sources contradict each other.
- Write in plain prose, with short paragraphs.
- Open with a 1-2 sentence summary, then go deeper.
- Do NOT include a "Sources" section — the UI renders the list separately.
- 350-700 words.
''';

  /// Run a deep-research pipeline. Returns a stream of events. Cancellation
  /// is honoured via [cancelToken].
  Stream<DeepResearchEvent> run(
    String query, {
    DeepResearchDepth depth = DeepResearchDepth.standard,
    CancelToken? cancelToken,
  }) async* {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      yield const DeepResearchError('Query is empty.');
      return;
    }

    final stopwatch = Stopwatch()..start();
    final id = const Uuid().v4();

    // Pre-check keys so we surface a friendly error instead of a generic one.
    final tavilyKey = await ApiKeys.tavily();
    if (tavilyKey == null) {
      yield const DeepResearchError(
        'Add your Tavily key in Settings → API Keys.',
        needsKey: true,
      );
      return;
    }
    final llmEngine = AiEnginePrefs.llmEngine();
    final llmKey = llmEngine == LlmEngine.sarvam
        ? await ApiKeys.sarvam()
        : await ApiKeys.groq();
    if (llmKey == null) {
      yield DeepResearchError(
        'Add your ${llmEngine == LlmEngine.sarvam ? 'Sarvam' : 'Groq'} key '
        'in Settings → API Keys.',
        needsKey: true,
      );
      return;
    }

    try {
      await NetworkGuard.ensureOnline();
    } on OfflineException catch (e) {
      yield DeepResearchError(e.toString(), offline: true);
      return;
    }

    // ── 1. Plan ────────────────────────────────────────────────────────────
    List<String> subQueries;
    try {
      subQueries = await _plan(trimmed, depth, cancelToken);
    } on MissingApiKeyException catch (e) {
      yield DeepResearchError(e.toString(), needsKey: true);
      return;
    } on OfflineException catch (e) {
      yield DeepResearchError(e.toString(), offline: true);
      return;
    } on GroqException catch (e) {
      yield DeepResearchError('Planner failed: $e');
      return;
    } catch (e) {
      // Fall back to a single sub-query equal to the original.
      _log('plan failed, falling back to single query: $e');
      subQueries = [trimmed];
    }

    if (cancelToken?.isCancelled ?? false) {
      yield const DeepResearchError('Cancelled');
      return;
    }
    yield DeepResearchPlanning(subQueries);

    // ── 2. Search (parallel, real-time event emission) ─────────────────────
    //
    // We launch every Tavily call concurrently and pipe their `Searching`
    // and `SearchResult` events through a StreamController so they reach
    // the UI the instant they happen — no buffer-and-flush.
    final perQueryResults = <String, List<TavilySource>>{};
    final searchEvents = StreamController<DeepResearchEvent>();

    final searchFutures = <Future<void>>[];
    for (final sq in subQueries) {
      searchFutures.add(() async {
        searchEvents.add(DeepResearchSearching(sq));
        try {
          final r = await _tavily.search(
            sq,
            includeAnswer: false,
            maxResults: 5,
            searchDepth: TavilyDepth.advanced,
            cancelToken: cancelToken,
          );
          perQueryResults[sq] = r.results;
          searchEvents.add(DeepResearchSearchResult(sq, r.results));
        } catch (e) {
          _log('sub-query "$sq" failed: $e');
          perQueryResults[sq] = const [];
          searchEvents.add(DeepResearchSearchResult(sq, const []));
        }
      }());
    }

    // Close the controller once all parallel work finishes; this lets the
    // `await for` below terminate cleanly.
    unawaited(Future.wait(searchFutures).whenComplete(searchEvents.close));

    await for (final e in searchEvents.stream) {
      yield e;
    }

    if (cancelToken?.isCancelled ?? false) {
      yield const DeepResearchError('Cancelled');
      return;
    }

    // ── 3. Dedupe ──────────────────────────────────────────────────────────
    final dedupedByUrl = <String, TavilySource>{};
    for (final list in perQueryResults.values) {
      for (final s in list) {
        if (s.url.isEmpty) continue;
        final existing = dedupedByUrl[s.url];
        if (existing == null || s.score > existing.score) {
          dedupedByUrl[s.url] = s;
        }
      }
    }
    final allSources = dedupedByUrl.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (allSources.isEmpty) {
      yield const DeepResearchError(
        'No web sources found. Try a more specific query.',
      );
      return;
    }

    // ── 4. Synthesize (streaming) ──────────────────────────────────────────
    yield DeepResearchSynthesizing(allSources.length);

    final messages = _buildSynthesisMessages(trimmed, allSources);
    final answerBuf = StringBuffer();

    try {
      await for (final delta in _llmStream(
        messages: messages,
        temperature: 0.4,
        cancelToken: cancelToken,
      )) {
        if (cancelToken?.isCancelled ?? false) {
          yield const DeepResearchError('Cancelled');
          return;
        }
        answerBuf.write(delta);
        yield DeepResearchToken(delta);
      }
    } on MissingApiKeyException catch (e) {
      yield DeepResearchError(e.toString(), needsKey: true);
      return;
    } on OfflineException catch (e) {
      yield DeepResearchError(e.toString(), offline: true);
      return;
    } on GroqException catch (e) {
      yield DeepResearchError('Synthesis failed: $e');
      return;
    } on SarvamException catch (e) {
      yield DeepResearchError('Synthesis failed: $e');
      return;
    }

    stopwatch.stop();
    final result = DeepResearchResult(
      id: id,
      query: trimmed,
      subQueries: subQueries,
      sources: allSources,
      markdownAnswer: answerBuf.toString().trim(),
      runMs: stopwatch.elapsedMilliseconds,
      createdAt: DateTime.now(),
    );
    yield DeepResearchComplete(result);
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Future<List<String>> _plan(
    String query,
    DeepResearchDepth depth,
    CancelToken? cancelToken,
  ) async {
    final n = depth.subQueryCount;
    if (n == 1) return [query]; // Quick mode skips planning.

    final system = _plannerSystemPrompt.replaceAll('{{N}}', '$n');
    final raw = await _llmComplete(
      messages: [
        GroqMessage('system', system),
        GroqMessage('user', query),
      ],
      temperature: 0.2,
      cancelToken: cancelToken,
    );

    // Some providers wrap JSON in ``` blocks. Strip that defensively.
    var clean = raw.trim();
    if (clean.startsWith('```')) {
      clean = clean.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      final end = clean.lastIndexOf('```');
      if (end >= 0) clean = clean.substring(0, end).trim();
    }

    try {
      final parsed = jsonDecode(clean);
      if (parsed is Map) {
        final list = parsed['sub_queries'];
        if (list is List) {
          final out = list
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (out.isNotEmpty) return out.take(n).toList();
        }
      }
    } catch (e) {
      _log('plan JSON parse failed: $e');
    }
    // Fallback: single query.
    return [query];
  }

  List<GroqMessage> _buildSynthesisMessages(
    String query,
    List<TavilySource> sources,
  ) {
    final buf = StringBuffer()
      ..writeln('Question: $query')
      ..writeln()
      ..writeln('Sources:');
    for (var i = 0; i < sources.length; i++) {
      final s = sources[i];
      buf
        ..writeln()
        ..writeln('[${i + 1}] ${s.title} — ${s.domain}')
        ..writeln(s.url)
        ..writeln(s.content);
    }
    return [
      GroqMessage('system', _synthesisSystemPrompt),
      GroqMessage('user', buf.toString()),
    ];
  }
}
