import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/providers/chat_provider.dart';

/// Compact status panel shown above the input bar while Brutus is sharing
/// the user's screen. Deliberately *no* live mirror preview — that would
/// create a feedback loop (Brutus would see itself seeing itself).
class ScreenSharePanel extends ConsumerWidget {
  const ScreenSharePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(chatProvider.select((s) => s.screenShareOn));
    final framesSent =
        ref.watch(chatProvider.select((s) => s.screenFramesSent));
    final framesFailed =
        ref.watch(chatProvider.select((s) => s.screenFramesFailed));
    final dataMode =
        ref.watch(chatProvider.select((s) => s.screenShareDataMode));

    if (!on) return const SizedBox.shrink();

    final notifier = ref.read(chatProvider.notifier);

    // The animation wrapper is its own widget so it doesn't replay every
    // time the frame counter ticks (every 2-4s). Animation runs once on
    // mount, the inner content rebuilds normally.
    return _AnimatedShell(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.error.withValues(alpha: 0.45),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.error.withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              _LiveDot(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Brutus is seeing your screen',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusLine(framesSent, framesFailed, dataMode),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              _ModeChip(
                mode: dataMode,
                onTap: () {
                  final next = dataMode == ScreenShareDataMode.standard
                      ? ScreenShareDataMode.low
                      : ScreenShareDataMode.standard;
                  notifier.setScreenShareDataMode(next);
                },
              ),
              const SizedBox(width: 6),
              _StopButton(onTap: notifier.stopScreenShare),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLine(int sent, int failed, ScreenShareDataMode mode) {
    final base = '${mode.label}  ·  $sent sent';
    if (failed > 0) return '$base  ·  $failed failed';
    return base;
  }
}

class _AnimatedShell extends StatelessWidget {
  final Widget child;
  const _AnimatedShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return child.animate().fadeIn(duration: 220.ms).slideY(begin: -0.05, end: 0);
  }
}

class _LiveDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: AppColors.error,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.6),
            blurRadius: 6,
          ),
        ],
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(
          begin: 0.4,
          end: 1.0,
          duration: 700.ms,
        );
  }
}

class _ModeChip extends StatelessWidget {
  final ScreenShareDataMode mode;
  final VoidCallback onTap;
  const _ModeChip({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final low = mode == ScreenShareDataMode.low;
    return Tooltip(
      message: low
          ? 'Low data: 480px · 7s. Tap for Standard.'
          : 'Standard: 720px · 5s. Tap for Low data.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: low
                  ? AppColors.warning.withValues(alpha: 0.15)
                  : AppColors.primarySurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: low
                    ? AppColors.warning.withValues(alpha: 0.4)
                    : AppColors.primary.withValues(alpha: 0.3),
                width: 0.6,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  low ? Iconsax.flash_slash : Iconsax.flash_1,
                  size: 12,
                  color: low ? AppColors.warning : AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  low ? 'Low' : 'Std',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: low ? AppColors.warning : AppColors.primary,
                    letterSpacing: 0.3,
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

class _StopButton extends StatelessWidget {
  final VoidCallback onTap;
  const _StopButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Stop sharing',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Iconsax.close_square,
              size: 16,
              color: AppColors.error,
            ),
          ),
        ),
      ),
    );
  }
}
