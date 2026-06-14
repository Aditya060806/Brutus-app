import 'package:flutter/material.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/particle_sphere.dart';

/// AI orb — pure 3D particle sphere, no chrome.
///
/// Faithful to the desktop reference (`Sphere.tsx`):
///   • Idle (system off): slate particles, slow rotation
///   • Active (system on): red particles, reactive to **Brutus's** voice
///     (mic input never drives the sphere — that's intentional)
///
/// No mic icon, no glow rings, no gradient ring — just the sphere with a
/// subtle backdrop glow when active.
class AiOrbWidget extends StatelessWidget {
  final bool isActive;
  final VoidCallback onToggle;
  final String? statusText;
  final double audioLevel; // Brutus's output level (0..1)
  final bool isSpeaking;

  const AiOrbWidget({
    super.key,
    required this.isActive,
    required this.onToggle,
    this.statusText,
    this.audioLevel = 0.0,
    this.isSpeaking = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onToggle,
          // Big tappable area, sphere centred. Subtle radial glow underneath
          // when active — gives the orb depth without adding any chrome.
          child: SizedBox(
            width: 280,
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isActive)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFEF4444).withValues(
                            alpha: 0.15 + (audioLevel * 0.15).clamp(0.0, 0.2),
                          ),
                          const Color(0xFFEF4444).withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.7],
                      ),
                    ),
                  ),
                ParticleSphere(
                  audioLevel: audioLevel,
                  isActive: isActive,
                  size: 280,
                  particleCount: 3500,
                  selfPulse: isSpeaking && audioLevel < 0.05,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            statusText ?? (isActive ? 'Listening...' : 'Tap to wake Brutus'),
            key: ValueKey(statusText ?? isActive.toString()),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isActive
                  ? const Color(0xFFEF4444)
                  : AppColors.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}
