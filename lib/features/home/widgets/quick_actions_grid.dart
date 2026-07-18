import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:brutus_app/core/theme/app_colors.dart';

class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key});

  static const _actions = [
    _QuickAction(
      icon: Iconsax.sms,
      label: 'Email',
      color: AppColors.email,
      route: '/tools/email',
    ),
    _QuickAction(
      icon: Iconsax.cloud_sunny,
      label: 'Weather',
      color: AppColors.weather,
      route: '/tools/weather',
    ),
    _QuickAction(
      icon: Iconsax.chart_2,
      label: 'Stocks',
      color: AppColors.stocks,
      route: '/tools/stocks',
    ),
    _QuickAction(
      icon: Iconsax.note,
      label: 'Notes',
      color: AppColors.notes,
      route: '/tools/notes',
    ),
    _QuickAction(
      icon: Iconsax.cpu,
      label: 'Automate',
      color: AppColors.automation,
      route: '/tools/automation',
    ),
    _QuickAction(
      icon: Iconsax.search_normal_1,
      label: 'Research',
      color: AppColors.research,
      route: '/tools/research',
    ),
    _QuickAction(
      icon: Iconsax.bluetooth,
      label: 'Robot',
      color: AppColors.primary,
      route: '/tools/robot',
    ),
    _QuickAction(
      icon: Iconsax.eye,
      label: 'Robot Eyes',
      color: AppColors.info,
      route: '/tools/robot-eyes',
    ),
    _QuickAction(
      icon: Iconsax.location,
      label: 'Maps',
      color: AppColors.maps,
      route: '/tools/maps',
    ),
    _QuickAction(
      icon: Iconsax.gallery_edit,
      label: 'Gallery',
      color: AppColors.files,
      route: '/tools/gallery',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.0,
      ),
      itemCount: _actions.length,
      itemBuilder: (context, index) {
        return _ActionTile(action: _actions[index])
            .animate(delay: Duration(milliseconds: 40 * index))
            .fadeIn(duration: 280.ms)
            .scale(
              begin: const Offset(0.92, 0.92),
              curve: Curves.easeOutBack,
            );
      },
    );
  }
}

class _ActionTile extends StatefulWidget {
  final _QuickAction action;
  const _ActionTile({required this.action});

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.action.color;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.lightImpact();
        context.go(widget.action.route);
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _pressed
                  ? color.withValues(alpha: 0.35)
                  : AppColors.border,
              width: _pressed ? 1 : 0.5,
            ),
            boxShadow: _pressed
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : AppColors.cardShadow,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: _pressed ? 0.18 : 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  widget.action.icon,
                  size: 22,
                  color: color,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.action.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final String route;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.route,
  });
}
