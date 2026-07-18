import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/shared_widgets.dart';
import 'package:brutus_app/data/services/robot_bluetooth_service.dart';
import 'package:brutus_app/providers/chat_provider.dart';
import 'package:brutus_app/providers/robot_provider.dart';
import 'package:brutus_app/providers/user_prefs_provider.dart';

/// Live system status strip: AI engine · network · robot.
///
/// Every card reflects real state (no placeholders). Uses `select` so the
/// row only rebuilds when a status actually flips — never on the rapid
/// audio-level updates the chat provider emits while Brutus speaks.
class StatusCards extends ConsumerWidget {
  const StatusCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // (isConnected, status, isLiveMode) — deliberately excludes audioLevel.
    final ai = ref.watch(
      chatProvider.select((s) => (s.isConnected, s.status, s.isLiveMode)),
    );
    final online = ref.watch(isOnlineProvider).value ?? true;
    final robot = ref.watch(robotProvider.select((s) => s.connection));

    final (aiConnected, aiStatus, aiLive) = ai;

    final (aiLabel, aiColor, aiPulse) = switch ((aiConnected, aiStatus)) {
      (_, VoiceStatus.connecting) => ('Connecting', AppColors.warning, true),
      (true, VoiceStatus.speaking) => ('Speaking', AppColors.success, true),
      (true, VoiceStatus.thinking) => ('Thinking', AppColors.warning, true),
      (true, _) when aiLive => ('Live', AppColors.success, true),
      (true, _) => ('Text mode', AppColors.info, false),
      (false, VoiceStatus.error) => ('Error', AppColors.error, false),
      (false, _) => ('Off', AppColors.textTertiary, false),
    };

    final (netLabel, netColor) = online
        ? ('Online', AppColors.info)
        : ('Offline', AppColors.error);

    final (robotLabel, robotColor, robotPulse) = switch (robot) {
      RobotConnectionState.connected => ('Linked', AppColors.success, true),
      RobotConnectionState.connecting => ('Pairing', AppColors.warning, true),
      RobotConnectionState.disconnected =>
        ('Offline', AppColors.textTertiary, false),
    };

    return Row(
      children: [
        Expanded(
          child: _StatusCard(
            icon: Iconsax.cpu,
            iconGradient: AppColors.heroGradient,
            title: 'AI Engine',
            label: aiLabel,
            color: aiColor,
            pulse: aiPulse,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatusCard(
            icon: Iconsax.wifi,
            iconColor: netColor,
            title: 'Network',
            label: netLabel,
            color: netColor,
            pulse: false,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatusCard(
            icon: Iconsax.bluetooth,
            iconColor: robotColor == AppColors.textTertiary
                ? AppColors.primary
                : robotColor,
            title: 'Robot',
            label: robotLabel,
            color: robotColor,
            pulse: robotPulse,
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Gradient? iconGradient;
  final Color? iconColor;
  final String title;
  final String label;
  final Color color;
  final bool pulse;

  const _StatusCard({
    required this.icon,
    this.iconGradient,
    this.iconColor,
    required this.title,
    required this.label,
    required this.color,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: iconGradient,
              color: iconGradient == null
                  ? (iconColor ?? color).withValues(alpha: 0.1)
                  : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 16,
              color: iconGradient != null
                  ? Colors.white
                  : (iconColor ?? color),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 5),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOut,
            child: StatusBadge(
              key: ValueKey('$label$pulse'),
              label: label,
              color: color,
              pulse: pulse,
            ),
          ),
        ],
      ),
    );
  }
}
