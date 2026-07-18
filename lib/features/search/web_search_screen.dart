import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/shared_widgets.dart';
import 'package:brutus_app/providers/web_search_provider.dart';

/// Brutus Mobile — Web Search screen.
/// Standalone Tavily search with answer card + ranked results.
class WebSearchScreen extends ConsumerStatefulWidget {
  const WebSearchScreen({super.key});

  @override
  ConsumerState<WebSearchScreen> createState() => _WebSearchScreenState();
}

class _WebSearchScreenState extends ConsumerState<WebSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _runSearch([String? value]) {
    final query = (value ?? _controller.text).trim();
    if (query.isEmpty) return;
    _focus.unfocus();
    ref.read(webSearchProvider.notifier).search(query);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(webSearchProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Web Search'),
        actions: [
          if (state.isLoading)
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Iconsax.close_square, size: 20),
              onPressed: () => ref.read(webSearchProvider.notifier).cancel(),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(webSearchProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            _buildSearchBar(state),
            const SizedBox(height: 12),
            _buildOptionsRow(state),
            if (state.recent.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildRecent(state),
            ],
            const SizedBox(height: 18),
            if (state.isLoading)
              const _Shimmers()
            else if (state.error != null)
              _ErrorCard(
                message: state.error!,
                needsKey: state.needsKey,
                offline: state.offline,
                onRetry: () => _runSearch(state.query),
                onSettings: () => context.go('/settings/api-keys'),
              )
            else if (state.result != null)
              _Results(state.result!)
            else
              const _EmptyState(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(WebSearchState state) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(
            Iconsax.search_normal_1,
            size: 18,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: _runSearch,
              decoration: const InputDecoration(
                hintText: 'Search the web...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
                isDense: true,
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Iconsax.close_circle, size: 18),
              onPressed: () {
                _controller.clear();
                setState(() {});
              },
            ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: _runSearch,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Iconsax.send_1,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsRow(WebSearchState state) {
    return Row(
      children: [
        Expanded(
          child: SwitchListTile.adaptive(
            value: state.includeRawContent,
            onChanged: state.isLoading
                ? null
                : (v) =>
                    ref.read(webSearchProvider.notifier).setIncludeRaw(v),
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            title: const Text(
              'Show full content',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: const Text(
              'Slower — fetches the article body',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecent(WebSearchState state) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: state.recent.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == state.recent.length) {
            return TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: AppColors.textTertiary,
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: const Icon(Iconsax.trash, size: 14),
              label: const Text('Clear'),
              onPressed: () =>
                  ref.read(webSearchProvider.notifier).clearRecent(),
            );
          }
          final query = state.recent[i];
          return InputChip(
            label: Text(
              query,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            avatar: const Icon(Iconsax.clock, size: 14),
            onPressed: () {
              _controller.text = query;
              _runSearch(query);
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Iconsax.global_search,
              size: 28,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Search the web with Tavily',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Real-time, LLM-friendly results with a one-line answer up top.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),
        ],
      ).animate().fadeIn(duration: 300.ms),
    );
  }
}

class _Shimmers extends StatelessWidget {
  const _Shimmers();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Shimmer.fromColors(
            baseColor: AppColors.surfaceVariant,
            highlightColor: AppColors.surface,
            child: Container(
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  final TavilyResult result;
  const _Results(this.result);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.answer != null && result.answer!.trim().isNotEmpty)
          _AnswerCard(answer: result.answer!.trim())
              .animate()
              .fadeIn(duration: 300.ms)
              .slideY(begin: 0.04),
        const SizedBox(height: 14),
        const SectionHeader(title: 'Top results'),
        const SizedBox(height: 10),
        ...result.results.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ResultCard(index: e.key + 1, source: e.value)
                    .animate(delay: Duration(milliseconds: 60 * e.key))
                    .fadeIn(duration: 250.ms)
                    .slideX(begin: 0.03),
              ),
            ),
      ],
    );
  }
}

class _AnswerCard extends StatelessWidget {
  final String answer;
  const _AnswerCard({required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.primaryGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.flash_1, size: 14, color: Colors.white70),
              const SizedBox(width: 6),
              const Text(
                'ANSWER',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Iconsax.copy, size: 16, color: Colors.white),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: answer));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Answer copied'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            answer,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final int index;
  final TavilySource source;
  const _ResultCard({required this.index, required this.source});

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(source.url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open URL')),
      );
    }
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: source.url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied ${source.domain}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scorePct = (source.score * 100).clamp(0, 100).toStringAsFixed(0);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      onTap: () => _open(context),
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
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$index',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source.domain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$scorePct%',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _open(context),
            onLongPress: () => _copy(context),
            child: Text(
              source.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
          ),
          if (source.content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              source.content,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          if (source.rawContent != null &&
              source.rawContent!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
                visualDensity: VisualDensity.compact,
                title: const Text(
                  'Show full article',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                children: [
                  Text(
                    source.rawContent!.trim(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final bool needsKey;
  final bool offline;
  final VoidCallback onRetry;
  final VoidCallback onSettings;
  const _ErrorCard({
    required this.message,
    required this.needsKey,
    required this.offline,
    required this.onRetry,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final color = offline ? AppColors.warning : AppColors.error;
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
                offline ? Iconsax.wifi : Iconsax.warning_2,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                offline
                    ? "You're offline"
                    : needsKey
                        ? 'Tavily key needed'
                        : 'Search failed',
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
            message,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (needsKey)
                ElevatedButton.icon(
                  onPressed: onSettings,
                  icon: const Icon(Iconsax.key, size: 14),
                  label: const Text('Open Settings'),
                )
              else
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Iconsax.refresh, size: 14),
                  label: const Text('Retry'),
                ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}
