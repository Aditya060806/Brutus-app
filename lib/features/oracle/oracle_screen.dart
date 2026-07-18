import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/shared_widgets.dart';
import 'package:brutus_app/data/services/vector_store.dart';
import 'package:brutus_app/features/oracle/widgets/chunk_sheet.dart';
import 'package:brutus_app/features/oracle/widgets/ingest_sheet.dart';
import 'package:brutus_app/providers/rag_oracle_provider.dart';

class OracleScreen extends ConsumerStatefulWidget {
  const OracleScreen({super.key});

  @override
  ConsumerState<OracleScreen> createState() => _OracleScreenState();
}

class _OracleScreenState extends ConsumerState<OracleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _questionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _questionCtrl.dispose();
    super.dispose();
  }

  void _ask() {
    final q = _questionCtrl.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    ref.read(ragOracleProvider.notifier).ask(q);
  }

  Future<void> _openIngestSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const IngestSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ragOracleProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('RAG Oracle'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textTertiary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Ask'),
            Tab(text: 'Library'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) {
          if (_tabs.index != 1) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: _openIngestSheet,
            icon: const Icon(Iconsax.add),
            label: const Text('Add'),
          );
        },
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _AskTab(
            state: state,
            controller: _questionCtrl,
            onAsk: _ask,
            onJumpToLibrary: () => _tabs.animateTo(1),
          ),
          _LibraryTab(state: state, onAdd: _openIngestSheet),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ask tab
// ─────────────────────────────────────────────────────────────────────────────

class _AskTab extends ConsumerWidget {
  final OracleProviderState state;
  final TextEditingController controller;
  final VoidCallback onAsk;
  final VoidCallback onJumpToLibrary;

  const _AskTab({
    required this.state,
    required this.controller,
    required this.onAsk,
    required this.onJumpToLibrary,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = state.current;
    final isRunning = cur?.isRunning ?? false;
    final isEmpty = state.documents.isEmpty;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        _StatsRow(
          documents: state.documents.length,
          chunks: state.totalChunks,
          onTap: onJumpToLibrary,
        ),
        const SizedBox(height: 14),
        _QuestionCard(
          controller: controller,
          onAsk: onAsk,
          isRunning: isRunning,
          isEmpty: isEmpty,
          onCancel: () => ref.read(ragOracleProvider.notifier).cancelAsk(),
        ),
        if (isEmpty) ...[
          const SizedBox(height: 22),
          _EmptyKnowledgeBase(onAdd: () {
            // FAB lives only on Library tab; jump there.
            onJumpToLibrary();
          }),
        ],
        if (cur != null) ...[
          const SizedBox(height: 22),
          if (cur.errorMessage != null)
            _ErrorBox(state: cur)
          else
            _AnswerView(state: cur, onCitationTap: (c) async {
              final doc = await ref
                  .read(ragOracleProvider.notifier)
                  ._serviceGetById(c.documentId);
              if (doc != null && context.mounted) {
                await ChunkSheet.show(
                  context,
                  document: doc,
                  highlightIndex: c.chunkIndex,
                );
              }
            }),
        ],
        if (state.history.isNotEmpty) ...[
          const SizedBox(height: 24),
          const SectionHeader(
            title: 'Recent Q&A',
            subtitle: 'Tap to revisit',
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: state.history.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final a = state.history[i];
                return _HistoryCard(
                  answer: a,
                  onTap: () => ref
                      .read(ragOracleProvider.notifier)
                      .showHistoryEntry(a),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int documents;
  final int chunks;
  final VoidCallback onTap;

  const _StatsRow({
    required this.documents,
    required this.chunks,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Stat(
          icon: Iconsax.book,
          label: 'Documents',
          value: '$documents',
          onTap: onTap,
        ),
        const SizedBox(width: 10),
        _Stat(
          icon: Iconsax.layer,
          label: 'Chunks',
          value: '$chunks',
          onTap: onTap,
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onAsk;
  final VoidCallback onCancel;
  final bool isRunning;
  final bool isEmpty;

  const _QuestionCard({
    required this.controller,
    required this.onAsk,
    required this.onCancel,
    required this.isRunning,
    required this.isEmpty,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ask the Oracle',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 3,
            minLines: 2,
            enabled: !isRunning,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: isEmpty
                  ? 'Add some notes first to enable Ask'
                  : 'What do you want to know?',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Spacer(),
              if (isRunning)
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Iconsax.close_square, size: 14),
                  label: const Text('Cancel'),
                )
              else
                ElevatedButton.icon(
                  onPressed: isEmpty ? null : onAsk,
                  icon: const Icon(Iconsax.send_1, size: 14),
                  label: const Text('Ask'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnswerView extends StatelessWidget {
  final OracleAskState state;
  final void Function(RagCitation) onCitationTap;
  const _AnswerView({required this.state, required this.onCitationTap});

  @override
  Widget build(BuildContext context) {
    final phaseLabel = switch (state.phase) {
      OraclePhase.embedding => 'Embedding question...',
      OraclePhase.retrieving => 'Searching your knowledge...',
      OraclePhase.synthesizing => 'Synthesising...',
      OraclePhase.done => 'Done',
      OraclePhase.error => 'Failed',
      OraclePhase.idle => '',
    };

    final answer = state.streamingAnswer;
    final citations = state.answer?.citations ?? const <RagCitation>[];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.flash_1, size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'ORACLE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                phaseLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
              const Spacer(),
              if (state.answer != null)
                IconButton(
                  tooltip: 'Copy markdown',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Iconsax.copy, size: 14),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: state.answer!.markdownAnswer),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Answer copied')),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (answer.isEmpty && state.phase != OraclePhase.done)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Working...',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            MarkdownBody(
              data: answer,
              shrinkWrap: true,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
                strong: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (state.phase == OraclePhase.synthesizing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fade(duration: 600.ms),
            ),
          if (citations.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'CITATIONS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 8),
            ...citations.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CitationTile(citation: c, onTap: () => onCitationTap(c)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CitationTile extends StatelessWidget {
  final RagCitation citation;
  final VoidCallback onTap;
  const _CitationTile({required this.citation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${citation.index}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      citation.documentTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    'chunk ${citation.chunkIndex}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                citation.snippet,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends ConsumerWidget {
  final OracleAskState state;
  const _ErrorBox({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = state.offline ? AppColors.warning : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                state.offline ? Iconsax.wifi : Iconsax.warning_2,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                state.offline
                    ? "You're offline"
                    : state.needsKey
                        ? 'Missing API key'
                        : 'Oracle failed',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            state.errorMessage ?? '',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (state.needsKey) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => context.go('/settings/api-keys'),
              icon: const Icon(Iconsax.key, size: 14),
              label: const Text('Open Settings'),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyKnowledgeBase extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyKnowledgeBase({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.subtleGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Iconsax.book,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Add your first knowledge source',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Pick a few notes, paste a snippet, or import a .md file. Brutus will chunk + embed them on-device so you can ask grounded questions.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Iconsax.add, size: 14),
            label: const Text('Add knowledge'),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final OracleAnswer answer;
  final VoidCallback onTap;
  const _HistoryCard({required this.answer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              answer.question,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Icon(
                  Iconsax.layer,
                  size: 11,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${answer.citations.length} cite${answer.citations.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
                const Spacer(),
                Text(
                  _relative(answer.createdAt),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _relative(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${dt.day}/${dt.month}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Library tab
// ─────────────────────────────────────────────────────────────────────────────

class _LibraryTab extends ConsumerWidget {
  final OracleProviderState state;
  final VoidCallback onAdd;
  const _LibraryTab({required this.state, required this.onAdd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.documents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Iconsax.book_saved,
                size: 48,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 12),
              Text(
                'Empty library',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                "Tap the + button to add notes, paste text, or import a file.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Iconsax.add, size: 14),
                label: const Text('Add knowledge'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(ragOracleProvider.notifier).refreshLibrary(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        itemCount: state.documents.length,
        itemBuilder: (context, i) {
          final d = state.documents[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Dismissible(
              key: Key(d.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 18),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Iconsax.trash, color: AppColors.error),
              ),
              onDismissed: (_) =>
                  ref.read(ragOracleProvider.notifier).deleteDocument(d.id),
              child: GlassCard(
                onTap: () => ChunkSheet.show(context, document: d),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _iconFor(d.source),
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _MiniPill(
                                label:
                                    '${d.chunks.length} chunk${d.chunks.length == 1 ? '' : 's'}',
                              ),
                              const SizedBox(width: 6),
                              _MiniPill(
                                label: '${d.totalTokens} tok',
                                monospace: true,
                              ),
                              const SizedBox(width: 6),
                              _MiniPill(
                                label: d.source.name,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Iconsax.arrow_right_3,
                      size: 14,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(RagSourceKind kind) {
    switch (kind) {
      case RagSourceKind.note:
        return Iconsax.note;
      case RagSourceKind.pasted:
        return Iconsax.text;
      case RagSourceKind.imported:
        return Iconsax.document_upload;
    }
  }
}

class _MiniPill extends StatelessWidget {
  final String label;
  final Color? color;
  final bool monospace;
  const _MiniPill({required this.label, this.color, this.monospace = false});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: c,
          fontFamily: monospace ? 'monospace' : null,
        ),
      ),
    );
  }
}

// ── Provider extension to expose the service's getById without leaking the
// service reference into the widget tree.
extension on OracleNotifier {
  Future<RagDocument?> _serviceGetById(String id) async {
    final doc = await VectorStore.instance.getById(id);
    return doc;
  }
}
