/// Brutus Mobile — Deterministic text chunker for RAG ingestion.
///
/// No tokenizer dependency: tokens are approximated as `chars ÷ 4`, which is
/// a good rule-of-thumb for English / Hinglish text.
///
/// Splitting strategy:
///   1. Prefer paragraph boundaries (`\n\n`)
///   2. Fall back to sentence boundaries (terminator + space + uppercase)
///   3. Hard-split on character count as a last resort
///
/// Adjacent chunks share `overlapTokens` of trailing context to preserve
/// continuity at boundaries — useful for RAG retrieval.
class TextChunk {
  final int index;
  final String text;
  final int tokenCount;
  const TextChunk({
    required this.index,
    required this.text,
    required this.tokenCount,
  });
}

class TextChunker {
  TextChunker._();

  static int tokensFor(String text) => (text.length / 4).ceil();

  /// Chunk [text] into roughly [targetTokens]-sized pieces with
  /// [overlapTokens] of trailing-context overlap.
  static List<TextChunk> chunk(
    String text, {
    int targetTokens = 400,
    int overlapTokens = 50,
  }) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return const [];

    final maxChars = targetTokens * 4;
    final overlapChars = overlapTokens * 4;

    // Step 1 — split on paragraphs.
    final paragraphs = cleaned
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    // Coalesce paragraphs into chunks roughly the target size.
    final raw = <String>[];
    var current = StringBuffer();

    void flush() {
      final s = current.toString().trim();
      if (s.isNotEmpty) raw.add(s);
      current = StringBuffer();
    }

    for (final p in paragraphs) {
      if (p.length > 2 * maxChars) {
        // Oversized paragraph — split into sentences.
        flush();
        final sentences = _splitSentences(p);
        for (final s in sentences) {
          if (s.length > maxChars * 2) {
            // Single huge sentence — hard char-split.
            flush();
            for (var i = 0; i < s.length; i += maxChars) {
              raw.add(
                s.substring(i, (i + maxChars).clamp(0, s.length)).trim(),
              );
            }
          } else if (current.length + s.length + 1 > maxChars) {
            flush();
            current.write(s);
          } else {
            if (current.isNotEmpty) current.write(' ');
            current.write(s);
          }
        }
        flush();
      } else if (current.length + p.length + 2 > maxChars) {
        flush();
        current.write(p);
      } else {
        if (current.isNotEmpty) current.write('\n\n');
        current.write(p);
      }
    }
    flush();

    // Step 2 — apply overlap.
    final chunks = <TextChunk>[];
    for (var i = 0; i < raw.length; i++) {
      final body = raw[i];
      final overlap = i == 0
          ? ''
          : _tail(raw[i - 1], overlapChars);
      final combined = overlap.isEmpty ? body : '$overlap\n\n$body';
      chunks.add(
        TextChunk(
          index: i,
          text: combined,
          tokenCount: tokensFor(combined),
        ),
      );
    }
    return chunks;
  }

  static String _tail(String s, int chars) {
    if (chars <= 0 || s.length <= chars) return s;
    // Try to start the overlap on a sentence boundary so we don't cut a word.
    final start = s.length - chars;
    final breakAt = s.indexOf(RegExp(r'[.!?]\s+[A-Z]'), start);
    if (breakAt > 0 && breakAt < s.length - 30) {
      return s.substring(breakAt + 2).trim();
    }
    final spaceAt = s.indexOf(' ', start);
    if (spaceAt > 0) return s.substring(spaceAt + 1).trim();
    return s.substring(start).trim();
  }

  /// Split a paragraph into sentences. Conservative: only treats `. ` / `? `
  /// / `! ` followed by an uppercase character as a boundary.
  static List<String> _splitSentences(String paragraph) {
    final out = <String>[];
    final regex = RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9"\u0900-\u097F])');
    final parts = paragraph.split(regex);
    for (final p in parts) {
      final t = p.trim();
      if (t.isNotEmpty) out.add(t);
    }
    return out;
  }
}
