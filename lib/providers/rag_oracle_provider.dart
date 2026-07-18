import 'dart:async';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:brutus_app/core/constants/api_constants.dart';
import 'package:brutus_app/data/services/rag_oracle_service.dart';

export 'package:brutus_app/data/services/rag_oracle_service.dart'
    show
        OracleEvent,
        OracleEmbedding,
        OracleRetrieving,
        OracleHits,
        OracleSynthesizing,
        OracleToken,
        OracleComplete,
        OracleError,
        OracleAnswer,
        RagCitation,
        RagDocument,
        RagChunk,
        RagSearchHit,
        RagSourceKind,
        IngestResult;

enum OraclePhase { idle, embedding, retrieving, synthesizing, done, error }

class OracleAskState {
  final String question;
  final OraclePhase phase;
  final List<RagSearchHit> hits;
  final String streamingAnswer;
  final OracleAnswer? answer;
  final String? errorMessage;
  final bool needsKey;
  final bool offline;

  const OracleAskState({
    required this.question,
    this.phase = OraclePhase.idle,
    this.hits = const [],
    this.streamingAnswer = '',
    this.answer,
    this.errorMessage,
    this.needsKey = false,
    this.offline = false,
  });

  OracleAskState copyWith({
    OraclePhase? phase,
    List<RagSearchHit>? hits,
    String? streamingAnswer,
    OracleAnswer? answer,
    String? errorMessage,
    bool? needsKey,
    bool? offline,
    bool clearError = false,
  }) {
    return OracleAskState(
      question: question,
      phase: phase ?? this.phase,
      hits: hits ?? this.hits,
      streamingAnswer: streamingAnswer ?? this.streamingAnswer,
      answer: answer ?? this.answer,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      needsKey: needsKey ?? this.needsKey,
      offline: offline ?? this.offline,
    );
  }

  bool get isRunning =>
      phase != OraclePhase.idle &&
      phase != OraclePhase.done &&
      phase != OraclePhase.error;
}

class OracleIngestProgress {
  final String label;
  final int done;
  final int total;
  const OracleIngestProgress({
    required this.label,
    required this.done,
    required this.total,
  });
}

class OracleProviderState {
  final List<RagDocument> documents;
  final int totalChunks;
  final OracleAskState? current;
  final List<OracleAnswer> history;
  final OracleIngestProgress? ingestProgress;

  const OracleProviderState({
    this.documents = const [],
    this.totalChunks = 0,
    this.current,
    this.history = const [],
    this.ingestProgress,
  });

  OracleProviderState copyWith({
    List<RagDocument>? documents,
    int? totalChunks,
    OracleAskState? current,
    List<OracleAnswer>? history,
    OracleIngestProgress? ingestProgress,
    bool clearCurrent = false,
    bool clearProgress = false,
  }) {
    return OracleProviderState(
      documents: documents ?? this.documents,
      totalChunks: totalChunks ?? this.totalChunks,
      current: clearCurrent ? null : (current ?? this.current),
      history: history ?? this.history,
      ingestProgress:
          clearProgress ? null : (ingestProgress ?? this.ingestProgress),
    );
  }
}

class OracleNotifier extends StateNotifier<OracleProviderState> {
  OracleNotifier({RagOracleService? service})
      : _service = service ?? RagOracleService(),
        super(const OracleProviderState()) {
    _loadHistory();
    _refreshLibrary();
  }

  final RagOracleService _service;
  StreamSubscription<OracleEvent>? _askSub;
  CancelToken? _cancelToken;
  CancelToken? _ingestCancel;

  static const _historyBoxName = ApiConstants.boxOracleHistory;
  static const _historyKey = 'pairs';
  static const _maxHistory = 100;

  void _log(String msg) => dev.log('[OracleProv] $msg', name: 'BrutusAI');

  // ── Library ─────────────────────────────────────────────────────────────

  Future<void> _refreshLibrary() async {
    try {
      final docs = await _service.listDocuments();
      final total = await _service.totalChunks();
      state = state.copyWith(documents: docs, totalChunks: total);
    } catch (e) {
      _log('library refresh failed: $e');
    }
  }

  /// Refresh button on the Library tab.
  Future<void> refreshLibrary() => _refreshLibrary();

  Future<void> deleteDocument(String id) async {
    await _service.deleteDocument(id);
    await _refreshLibrary();
  }

  Future<void> clearAllDocuments() async {
    await VectorStore.instance.clearAll();
    await _refreshLibrary();
  }

  // ── Ingestion ───────────────────────────────────────────────────────────

  /// Cancel any in-flight ingest.
  void cancelIngest() {
    _ingestCancel?.cancel('user-cancel');
    _ingestCancel = null;
  }

  /// Ingest a piece of text. Returns null on success or an error string.
  Future<String?> ingest({
    required String title,
    required String text,
    required RagSourceKind source,
    String? sourceRef,
    String? documentId,
  }) async {
    cancelIngest();
    final token = CancelToken();
    _ingestCancel = token;

    state = state.copyWith(
      ingestProgress: OracleIngestProgress(
        label: title.trim().isEmpty ? 'Untitled' : title.trim(),
        done: 0,
        total: 0,
      ),
    );

    try {
      await _service.ingestText(
        title: title,
        text: text,
        source: source,
        sourceRef: sourceRef,
        documentId: documentId,
        cancelToken: token,
        onProgress: (done, total) {
          state = state.copyWith(
            ingestProgress: OracleIngestProgress(
              label: title.trim().isEmpty ? 'Untitled' : title.trim(),
              done: done,
              total: total,
            ),
          );
        },
      );
      await _refreshLibrary();
      state = state.copyWith(clearProgress: true);
      return null;
    } catch (e) {
      _log('ingest failed: $e');
      state = state.copyWith(clearProgress: true);
      return e.toString();
    } finally {
      _ingestCancel = null;
    }
  }

  // ── Ask flow ────────────────────────────────────────────────────────────

  Future<void> cancelAsk() async {
    _cancelToken?.cancel('user-cancel');
    _cancelToken = null;
    await _askSub?.cancel();
    _askSub = null;
    final cur = state.current;
    if (cur != null && cur.isRunning) {
      state = state.copyWith(
        current: cur.copyWith(
          phase: OraclePhase.error,
          errorMessage: 'Cancelled',
        ),
      );
    }
  }

  Future<void> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;

    await cancelAsk();
    final token = CancelToken();
    _cancelToken = token;

    state = state.copyWith(
      current: OracleAskState(
        question: trimmed,
        phase: OraclePhase.embedding,
      ),
    );

    _askSub = _service
        .ask(trimmed, cancelToken: token)
        .listen(_onEvent, onError: _onUnhandledError);
  }

  void showHistoryEntry(OracleAnswer answer) {
    state = state.copyWith(
      current: OracleAskState(
        question: answer.question,
        phase: OraclePhase.done,
        streamingAnswer: answer.markdownAnswer,
        answer: answer,
      ),
    );
  }

  void clearCurrent() {
    state = state.copyWith(clearCurrent: true);
  }

  void _onEvent(OracleEvent e) {
    final cur = state.current;
    if (cur == null) return;

    if (e is OracleEmbedding) {
      state = state.copyWith(current: cur.copyWith(phase: OraclePhase.embedding));
    } else if (e is OracleRetrieving) {
      state = state.copyWith(current: cur.copyWith(phase: OraclePhase.retrieving));
    } else if (e is OracleHits) {
      state = state.copyWith(current: cur.copyWith(hits: e.hits));
    } else if (e is OracleSynthesizing) {
      state = state.copyWith(
        current: cur.copyWith(phase: OraclePhase.synthesizing),
      );
    } else if (e is OracleToken) {
      state = state.copyWith(
        current: cur.copyWith(
          streamingAnswer: cur.streamingAnswer + e.delta,
        ),
      );
    } else if (e is OracleComplete) {
      state = state.copyWith(
        current: cur.copyWith(
          phase: OraclePhase.done,
          answer: e.answer,
          streamingAnswer: e.answer.markdownAnswer,
        ),
      );
      unawaited(_persistHistory(e.answer));
      _askSub?.cancel();
      _askSub = null;
      _cancelToken = null;
    } else if (e is OracleError) {
      state = state.copyWith(
        current: cur.copyWith(
          phase: OraclePhase.error,
          errorMessage: e.message,
          needsKey: e.needsKey,
          offline: e.offline,
        ),
      );
      _askSub?.cancel();
      _askSub = null;
      _cancelToken = null;
    }
  }

  void _onUnhandledError(Object err, StackTrace st) {
    _log('unhandled stream error: $err\n$st');
    final cur = state.current;
    if (cur != null) {
      state = state.copyWith(
        current: cur.copyWith(
          phase: OraclePhase.error,
          errorMessage: 'Unexpected error: $err',
        ),
      );
    }
    _askSub?.cancel();
    _askSub = null;
    _cancelToken = null;
  }

  // ── History ─────────────────────────────────────────────────────────────

  void _loadHistory() {
    try {
      final box = Hive.box(_historyBoxName);
      final raw = (box.get(_historyKey) as List?) ?? const [];
      final loaded = raw
          .map((m) => OracleAnswer.fromMap(Map.from(m as Map)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(history: loaded);
    } catch (e) {
      _log('history load failed: $e');
    }
  }

  Future<void> _persistHistory(OracleAnswer answer) async {
    try {
      final box = Hive.box(_historyBoxName);
      final next = <OracleAnswer>[
        answer,
        ...state.history.where((a) => a.id != answer.id),
      ].take(_maxHistory).toList();
      await box.put(_historyKey, next.map((a) => a.toMap()).toList());
      state = state.copyWith(history: next);
    } catch (e) {
      _log('history persist failed: $e');
    }
  }

  Future<void> deleteHistoryEntry(String id) async {
    try {
      final box = Hive.box(_historyBoxName);
      final next = state.history.where((a) => a.id != id).toList();
      await box.put(_historyKey, next.map((a) => a.toMap()).toList());
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

  // ── Voice tool entry ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> runForTool(String question) async {
    if (state.documents.isEmpty) {
      return {
        'answer':
            'Your oracle is empty — open Tools → Oracle and add some notes first.',
        'citations': const [],
      };
    }

    await cancelAsk();
    final token = CancelToken();
    _cancelToken = token;
    state = state.copyWith(
      current: OracleAskState(
        question: question.trim(),
        phase: OraclePhase.embedding,
      ),
    );

    final completer = Completer<void>();
    OracleAnswer? final_;
    String? errorMessage;

    _askSub = _service.ask(question, cancelToken: token).listen(
      (e) {
        _onEvent(e);
        if (e is OracleComplete) {
          final_ = e.answer;
          if (!completer.isCompleted) completer.complete();
        } else if (e is OracleError) {
          errorMessage = e.message;
          if (!completer.isCompleted) completer.complete();
        }
      },
      onError: (err, st) {
        _onUnhandledError(err, st);
        errorMessage = 'Unexpected error: $err';
        if (!completer.isCompleted) completer.complete();
      },
    );

    await completer.future;

    if (final_ != null) {
      final spoken =
          final_!.markdownAnswer.replaceAll(RegExp(r'\s*\[\d+\]'), '');
      return {
        'answer': spoken.trim(),
        'citations': final_!.citations
            .map((c) => {
                  'index': c.index,
                  'title': c.documentTitle,
                  'snippet': c.snippet,
                })
            .toList(),
        'runMs': final_!.runMs,
      };
    }
    return {'error': errorMessage ?? 'Oracle failed'};
  }

  @override
  void dispose() {
    _cancelToken?.cancel('dispose');
    _ingestCancel?.cancel('dispose');
    _askSub?.cancel();
    super.dispose();
  }
}

final ragOracleProvider =
    StateNotifierProvider<OracleNotifier, OracleProviderState>(
  (ref) {
    final n = OracleNotifier();
    ref.onDispose(n.dispose);
    return n;
  },
);
