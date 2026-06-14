import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/providers/rag_oracle_provider.dart';

/// Bottom sheet showing every chunk inside a single [RagDocument].
class ChunkSheet extends StatelessWidget {
  final RagDocument document;
  final int? highlightIndex;

  const ChunkSheet({
    super.key,
    required this.document,
    this.highlightIndex,
  });

  static Future<void> show(
    BuildContext context, {
    required RagDocument document,
    int? highlightIndex,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ChunkSheet(
        document: document,
        highlightIndex: highlightIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Icon(_icon(document.source), size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      document.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _Pill(
                    label: '${document.chunks.length} chunk${document.chunks.length == 1 ? '' : 's'}',
                  ),
                  const SizedBox(width: 6),
                  _Pill(
                    label: '${document.totalTokens} tok',
                    monospace: true,
                  ),
                  const SizedBox(width: 6),
                  _Pill(
                    label: document.source.name,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
            const Divider(height: 18),
            Expanded(
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                itemCount: document.chunks.length,
                itemBuilder: (context, i) {
                  final c = document.chunks[i];
                  final highlight = highlightIndex == c.index;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: highlight
                          ? AppColors.primarySurface
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: highlight
                            ? AppColors.primary
                            : AppColors.border,
                        width: highlight ? 1.0 : 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _Pill(label: '#${c.index}'),
                            const SizedBox(width: 6),
                            _Pill(label: '${c.tokenCount} tok', monospace: true),
                            const Spacer(),
                            Text(
                              '${c.embedding.length} dim',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textTertiary,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          c.text,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _icon(RagSourceKind k) {
    switch (k) {
      case RagSourceKind.note:
        return Iconsax.note;
      case RagSourceKind.pasted:
        return Iconsax.text;
      case RagSourceKind.imported:
        return Iconsax.document_upload;
    }
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color? color;
  final bool monospace;
  const _Pill({required this.label, this.color, this.monospace = false});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c,
          fontFamily: monospace ? 'monospace' : null,
        ),
      ),
    );
  }
}
