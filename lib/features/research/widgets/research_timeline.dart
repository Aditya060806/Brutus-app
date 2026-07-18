import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/providers/deep_research_provider.dart';

/// Vertical timeline showing each phase of a research run as it streams in.
class ResearchTimeline extends StatelessWidget {
  final DeepResearchRunState run;
  const ResearchTimeline({super.key, required this.run});

  @override
  Widget build(BuildContext context) {
    final nodes = <_TimelineNode>[
      _TimelineNode(
        icon: Iconsax.routing_2,
        label: 'Planning',
        sub: run.subQueries.isEmpty
            ? 'Decomposing your topic into sub-queries...'
            : '${run.subQueries.length} sub-querie(s) planned',
        state: _stateForPlanning(),
      ),
      ...run.subQueries.map(
        (s) => _TimelineNode(
          icon: Iconsax.search_normal_1,
          label: 'Search',
          sub: s.subQuery,
          tail: s.sources == null
              ? null
              : '${s.sources!.length} source${s.sources!.length == 1 ? '' : 's'}',
          state: s.searching
              ? _NodeState.running
              : (s.sources == null || s.sources!.isEmpty)
                  ? _NodeState.warn
                  : _NodeState.done,
        ),
      ),
      _TimelineNode(
        icon: Iconsax.flash_1,
        label: 'Synthesize',
        sub: run.dedupedSources == 0
            ? 'Waiting for sources...'
            : '${run.dedupedSources} unique source${run.dedupedSources == 1 ? '' : 's'} → Groq',
        state: _stateForSynthesis(),
      ),
      _TimelineNode(
        icon: Iconsax.tick_circle,
        label: 'Done',
        sub: run.result == null
            ? '...'
            : 'Wrote ${run.result!.markdownAnswer.length} chars in ${(run.result!.runMs / 1000).toStringAsFixed(1)}s',
        state: run.phase == ResearchPhase.done
            ? _NodeState.done
            : run.phase == ResearchPhase.error
                ? _NodeState.error
                : _NodeState.idle,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < nodes.length; i++)
          _TimelineRow(
            node: nodes[i],
            isLast: i == nodes.length - 1,
          ),
      ],
    );
  }

  _NodeState _stateForPlanning() {
    if (run.phase == ResearchPhase.error && run.subQueries.isEmpty) {
      return _NodeState.error;
    }
    if (run.phase == ResearchPhase.planning) return _NodeState.running;
    if (run.subQueries.isNotEmpty) return _NodeState.done;
    return _NodeState.idle;
  }

  _NodeState _stateForSynthesis() {
    if (run.phase == ResearchPhase.synthesizing) return _NodeState.running;
    if (run.phase == ResearchPhase.done) return _NodeState.done;
    if (run.phase == ResearchPhase.error && run.dedupedSources > 0) {
      return _NodeState.error;
    }
    return _NodeState.idle;
  }
}

enum _NodeState { idle, running, done, warn, error }

class _TimelineNode {
  final IconData icon;
  final String label;
  final String sub;
  final String? tail;
  final _NodeState state;
  const _TimelineNode({
    required this.icon,
    required this.label,
    required this.sub,
    required this.state,
    this.tail,
  });
}

class _TimelineRow extends StatelessWidget {
  final _TimelineNode node;
  final bool isLast;
  const _TimelineRow({required this.node, required this.isLast});

  Color get _color {
    switch (node.state) {
      case _NodeState.idle:
        return AppColors.textTertiary;
      case _NodeState.running:
        return AppColors.primary;
      case _NodeState.done:
        return AppColors.success;
      case _NodeState.warn:
        return AppColors.warning;
      case _NodeState.error:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = node.state == _NodeState.running;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Spine ──
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              children: [
                _Dot(color: _color, pulsing: running),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.4,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ── Content ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _color.withValues(
                      alpha: running ? 0.35 : 0.12,
                    ),
                    width: running ? 1.0 : 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(node.icon, size: 14, color: _color),
                        const SizedBox(width: 6),
                        Text(
                          node.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _color,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const Spacer(),
                        if (node.tail != null)
                          Text(
                            node.tail!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                              fontFamily: 'monospace',
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      node.sub,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final bool pulsing;
  const _Dot({required this.color, required this.pulsing});

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: pulsing
            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
            : null,
      ),
    );
    if (!pulsing) return dot;
    return dot
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(begin: const Offset(0.85, 0.85), duration: 700.ms)
        .then()
        .scale(begin: const Offset(1.15, 1.15), duration: 700.ms);
  }
}
