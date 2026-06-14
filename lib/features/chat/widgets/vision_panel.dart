import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/data/services/vision_service.dart';
import 'package:brutus_app/providers/chat_provider.dart';

/// Compact, draggable-feel panel showing the camera preview Brutus sees.
/// Sits above the input bar, takes ~30% of screen height.
class VisionPanel extends ConsumerStatefulWidget {
  const VisionPanel({super.key});

  @override
  ConsumerState<VisionPanel> createState() => _VisionPanelState();
}

class _VisionPanelState extends ConsumerState<VisionPanel> {
  // We pull the controller directly from the singleton — it is owned by the
  // VisionService, so we just need to rebuild when start/stop completes.
  CameraController? get _controller => VisionService.instance.controller;

  @override
  Widget build(BuildContext context) {
    // Only rebuild when the vision-related slices change. Watching the entire
    // chat state would rebuild on every audio level tick (~10/s).
    final visionMode = ref.watch(
      chatProvider.select((s) => s.visionMode),
    );
    final framesSent = ref.watch(
      chatProvider.select((s) => s.visionFramesSent),
    );
    final framesFailed = ref.watch(
      chatProvider.select((s) => s.visionFramesFailed),
    );
    final dataMode = ref.watch(
      chatProvider.select((s) => s.visionDataMode),
    );
    final on = visionMode != VisionMode.off;

    if (!on) return const SizedBox.shrink();

    final controller = _controller;
    final aspect = controller != null && controller.value.isInitialized
        ? controller.value.aspectRatio
        : 9 / 16;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera preview, fitted to fill the panel without letterboxing.
            // We use FittedBox.cover so portrait phones don't show black bars.
            if (controller != null && controller.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.previewSize?.height ?? 720,
                  height: controller.value.previewSize?.width ?? 1280,
                  child: AspectRatio(
                    aspectRatio: aspect,
                    child: CameraPreview(controller),
                  ),
                ),
              )
            else
              const Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),

            // Top label — what Brutus sees + frame counters
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  _DotPulse(color: AppColors.error),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      visionMode == VisionMode.frontCamera
                          ? 'Brutus is seeing • Front'
                          : 'Brutus is seeing • Back',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _FrameCounter(
                    sent: framesSent,
                    failed: framesFailed,
                  ),
                ],
              ),
            ),

            // Bottom controls — switch lens + toggle data mode + close
            Positioned(
              bottom: 10,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  _ControlBtn(
                    icon: Iconsax.refresh,
                    tooltip: 'Switch camera',
                    onTap: () =>
                        ref.read(chatProvider.notifier).switchVisionLens(),
                  ),
                  const SizedBox(width: 8),
                  _DataModeToggle(
                    mode: dataMode,
                    onTap: () {
                      final next = dataMode == VisionDataMode.standard
                          ? VisionDataMode.low
                          : VisionDataMode.standard;
                      ref
                          .read(chatProvider.notifier)
                          .setVisionDataMode(next);
                    },
                  ),
                  const Spacer(),
                  _ControlBtn(
                    icon: Iconsax.close_square,
                    tooltip: 'Stop vision',
                    primary: true,
                    onTap: () => ref.read(chatProvider.notifier).stopVision(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.05, end: 0),
    );
  }
}

class _DotPulse extends StatelessWidget {
  final Color color;
  const _DotPulse({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(
          begin: 0.4,
          end: 1.0,
          duration: 700.ms,
        );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool primary;
  const _ControlBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: primary
                  ? AppColors.primary.withValues(alpha: 0.9)
                  : Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}

/// Top-right pill showing how many frames Brutus has accepted vs. failed
/// to send. The failure count is hidden until > 0 to keep the panel calm
/// during normal operation; once it appears, it tints red so the user
/// notices network issues at a glance.
class _FrameCounter extends StatelessWidget {
  final int sent;
  final int failed;
  const _FrameCounter({required this.sent, required this.failed});

  @override
  Widget build(BuildContext context) {
    final hasFailures = failed > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: hasFailures
            ? Border.all(
                color: AppColors.error.withValues(alpha: 0.7),
                width: 0.6,
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${sent}f',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          if (hasFailures) ...[
            Container(
              width: 1,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: Colors.white24,
            ),
            Tooltip(
              message: '$failed frame(s) failed to send',
              child: Row(
                children: [
                  const Icon(
                    Iconsax.warning_2,
                    size: 10,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$failed',
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
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

/// In-panel toggle for the bandwidth profile. Tapping flips between Standard
/// and Low data without leaving the chat — handy when the user steps onto
/// cellular mid-session.
class _DataModeToggle extends StatelessWidget {
  final VisionDataMode mode;
  final VoidCallback onTap;
  const _DataModeToggle({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final low = mode == VisionDataMode.low;
    return Tooltip(
      message: low
          ? 'Low data: 480p · 4s. Tap for Standard.'
          : 'Standard: 720p · 2s. Tap for Low data.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: low
                  ? AppColors.warning.withValues(alpha: 0.85)
                  : Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  low ? Iconsax.simcard : Iconsax.wifi,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  low ? 'Low' : 'HD',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
