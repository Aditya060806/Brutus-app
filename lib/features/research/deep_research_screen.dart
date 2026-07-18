import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/shared_widgets.dart';
import 'package:brutus_app/features/research/widgets/research_timeline.dart';
import 'package:brutus_app/features/research/widgets/sources_list.dart';
import 'package:brutus_app/providers/deep_research_provider.dart';

class DeepResearchScreen extends ConsumerStatefulWidget {
  const DeepResearchScreen({super.key});

  @override
  ConsumerState<DeepResearchScreen> createState() => _DeepResearchScreenState();
}

class _DeepResearchScreenState extends ConsumerState<DeepResearchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _queryController = TextEditingController();
  DeepResearchDepth _depth = DeepResearchDepth.standard;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _start() {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    ref.read(deepResearchProvider.notifier).run(query, depth: _depth);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deepResearchProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Deep Research'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textTertiary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Run'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _RunTab(
            state: state,
            queryController: _queryController,
            depth: _depth,
            onDepth: (d) => setState(() => _depth = d),
            onStart: _start,
          ),
          _HistoryTab(state: state),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Run tab
// ─────────────────────────────────────────────────────────────────────────────

class _RunTab extends ConsumerWidget {
  final DeepResearchProviderState state;
  final TextEditingController queryController;
  final DeepResearchDepth depth;
  final ValueChanged<DeepResearchDepth> onDepth;
  final VoidCallback onStart;

  const _RunTab({
    required this.state,
    required this.queryController,
    required this.depth,
    required this.onDepth,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = state.current;
    final isRunning = run?.isRunning ?? false;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        _heroCard(),
        const SizedBox(height: 18),
        _inputCard(context, ref, isRunning),
        if (run != null) ...[
          const SizedBox(height: 22),
          if (run.errorMessage != null)
            _errorCard(context, run)
          else ...[
            ResearchTimeline(run: run),
            if (run.streamingAnswer.isNotEmpty || run.phase == ResearchPhase.synthesizing) ...[
              const SizedBox(height: 4),
              _AnswerBubble(run: run),
            ],
            if (run.result != null) ...[
              const SizedBox(height: 22),
              SourcesList(sources: run.result!.sources),
            ],
          ],
        ],
      ],
    );
  }

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEC4899), Color(0xFFF43F5E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.research.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Iconsax.search_normal_1,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Research Engine',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Tavily search → Groq synthesis → cited answer',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.97, 0.97));
  }

  Widget _inputCard(BuildContext context, WidgetRef ref, bool isRunning) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Research Query',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: queryController,
            maxLines: 3,
            minLines: 2,
            enabled: !isRunning,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What would you like to research?',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
          const SizedBox(height: 8),
          // Depth chips
          Row(
            children: [
              for (final d in DeepResearchDepth.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(d.label),
                    selected: depth == d,
                    onSelected: isRunning ? null : (_) => onDepth(d),
                  ),
                ),
              const Spacer(),
              if (isRunning)
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(deepResearchProvider.notifier).cancel(),
                  icon: const Icon(Iconsax.close_square, size: 16),
                  label: const Text('Cancel'),
                )
              else
                ElevatedButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Iconsax.send_1, size: 16),
                  label: const Text('Start'),
                ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms);
  }

  Widget _errorCard(BuildContext context, DeepResearchRunState run) {
    final color = run.offline ? AppColors.warning : AppColors.error;
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
                run.offline ? Iconsax.wifi : Iconsax.warning_2,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                run.offline
                    ? "You're offline"
                    : run.needsKey
                        ? 'Missing API key'
                        : 'Research failed',
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
            run.errorMessage ?? '',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (run.needsKey)
                ElevatedButton.icon(
                  onPressed: () => context.go('/settings/api-keys'),
                  icon: const Icon(Iconsax.key, size: 14),
                  label: const Text('Open Settings'),
                )
              else if (!run.offline)
                ElevatedButton.icon(
                  onPressed: () => context
                      .findAncestorStateOfType<_DeepResearchScreenState>()
                      ?._start(),
                  icon: const Icon(Iconsax.refresh, size: 14),
                  label: const Text('Retry'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnswerBubble extends StatelessWidget {
  final DeepResearchRunState run;
  const _AnswerBubble({required this.run});

  @override
  Widget build(BuildContext context) {
    final isStreaming = run.phase == ResearchPhase.synthesizing;
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
                'ANSWER',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              if (run.result != null)
                IconButton(
                  tooltip: 'Copy markdown',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Iconsax.copy, size: 14),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: run.result!.markdownAnswer),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Answer copied')),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (run.streamingAnswer.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Synthesising...',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            MarkdownBody(
              data: run.streamingAnswer,
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
          if (isStreaming) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .fade(duration: 600.ms),
                const SizedBox(width: 6),
                const Text(
                  'streaming...',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History tab
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerWidget {
  final DeepResearchProviderState state;
  const _HistoryTab({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Iconsax.archive,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              'No research yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Run a query in the Run tab to start your history.',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      itemCount: state.history.length,
      itemBuilder: (context, i) {
        final r = state.history[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Dismissible(
            key: Key(r.id),
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
            onDismissed: (_) => ref
                .read(deepResearchProvider.notifier)
                .deleteHistoryEntry(r.id),
            child: GlassCard(
              padding: const EdgeInsets.all(14),
              onTap: () {
                ref.read(deepResearchProvider.notifier).showHistoryEntry(r);
                DefaultTabController.maybeOf(context)?.animateTo(0);
                final tabState = context
                    .findAncestorStateOfType<_DeepResearchScreenState>();
                tabState?._tabs.animateTo(0);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.query,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _MetaChip(
                        icon: Iconsax.global_search,
                        label: '${r.sources.length} src',
                      ),
                      const SizedBox(width: 6),
                      _MetaChip(
                        icon: Iconsax.clock,
                        label: '${(r.runMs / 1000).toStringAsFixed(1)}s',
                      ),
                      const Spacer(),
                      Text(
                        _relative(r.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _relative(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'yesterday';
    return '${dt.day}/${dt.month}';
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.textTertiary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
