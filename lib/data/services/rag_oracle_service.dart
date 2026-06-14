import 'dart:async';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'package:brutus_app/data/services/api_keys.dart';
import 'package:brutus_app/data/services/embeddings_client.dart';
import 'package:brutus_app/data/services/groq_client.dart';
import 'package:brutus_app/data/services/network_guard.dart';
import 'package:brutus_app/data/services/text_chunker.dart';
import 'package:brutus_app/data/services/vector_store.dart';

export 'package:brutus_app/data/services/text_chunker.dart' show TextChunk, TextChunker;
export 'package:brutus_app/data/services/vector_store.dart'
    show
        RagDocument,
        RagChunk,
        RagSearchHit,
        RagSourceKind,
        RagSourceKindX,
        VectorStore;

// ── Streaming events ─────────────────────────────────────────────────────────

sealed class OracleEvent {
  const OracleEvent();
}

class OracleEmbedding extends OracleEvent {
  const OracleEmbedding();
}

class OracleRetrieving extends OracleEvent {
  final int topK;
  const OracleRetrieving(this.topK);
}

class OracleHits extends OracleEvent {
  final List<RagSearchHit> hits;
  const OracleHits(this.hits);
}

class OracleSynthesizing extends OracleEvent {
  final int contextChunks;
  const OracleSynthesizing(this.contextChunks);
}

class OracleToken extends OracleEvent {
  final String delta;
  const OracleToken(this.delta);
}

class OracleComplete extends OracleEvent {
  final OracleAnswer answer;
  const OracleComplete(this.answer);
}

class OracleError extends OracleEvent {
  final String message;
  final bool needsKey;
  final bool offline;
  const OracleError(
    this.message, {
    this.needsKey = false,
    this.offline = false,
  });
}

/// One citation in a final [OracleAnswer].
class RagCitation {
  final int index;
  final String documentId;
  final String documentTitle;
  final int chunkIndex;
  final String snippet;
  final double score;

  const RagCitation({
    required this.index,
    required this.documentId,
    required this.documentTitle,
    required this.chunkIndex,
    required this.snippet,
    required this.score,
  });

  Map<String, dynamic> toMap() => {
        'index': index,
        'documentId': documentId,
        'documentTitle': documentTitle,
        'chunkIndex': chunkIndex,
        'snippet': snippet,
        'score': score,
      };

  factory RagCitation.fromMap(Map map) => RagCitation(
        index: (map['index'] as num?)?.toInt() ?? 0,
        documentId: map['documentId'] as String? ?? '',
        documentTitle: map['documentTitle'] as String? ?? '',
        chunkIndex: (map['chunkIndex'] as num?)?.toInt() ?? 0,
        snippet: map['snippet'] as String? ?? '',
        score: (map['score'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Final result emitted by [OracleComplete].
class OracleAnswer {
  final String id;
  final String question;
  final String markdownAnswer;
  final List<RagCitation> citations;
  final int runMs;
  final DateTime createdAt;

  const OracleAnswer({
    required this.id,
    required this.question,
    required this.markdownAnswer,
    required this.citations,
    required this.runMs,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'question': question,
        'markdownAnswer': markdownAnswer,
        'citations': citations.map((c) => c.toMap()).toList(),
        'runMs': runMs,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory OracleAnswer.fromMap(Map map) => OracleAnswer(
        id: map['id'] as String? ?? const Uuid().v4(),
        question: map['question'] as String? ?? '',
        markdownAnswer: map['markdownAnswer'] as String? ?? '',
        citations: ((map['citations'] as List?) ?? const [])
            .map((c) => RagCitation.fromMap(Map.from(c as Map)))
            .toList(),
        runMs: (map['runMs'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['createdAt'] as num?)?.toInt() ?? 0,
        ),
      );
}

/// Result of a single ingest call — tells the UI how many chunks were
/// indexed and the new document id.
class IngestResult {
  final String documentId;
  final int chunkCount;
  const IngestResult({required this.documentId, required this.chunkCount});
}

/// Brutus Mobile — RAG Oracle service.
///
/// Public API:
///   • [ingestText] — chunk + embed + persist a piece of text
///   • [deleteDocument] — by id
///   • [listDocuments] — read every doc back
///   • [ask] — streamed Q&A pipeline
class RagOracleService {
  RagOracleService({
    EmbeddingsClient? embeddings,
    GroqClient? groq,
    VectorStore? store,
  })  : _embeddings = embeddings ?? EmbeddingsClient(),
        _groq = groq ?? GroqClient(),
        _store = store ?? VectorStore.instance;

  final EmbeddingsClient _embeddings;
  final GroqClient _groq;
  final VectorStore _store;

  void _log(String msg) => dev.log('[Oracle] $msg', name: 'BrutusAI');

  static const _systemPrompt = '''
You are Brutus's Oracle, a precise assistant that answers questions using
ONLY the user's own saved knowledge. Each excerpt is numbered [1], [2], ...
Cite every factual claim with bracket numbers. If the excerpts don't
contain enough information to answer, say so clearly — do not fabricate.

RULES:
- Use ONLY the provided excerpts. Do not draw on outside knowledge.
- Cite with bracket numbers — e.g. "Brutus uses Hive for storage [1][3]."
- Keep paragraphs short. Match the user's tone (casual is fine).
- If the question has multiple parts, answer each.
- 80-300 words.
''';

  // ── Ingestion ───────────────────────────────────────────────────────────

  /// Chunk + embed + persist [text] as a [RagDocument].
  ///
  /// [onProgress] (optional) is called as `(done, total)` so the UI can
  /// show "Indexing 3 of 12..." while embedding batches stream in.
  Future<IngestResult> ingestText({
    required String title,
    required String text,
    required RagSourceKind source,
    String? sourceRef,
    String? documentId,
    void Function(int done, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) {
      throw const FormatException('Cannot ingest empty text.');
    }

    final chunks = TextChunker.chunk(cleaned);
    if (chunks.isEmpty) {
      throw const FormatException('Text could not be chunked.');
    }

    onProgress?.call(0, chunks.length);

    // Embed in one (or a few) batches via the client; report progress as
    // each batch lands.
    final ragChunks = <RagChunk>[];
    const perCall = 100;

    for (var start = 0; start < chunks.length; start += perCall) {
      final batch = chunks.sublist(
        start,
        (start + perCall).clamp(0, chunks.length),
      );
      final vectors = await _embeddings.embedBatch(
        batch.map((c) => c.text).toList(),
        cancelToken: cancelToken,
      );
      for (var i = 0; i < batch.length; i++) {
        ragChunks.add(
          RagChunk(
            index: batch[i].index,
            text: batch[i].text,
            tokenCount: batch[i].tokenCount,
            embedding: vectors[i],
          ),
        );
      }
      onProgress?.call(ragChunks.length, chunks.length);
    }

    final now = DateTime.now();
    final docId = documentId ?? const Uuid().v4();

    // Preserve original createdAt on re-ingest.
    final existing = await _store.getById(docId);
    final doc = RagDocument(
      id: docId,
      title: title.trim().isEmpty ? 'Untitled' : title.trim(),
      source: source,
      sourceRef: sourceRef,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      chunks: ragChunks,
    );
    await _store.upsertDocument(doc);
    _log('ingested ${ragChunks.length} chunks for "$title"');
    return IngestResult(
      documentId: doc.id,
      chunkCount: ragChunks.length,
    );
  }

  Future<void> deleteDocument(String id) => _store.deleteDocument(id);
  Future<List<RagDocument>> listDocuments() => _store.listDocuments();
  Future<int> totalChunks() => _store.totalChunks();
  Future<RagDocument?> getById(String id) => _store.getById(id);

  // ── Query ──────────────────────────────────────────────────────────────

  /// Stream a Q&A run.
  Stream<OracleEvent> ask(
    String question, {
    int topK = 5,
    double minScore = 0.55,
    CancelToken? cancelToken,
  }) async* {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      yield const OracleError('Question is empty.');
      return;
    }

    final stopwatch = Stopwatch()..start();
    final id = const Uuid().v4();

    // Pre-check keys for friendly errors.
    final geminiKey = await ApiKeys.gemini();
    if (geminiKey == null) {
      yield const OracleError(
        'Add your Gemini key in Settings → API Keys.',
        needsKey: true,
      );
      return;
    }
    final groqKey = await ApiKeys.groq();
    if (groqKey == null) {
      yield const OracleError(
        'Add your Groq key in Settings → API Keys.',
        needsKey: true,
      );
      return;
    }

    try {
      await NetworkGuard.ensureOnline();
    } on OfflineException catch (e) {
      yield OracleError(e.toString(), offline: true);
      return;
    }

    yield const OracleEmbedding();
    List<double> queryVec;
    try {
      queryVec = await _embeddings.embed(
        trimmed,
        taskType: EmbeddingTaskType.retrievalQuery,
        cancelToken: cancelToken,
      );
    } on MissingApiKeyException catch (e) {
      yield OracleError(e.toString(), needsKey: true);
      return;
    } on OfflineException catch (e) {
      yield OracleError(e.toString(), offline: true);
      return;
    } on EmbeddingException catch (e) {
      yield OracleError('Embedding failed: $e');
      return;
    }

    yield OracleRetrieving(topK);

    final hits = await _store.search(
      queryVec,
      topK: topK,
      minScore: minScore,
    );
    yield OracleHits(hits);

    if (hits.isEmpty) {
      stopwatch.stop();
      yield OracleComplete(
        OracleAnswer(
          id: id,
          question: trimmed,
          markdownAnswer:
              "I couldn't find anything in your saved knowledge that matches "
              'that question. Try rephrasing, or add a relevant note in '
              'Tools → Oracle → Library.',
          citations: const [],
          runMs: stopwatch.elapsedMilliseconds,
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    yield OracleSynthesizing(hits.length);

    final messages = _buildMessages(trimmed, hits);
    final answerBuf = StringBuffer();

    try {
      await for (final delta in _groq.stream(
        messages: messages,
        temperature: 0.3,
        cancelToken: cancelToken,
      )) {
        if (cancelToken?.isCancelled ?? false) {
          yield const OracleError('Cancelled');
          return;
        }
        answerBuf.write(delta);
        yield OracleToken(delta);
      }
    } on MissingApiKeyException catch (e) {
      yield OracleError(e.toString(), needsKey: true);
      return;
    } on OfflineException catch (e) {
      yield OracleError(e.toString(), offline: true);
      return;
    } on GroqException catch (e) {
      yield OracleError('Synthesis failed: $e');
      return;
    }

    stopwatch.stop();

    final citations = <RagCitation>[];
    for (var i = 0; i < hits.length; i++) {
      citations.add(
        RagCitation(
          index: i + 1,
          documentId: hits[i].documentId,
          documentTitle: hits[i].documentTitle,
          chunkIndex: hits[i].chunkIndex,
          snippet: _excerpt(hits[i].chunkText),
          score: hits[i].score,
        ),
      );
    }

    yield OracleComplete(
      OracleAnswer(
        id: id,
        question: trimmed,
        markdownAnswer: answerBuf.toString().trim(),
        citations: citations,
        runMs: stopwatch.elapsedMilliseconds,
        createdAt: DateTime.now(),
      ),
    );
  }

  // ── Internals ──────────────────────────────────────────────────────────

  List<GroqMessage> _buildMessages(String question, List<RagSearchHit> hits) {
    final buf = StringBuffer()
      ..writeln('Question: $question')
      ..writeln()
      ..writeln('Excerpts:');
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      buf
        ..writeln()
        ..writeln('[${i + 1}] from "${h.documentTitle}" (chunk ${h.chunkIndex}):')
        ..writeln(h.chunkText);
    }
    return [
      GroqMessage('system', _systemPrompt),
      GroqMessage('user', buf.toString()),
    ];
  }

  static String _excerpt(String text, {int maxChars = 240}) {
    if (text.length <= maxChars) return text.trim();
    final cut = text.substring(0, maxChars);
    final lastSpace = cut.lastIndexOf(' ');
    return '${(lastSpace > 60 ? cut.substring(0, lastSpace) : cut).trim()}…';
  }
}
