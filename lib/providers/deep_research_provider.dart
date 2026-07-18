import 'dart:async';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:brutus_app/core/constants/api_constants.dart';
import 'package:brutus_app/data/services/deep_research_service.dart';

export 'package:brutus_app/data/services/deep_research_service.dart'
    show
        DeepResearchDepth,
        DeepResearchDepthX,
        DeepResearchEvent,
        DeepResearchPlanning,
        DeepResearchSearching,
        DeepResearchSearchResult,
        DeepResearchSynthesizing,
        DeepResearchToken,
        DeepResearchComplete,
        DeepResearchError,
        DeepResearchResult,
        TavilySource;

/// Single phase of a research run, used by the UI timeline.
enum ResearchPhase { idle, planning, searching, synthesizing, done, error }

/// Progress + outcome of a single sub-query inside a research run.
class SubQueryProgress {
  final String subQuery;
  final bool searching;
  final List<TavilySource>? sources;
  const SubQueryProgress({
    required this.subQuery,
    this.searching = true,
    this.sources,
  });
  SubQueryProgress copyWith({bool? searching, List<TavilySource>? sources}) =>
      SubQueryProgress(
        subQuery: subQuery,
        searching: searching ?? this.searching,
        sources: sources ?? this.sources,
      );
}

class DeepResearchRunState {
  final String query;
  final DeepResearchDepth depth;
  final ResearchPhase phase;
  final List<SubQueryProgress> subQueries;
  final int dedupedSources;
  final String streamingAnswer;
  final DeepResearchResult? result;
  final String? errorMessage;
  final bool needsKey;
  final bool offline;

  const DeepResearchRunState({
    required this.query,
    required this.depth,
    this.phase = ResearchPhase.idle,
    this.subQueries = const [],
    this.dedupedSources = 0,
    this.streamingAnswer = '',
    this.result,
    this.errorMessage,
    this.needsKey = false,
    this.offline = false,
  });

  DeepResearchRunState copyWith({
    ResearchPhase? phase,
    List<SubQueryProgress>? subQueries,
    int? dedupedSources,
    String? streamingAnswer,
    DeepResearchResult? result,
    String? errorMessage,
    bool? needsKey,
    bool? offline,
    bool clearError = false,
  }) {
    return DeepResearchRunState(
      query: query,
      depth: depth,
      phase: phase ?? this.phase,
      subQueries: subQueries ?? this.subQueries,
      dedupedSources: dedupedSources ?? this.dedupedSources,
      streamingAnswer: streamingAnswer ?? this.streamingAnswer,
      result: result ?? this.result,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      needsKey: needsKey ?? this.needsKey,
      offline: offline ?? this.offline,
    );
  }

  bool get isRunning =>
      phase != ResearchPhase.idle &&
      phase != ResearchPhase.done &&
      phase != ResearchPhase.error;

  /// Read-only view of sub-queries for the UI.
  List<({String subQuery, bool searching, List<TavilySource>? sources})>
      get subQueryView => subQueries
          .map((s) => (
                subQuery: s.subQuery,
                searching: s.searching,
                sources: s.sources,
              ))
          .toList();
}

class DeepResearchProviderState {
  final DeepResearchRunState? current;
  final List<DeepResearchResult> history;

  const DeepResearchProviderState({
    this.current,
    this.history = const [],
  });

  DeepResearchProviderState copyWith({
    DeepResearchRunState? current,
    List<DeepResearchResult>? history,
    bool clearCurrent = false,
  }) {
    return DeepResearchProviderState(
      current: clearCurrent ? null : (current ?? this.current),
      history: history ?? this.history,
    );
  }
}

class DeepResearchNotifier extends StateNotifier<DeepResearchProviderState> {
  DeepResearchNotifier({DeepResearchService? service})
      : _service = service ?? DeepResearchService(),
        super(const DeepResearchProviderState()) {
    _loadHistory();
  }

  final DeepResearchService _service;
  StreamSubscription<DeepResearchEvent>? _runSub;
  CancelToken? _cancelToken;

  static const _historyBoxName = ApiConstants.boxResearchHistory;
  static const _historyKey = 'runs';
  static const _maxHistory = 50;

  void _log(String msg) =>
      dev.log('[DeepResearchProv] $msg', name: 'BrutusAI');

  // ── History persistence ──────────────────────────────────────────────────

  void _loadHistory() {
    try {
      final box = Hive.box(_historyBoxName);
      final raw = (box.get(_historyKey) as List?) ?? const [];
      final loaded = raw
          .map((m) => DeepResearchResult.fromMap(Map.from(m as Map)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(history: loaded);
    } catch (e) {
      _log('history load failed: $e');
    }
  }

  Future<void> _persistHistory(DeepResearchResult result) async {
    try {
      final box = Hive.box(_historyBoxName);
      // Newest first, dedupe by id, cap at _maxHistory.
      final next = <DeepResearchResult>[
        result,
        ...state.history.where((r) => r.id != result.id),
      ].take(_maxHistory).toList();
      await box.put(
        _historyKey,
        next.map((r) => r.toMap()).toList(),
      );
      state = state.copyWith(history: next);
    } catch (e) {
      _log('history persist failed: $e');
    }
  }

  Future<void> deleteHistoryEntry(String id) async {
    try {
      final box = Hive.box(_historyBoxName);
      final next = state.history.where((r) => r.id != id).toList();
      await box.put(_historyKey, next.map((r) => r.toMap()).toList());
      state = state.copyWith(history: next);
    } catch (e) {
      _log('history delete failed: $e');
    }
  }

  Future<void> clearHistory() async {
    try {
      await Hive.box(_historyBoxName).delete(_historyKey);
      state = state.copyWith(history: const []);
    } catch (e) {
      _log('history clear failed: $e');
    }
  }

  // ── Run lifecycle ────────────────────────────────────────────────────────

  /// Cancel any in-flight run.
  Future<void> cancel() async {
    _cancelToken?.cancel('user-cancel');
    _cancelToken = null;
    await _runSub?.cancel();
    _runSub = null;
    final cur = state.current;
    if (cur != null && cur.isRunning) {
      state = state.copyWith(
        current: cur.copyWith(
          phase: ResearchPhase.error,
          errorMessage: 'Cancelled',
        ),
      );
    }
  }

  /// Kick off a new research run. Cancels any prior run first.
  Future<void> run(
    String query, {
    DeepResearchDepth depth = DeepResearchDepth.standard,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    await cancel();

    final token = CancelToken();
    _cancelToken = token;

    state = state.copyWith(
      current: DeepResearchRunState(
        query: trimmed,
        depth: depth,
        phase: ResearchPhase.planning,
      ),
    );

    _runSub = _service
        .run(trimmed, depth: depth, cancelToken: token)
        .listen(_onEvent, onError: _onUnhandledError);
  }

  /// View an existing history entry without re-running.
  void showHistoryEntry(DeepResearchResult result) {
    state = state.copyWith(
      current: DeepResearchRunState(
        query: result.query,
        depth: DeepResearchDepth.standard, // best-effort; not persisted
        phase: ResearchPhase.done,
        subQueries: result.subQueries
            .map(
              (s) => SubQueryProgress(subQuery: s, searching: false),
            )
            .toList(),
        dedupedSources: result.sources.length,
        streamingAnswer: result.markdownAnswer,
        result: result,
      ),
    );
  }

  /// Discard the current run view (back to fresh state, history untouched).
  void clearCurrent() {
    state = state.copyWith(clearCurrent: true);
  }

  void _onEvent(DeepResearchEvent event) {
    final cur = state.current;
    if (cur == null) return;

    if (event is DeepResearchPlanning) {
      state = state.copyWith(
        current: cur.copyWith(
          phase: ResearchPhase.searching,
          subQueries: event.subQueries
              .map((sq) => SubQueryProgress(subQuery: sq))
              .toList(),
        ),
      );
    } else if (event is DeepResearchSearching) {
      // Already represented by initial SubQueryProgress(searching: true).
      // No-op unless the list hasn't been initialised yet.
    } else if (event is DeepResearchSearchResult) {
      final updated = cur.subQueries
          .map((s) => s.subQuery == event.subQuery
              ? s.copyWith(searching: false, sources: event.sources)
              : s)
          .toList();
      state = state.copyWith(current: cur.copyWith(subQueries: updated));
    } else if (event is DeepResearchSynthesizing) {
      state = state.copyWith(
        current: cur.copyWith(
          phase: ResearchPhase.synthesizing,
          dedupedSources: event.totalSources,
        ),
      );
    } else if (event is DeepResearchToken) {
      state = state.copyWith(
        current: cur.copyWith(
          streamingAnswer: cur.streamingAnswer + event.delta,
        ),
      );
    } else if (event is DeepResearchComplete) {
      state = state.copyWith(
        current: cur.copyWith(
          phase: ResearchPhase.done,
          result: event.result,
          streamingAnswer: event.result.markdownAnswer,
          dedupedSources: event.result.sources.length,
        ),
      );
      unawaited(_persistHistory(event.result));
      _runSub?.cancel();
      _runSub = null;
      _cancelToken = null;
    } else if (event is DeepResearchError) {
      state = state.copyWith(
        current: cur.copyWith(
          phase: ResearchPhase.error,
          errorMessage: event.message,
          needsKey: event.needsKey,
          offline: event.offline,
        ),
      );
      _runSub?.cancel();
      _runSub = null;
      _cancelToken = null;
    }
  }

  void _onUnhandledError(Object e, StackTrace st) {
    _log('unhandled stream error: $e\n$st');
    final cur = state.current;
    if (cur != null) {
      state = state.copyWith(
        current: cur.copyWith(
          phase: ResearchPhase.error,
          errorMessage: 'Unexpected error: $e',
        ),
      );
    }
    _runSub?.cancel();
    _runSub = null;
    _cancelToken = null;
  }

  /// Used by the voice-tool runner — runs a research synchronously and
  /// returns a tool-shaped map for `functionResponse`.
  Future<Map<String, dynamic>> runForTool(String query) async {
    await cancel();
    final token = CancelToken();
    _cancelToken = token;
    final trimmed = query.trim();
    state = state.copyWith(
      current: DeepResearchRunState(
        query: trimmed,
        depth: DeepResearchDepth.standard,
        phase: ResearchPhase.planning,
      ),
    );

    DeepResearchResult? final_;
    String? errorMessage;
    final completer = Completer<void>();

    _runSub = _service
        .run(trimmed, cancelToken: token)
        .listen(
      (event) {
        _onEvent(event);
        if (event is DeepResearchComplete) {
          final_ = event.result;
          if (!completer.isCompleted) completer.complete();
        } else if (event is DeepResearchError) {
          errorMessage = event.message;
          if (!completer.isCompleted) completer.complete();
        }
      },
      onError: (e, st) {
        _onUnhandledError(e, st);
        errorMessage = 'Unexpected error: $e';
        if (!completer.isCompleted) completer.complete();
      },
    );

    await completer.future;

    if (final_ != null) {
      // Strip bracket citations for the spoken version.
      final spoken =
          final_!.markdownAnswer.replaceAll(RegExp(r'\s*\[\d+\]'), '');
      return {
        'query': final_!.query,
        'answer': spoken.trim(),
        'sources': final_!.sources
            .asMap()
            .entries
            .map((e) => {
                  'index': e.key + 1,
                  'title': e.value.title,
                  'url': e.value.url,
                  'domain': e.value.domain,
                })
            .toList(),
        'markdown': final_!.markdownAnswer,
        'runMs': final_!.runMs,
      };
    }
    return {'error': errorMessage ?? 'Deep research failed'};
  }

  @override
  void dispose() {
    _cancelToken?.cancel('dispose');
    _runSub?.cancel();
    super.dispose();
  }
}

final deepResearchProvider =
    StateNotifierProvider<DeepResearchNotifier, DeepResearchProviderState>(
  (ref) {
    final n = DeepResearchNotifier();
    ref.onDispose(n.dispose);
    return n;
  },
);
