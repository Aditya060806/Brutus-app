import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:brutus_app/core/constants/api_constants.dart';

/// Source kind of a [RagDocument].
enum RagSourceKind { note, pasted, imported }

extension RagSourceKindX on RagSourceKind {
  String get id => name;
  static RagSourceKind from(String? raw) =>
      RagSourceKind.values.firstWhere(
        (k) => k.id == raw,
        orElse: () => RagSourceKind.pasted,
      );
}

/// One chunk of a [RagDocument]. Embedding is stored inline so
/// document + embeddings stay atomically consistent.
class RagChunk {
  final int index;
  final String text;
  final int tokenCount;
  final List<double> embedding;

  const RagChunk({
    required this.index,
    required this.text,
    required this.tokenCount,
    required this.embedding,
  });

  Map<String, dynamic> toMap() => {
        'index': index,
        'text': text,
        'tokenCount': tokenCount,
        'embedding': embedding,
      };

  factory RagChunk.fromMap(Map map) => RagChunk(
        index: (map['index'] as num?)?.toInt() ?? 0,
        text: map['text'] as String? ?? '',
        tokenCount: (map['tokenCount'] as num?)?.toInt() ?? 0,
        embedding: (map['embedding'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList(growable: false) ??
            const [],
      );
}

/// One indexed document. Persisted in the `rag_documents` Hive box.
class RagDocument {
  final String id;
  final String title;
  final RagSourceKind source;
  final String? sourceRef; // note id, file path, or null for pasted
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<RagChunk> chunks;

  const RagDocument({
    required this.id,
    required this.title,
    required this.source,
    required this.sourceRef,
    required this.createdAt,
    required this.updatedAt,
    required this.chunks,
  });

  int get totalTokens =>
      chunks.fold<int>(0, (sum, c) => sum + c.tokenCount);

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'source': source.id,
        'sourceRef': sourceRef,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'chunks': chunks.map((c) => c.toMap()).toList(),
      };

  factory RagDocument.fromMap(Map map) => RagDocument(
        id: map['id'] as String? ?? const Uuid().v4(),
        title: map['title'] as String? ?? 'Untitled',
        source: RagSourceKindX.from(map['source'] as String?),
        sourceRef: map['sourceRef'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['createdAt'] as num?)?.toInt() ?? 0,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['updatedAt'] as num?)?.toInt() ?? 0,
        ),
        chunks: ((map['chunks'] as List?) ?? const [])
            .map((c) => RagChunk.fromMap(Map.from(c as Map)))
            .toList(),
      );
}

/// One retrieval hit returned from [VectorStore.search].
class RagSearchHit {
  final String documentId;
  final String documentTitle;
  final int chunkIndex;
  final String chunkText;
  final double score; // cosine similarity in [-1, 1]

  const RagSearchHit({
    required this.documentId,
    required this.documentTitle,
    required this.chunkIndex,
    required this.chunkText,
    required this.score,
  });
}

/// Brutus Mobile — On-device vector store backed by Hive.
///
/// Exact cosine search over every chunk. Plenty fast for the ≤5,000-chunk
/// scale we expect during Phase 3. ANN indexing is a Phase-5 problem.
///
/// Single-Future-chain serialisation prevents simultaneous writes from
/// racing each other.
class VectorStore {
  VectorStore._();
  static final VectorStore instance = VectorStore._();

  Future<void> _writeChain = Future.value();

  void _log(String msg) => dev.log('[VectorStore] $msg', name: 'BrutusAI');

  Box _box() => Hive.box(ApiConstants.boxRagDocuments);

  /// Insert or replace a document keyed by id.
  Future<void> upsertDocument(RagDocument doc) async {
    _writeChain = _writeChain.then((_) async {
      try {
        await _box().put(doc.id, doc.toMap());
      } catch (e) {
        _log('upsert failed: $e');
        rethrow;
      }
    });
    return _writeChain;
  }

  /// Delete by id. No-op if missing.
  Future<void> deleteDocument(String id) async {
    _writeChain = _writeChain.then((_) async {
      try {
        await _box().delete(id);
      } catch (e) {
        _log('delete failed: $e');
        rethrow;
      }
    });
    return _writeChain;
  }

  /// Wipe everything. Used by the screen's "Clear all" action.
  Future<void> clearAll() async {
    _writeChain = _writeChain.then((_) async {
      try {
        await _box().clear();
      } catch (e) {
        _log('clear failed: $e');
        rethrow;
      }
    });
    return _writeChain;
  }

  /// Read all documents. Sorted by `updatedAt` descending so the UI list
  /// shows newest at the top by default.
  Future<List<RagDocument>> listDocuments() async {
    final box = _box();
    final docs = box.values
        .map((v) => RagDocument.fromMap(Map.from(v as Map)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return docs;
  }

  Future<RagDocument?> getById(String id) async {
    final raw = _box().get(id);
    if (raw == null) return null;
    return RagDocument.fromMap(Map.from(raw as Map));
  }

  /// Total chunk count across all docs. Cheap — no embedding traversal.
  Future<int> totalChunks() async {
    var total = 0;
    for (final v in _box().values) {
      final chunks = (v as Map)['chunks'] as List?;
      total += chunks?.length ?? 0;
    }
    return total;
  }

  /// Cosine search. Iterates every chunk in memory. At ≤5K chunks this
  /// completes well under 250ms on a 2024 mid-range Android.
  Future<List<RagSearchHit>> search(
    List<double> queryEmbedding, {
    int topK = 5,
    double minScore = 0.55,
  }) async {
    if (queryEmbedding.isEmpty) return const [];
    final qNorm = _norm(queryEmbedding);
    if (qNorm == 0) return const [];

    // Heap-style: keep a sorted top-K list as we go.
    final hits = <RagSearchHit>[];

    for (final raw in _box().values) {
      final doc = RagDocument.fromMap(Map.from(raw as Map));
      for (final c in doc.chunks) {
        if (c.embedding.length != queryEmbedding.length) continue;
        final score = _cosine(queryEmbedding, c.embedding, qNorm);
        if (score < minScore) continue;
        if (hits.length < topK) {
          hits.add(
            RagSearchHit(
              documentId: doc.id,
              documentTitle: doc.title,
              chunkIndex: c.index,
              chunkText: c.text,
              score: score,
            ),
          );
          hits.sort((a, b) => b.score.compareTo(a.score));
        } else if (score > hits.last.score) {
          hits[hits.length - 1] = RagSearchHit(
            documentId: doc.id,
            documentTitle: doc.title,
            chunkIndex: c.index,
            chunkText: c.text,
            score: score,
          );
          hits.sort((a, b) => b.score.compareTo(a.score));
        }
      }
    }
    return hits;
  }

  // ── Math ────────────────────────────────────────────────────────────────

  static double _norm(List<double> v) {
    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    return math.sqrt(sum);
  }

  static double _cosine(List<double> a, List<double> b, double aNorm) {
    var dot = 0.0;
    var bSum = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      bSum += b[i] * b[i];
    }
    final bNorm = math.sqrt(bSum);
    if (bNorm == 0) return 0.0;
    return dot / (aNorm * bNorm);
  }
}
