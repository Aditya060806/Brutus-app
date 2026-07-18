import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/shared_widgets.dart';
import 'package:brutus_app/providers/gallery_provider.dart';

/// Brutus Mobile — AI image generation gallery.
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  final _promptCtrl = TextEditingController();

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(galleryProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Gallery'),
        actions: [
          if (state.images.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Iconsax.more, size: 20),
              onSelected: (v) {
                if (v == 'clear') _confirmClear(context);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'clear', child: Text('Delete all')),
              ],
            ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          _Hero(),
          const SizedBox(height: 18),
          _PromptCard(
            controller: _promptCtrl,
            state: state,
            onGenerate: () {
              ref.read(galleryProvider.notifier).setPrompt(_promptCtrl.text);
              ref.read(galleryProvider.notifier).generate();
            },
            onCancel: () => ref.read(galleryProvider.notifier).cancel(),
          ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 14),
            _ErrorCard(state: state),
          ],
          if (state.images.isEmpty && !state.isGenerating) ...[
            const SizedBox(height: 30),
            _EmptyState(),
          ],
          if (state.images.isNotEmpty) ...[
            const SizedBox(height: 22),
            const SectionHeader(
              title: 'Recent generations',
              subtitle: 'Tap to enlarge · long-press to delete',
            ),
            const SizedBox(height: 10),
            _Grid(images: state.images),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all images?'),
        content: const Text(
          'Removes every generated image from this device. Cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(galleryProvider.notifier).clearAll();
    }
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFEC4899), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Iconsax.gallery_edit, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Gallery',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Describe anything · HuggingFace generates · saved on-device',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.97, 0.97));
  }
}

class _PromptCard extends ConsumerWidget {
  final TextEditingController controller;
  final GalleryState state;
  final VoidCallback onGenerate;
  final VoidCallback onCancel;

  const _PromptCard({
    required this.controller,
    required this.state,
    required this.onGenerate,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Prompt',
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
            minLines: 2,
            maxLines: 4,
            enabled: !state.isGenerating,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'a cinematic photo of a misty redwood forest at dawn…',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in HfImageModel.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: state.selectedModel == m,
                  onSelected: state.isGenerating
                      ? null
                      : (_) =>
                          ref.read(galleryProvider.notifier).selectModel(m),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            state.selectedModel.description,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Spacer(),
              if (state.isGenerating)
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Iconsax.close_square, size: 16),
                  label: const Text('Cancel'),
                )
              else
                ElevatedButton.icon(
                  onPressed: onGenerate,
                  icon: const Icon(Iconsax.magic_star, size: 16),
                  label: const Text('Generate'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final GalleryState state;
  const _ErrorCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = state.offline ? AppColors.warning : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(14),
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
                        ? 'HuggingFace key needed'
                        : 'Generation failed',
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
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () =>
                  GoRouter.of(context).go('/settings/api-keys'),
              icon: const Icon(Iconsax.key, size: 14),
              label: const Text('Open Settings'),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(
          Iconsax.image,
          size: 48,
          color: AppColors.textTertiary,
        ),
        const SizedBox(height: 12),
        Text(
          'No images yet',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Tell Brutus what you imagine — short or detailed prompts both work. Each generation is saved here for later.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  final List<GeneratedImage> images;
  const _Grid({required this.images});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: images.length,
      itemBuilder: (context, i) {
        final g = images[i];
        return _Tile(image: g)
            .animate(delay: Duration(milliseconds: 30 * (i > 6 ? 0 : i)))
            .fadeIn(duration: 250.ms)
            .scale(begin: const Offset(0.96, 0.96));
      },
    );
  }
}

class _Tile extends ConsumerWidget {
  final GeneratedImage image;
  const _Tile({required this.image});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _openViewer(context, ref),
      onLongPress: () => _confirmDelete(context, ref),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
          boxShadow: AppColors.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: Image.file(
                  File(image.filePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.surfaceVariant,
                    child: const Icon(
                      Iconsax.image,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    image.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    image.model.label,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
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

  Future<void> _openViewer(BuildContext context, WidgetRef ref) {
    return showDialog(
      context: context,
      builder: (_) => _Viewer(image: image),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this image?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(galleryProvider.notifier).deleteImage(image.id);
    }
  }
}

class _Viewer extends StatelessWidget {
  final GeneratedImage image;
  const _Viewer({required this.image});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(image.filePath),
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              image.prompt,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${image.model.label} · ${_relative(image.createdAt)}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: image.prompt));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Prompt copied')),
                    );
                  },
                  icon: const Icon(Iconsax.copy, size: 14),
                  label: const Text('Copy prompt'),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => Share.shareXFiles(
                    [XFile(image.filePath)],
                    text: image.prompt,
                  ),
                  icon: const Icon(Iconsax.share, size: 14),
                  label: const Text('Share'),
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
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
