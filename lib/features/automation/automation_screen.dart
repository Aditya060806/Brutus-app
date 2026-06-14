import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/shared_widgets.dart';
import 'package:brutus_app/features/automation/widgets/app_launcher_sheet.dart';
import 'package:brutus_app/features/automation/widgets/notifications_sheet.dart';
import 'package:brutus_app/providers/automation_provider.dart';

class AutomationScreen extends ConsumerStatefulWidget {
  const AutomationScreen({super.key});

  @override
  ConsumerState<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends ConsumerState<AutomationScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission state can change while user is in the system Settings app —
    // refresh whenever we come back to the foreground.
    if (state == AppLifecycleState.resumed) {
      ref.read(automationProvider.notifier).refreshPermissions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(automationProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Automation')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          _Hero(state: state),
          const SizedBox(height: 18),
          _PermissionsSection(state: state),
          const SizedBox(height: 22),
          const SectionHeader(
            title: 'Quick controls',
            subtitle: 'Hardware toggles and shortcuts',
          ),
          const SizedBox(height: 10),
          _QuickGrid(state: state),
          const SizedBox(height: 22),
          const SectionHeader(
            title: 'Settings panels',
            subtitle: "Android won't let third-party apps toggle these directly — Brutus opens the system panel for you",
          ),
          const SizedBox(height: 10),
          _SettingsPanels(),
          const SizedBox(height: 22),
          _AppsCard(),
          if (state.notificationListenerEnabled) ...[
            const SizedBox(height: 16),
            _NotificationsCard(state: state),
          ],
          if (state.toast != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _Toast(text: state.toast!),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero
// ─────────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  final AutomationState state;
  const _Hero({required this.state});

  @override
  Widget build(BuildContext context) {
    final acc = state.accessibilityEnabled;
    final nl = state.notificationListenerEnabled;
    final overall = (acc ? 1 : 0) + (nl ? 1 : 0) + (state.canWriteSettings ? 1 : 0);
    final pct = (overall / 3 * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF8B5CF6), Color(0xFFA78BFA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.automation.withValues(alpha: 0.3),
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
            child: const Icon(Iconsax.cpu, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Phone Automation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Setup $pct% complete · grant the permissions below',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.97, 0.97));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Permissions
// ─────────────────────────────────────────────────────────────────────────────

class _PermissionsSection extends ConsumerWidget {
  final AutomationState state;
  const _PermissionsSection({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Permissions',
          subtitle: 'Grant once, use everywhere',
        ),
        const SizedBox(height: 10),
        _PermTile(
          icon: Iconsax.keyboard,
          title: 'Accessibility service',
          subtitle:
              'Lets Brutus type into apps, trigger Back/Home gestures, and auto-send WhatsApp messages.',
          enabled: state.accessibilityEnabled,
          onOpen: () => ref
              .read(automationProvider.notifier)
              .openAccessibilitySettings(),
        ),
        const SizedBox(height: 8),
        _PermTile(
          icon: Iconsax.notification,
          title: 'Notification access',
          subtitle:
              'Brutus reads incoming notifications when you ask "what just buzzed".',
          enabled: state.notificationListenerEnabled,
          onOpen: () => ref
              .read(automationProvider.notifier)
              .openNotificationListenerSettings(),
        ),
        const SizedBox(height: 8),
        _PermTile(
          icon: Iconsax.brush_2,
          title: 'Modify system settings',
          subtitle: 'Required for "set brightness" voice commands.',
          enabled: state.canWriteSettings,
          onOpen: () =>
              ref.read(automationProvider.notifier).openWriteSettings(),
        ),
      ],
    );
  }
}

class _PermTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onOpen;

  const _PermTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.success : AppColors.warning;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    StatusBadge(
                      label: enabled ? 'Granted' : 'Required',
                      color: color,
                      pulse: enabled,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                if (!enabled)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Iconsax.export_1, size: 14),
                      label: const Text('Open Settings'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick controls
// ─────────────────────────────────────────────────────────────────────────────

class _QuickGrid extends ConsumerWidget {
  final AutomationState state;
  const _QuickGrid({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(automationProvider.notifier);
    final tiles = <_QuickTile>[
      _QuickTile(
        icon: state.torchOn ? Iconsax.flash : Iconsax.flash_slash,
        label: 'Flashlight',
        active: state.torchOn,
        onTap: notifier.toggleTorch,
      ),
      _QuickTile(
        icon: Iconsax.volume_high,
        label: 'Volume',
        onTap: () => notifier.openSettingsPanel(SettingsPanel.volume),
      ),
      _QuickTile(
        icon: Iconsax.notification_status,
        label: 'Silent',
        active: state.ringerMode == RingerMode.silent,
        onTap: () => notifier.setRinger(RingerMode.silent),
      ),
      _QuickTile(
        icon: Iconsax.mobile,
        label: 'Vibrate',
        active: state.ringerMode == RingerMode.vibrate,
        onTap: () => notifier.setRinger(RingerMode.vibrate),
      ),
      _QuickTile(
        icon: Iconsax.notification_bing,
        label: 'Ring',
        active: state.ringerMode == RingerMode.normal,
        onTap: () => notifier.setRinger(RingerMode.normal),
      ),
      _QuickTile(
        icon: Iconsax.global,
        label: 'Internet',
        onTap: () => notifier.openSettingsPanel(SettingsPanel.internet),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, i) => tiles[i],
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : AppColors.primary;
    final bg = active ? AppColors.primary : AppColors.primarySurface;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
              width: active ? 1.0 : 0.5,
            ),
            boxShadow: active ? AppColors.primaryGlow : AppColors.cardShadow,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: fg, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings panels
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsPanels extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(automationProvider.notifier);
    final panels = <_PanelEntry>[
      _PanelEntry(Iconsax.wifi, 'Wi-Fi', SettingsPanel.wifi),
      _PanelEntry(Iconsax.bluetooth, 'Bluetooth', SettingsPanel.bluetooth),
      _PanelEntry(Iconsax.airplane, 'Airplane', SettingsPanel.airplane),
      _PanelEntry(Iconsax.location, 'Location', SettingsPanel.location),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final p in panels)
          _PanelChip(
            entry: p,
            onTap: () => notifier.openSettingsPanel(p.panel),
          ),
      ],
    );
  }
}

class _PanelEntry {
  final IconData icon;
  final String label;
  final SettingsPanel panel;
  const _PanelEntry(this.icon, this.label, this.panel);
}

class _PanelChip extends StatelessWidget {
  final _PanelEntry entry;
  final VoidCallback onTap;
  const _PanelChip({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(entry.icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                entry.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Iconsax.export_1,
                size: 12,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Apps card
// ─────────────────────────────────────────────────────────────────────────────

class _AppsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primarySurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Iconsax.element_3,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'App launcher',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Open any installed app in one tap or by voice.",
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => AppLauncherSheet.show(context, ref),
            icon: const Icon(Iconsax.search_normal_1, size: 14),
            label: const Text('Browse'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications card
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationsCard extends ConsumerWidget {
  final AutomationState state;
  const _NotificationsCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = state.notifications.length;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Iconsax.notification,
              color: AppColors.warning,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$unread active right now',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => NotificationsSheet.show(context, ref),
            icon: const Icon(Iconsax.eye, size: 14),
            label: const Text('View'),
          ),
        ],
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  final String text;
  const _Toast({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
