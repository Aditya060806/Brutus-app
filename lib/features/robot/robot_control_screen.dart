import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/data/services/robot_bluetooth_service.dart';
import 'package:brutus_app/providers/robot_provider.dart';

/// Brutus Robot — manual control panel.
///
/// - In-app BLE device scan (HM-10)
/// - Auto-drive toggle (binds VoiceStatus + outputLevelStream → robot)
/// - 6 expression chips with intensity slider
/// - Mouth slider (jaw angle)
/// - Eye joystick (LR / UD)
/// - Blink button + re-center
/// - 10 animation macros
/// - 10 movement tricks
/// - 4 LED patterns
class RobotControlScreen extends ConsumerStatefulWidget {
  const RobotControlScreen({super.key});

  @override
  ConsumerState<RobotControlScreen> createState() => _RobotControlScreenState();
}

class _RobotControlScreenState extends ConsumerState<RobotControlScreen> {
  double _mouth = 90;
  Offset _eye = const Offset(0, 0);

  @override
  void initState() {
    super.initState();
    // Auto-scan on first paint so the device list populates.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(robotProvider.notifier).startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(robotProvider);
    final notifier = ref.read(robotProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Robot Control'),
        actions: [
          if (state.isConnected)
            IconButton(
              icon: const Icon(Iconsax.close_square),
              tooltip: 'Disconnect',
              onPressed: notifier.disconnect,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _ConnectionCard(state: state),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: state.errorMessage!),
            ],
            const SizedBox(height: 16),
            _DevicesCard(state: state),
            const SizedBox(height: 16),
            _FreezeCard(state: state),
            const SizedBox(height: 16),
            _AutoDriveCard(state: state),

            // ── Expression ──
            const SizedBox(height: 24),
            _SectionHeader('Expression'),
            const SizedBox(height: 12),
            _ExpressionPicker(
              current: state.currentExpression,
              enabled: state.isConnected,
              onPicked: (i) => notifier.setExpression(i),
            ),

            // ── Expression Intensity ──
            const SizedBox(height: 16),
            _IntensitySlider(
              value: state.expressionIntensity,
              enabled: state.isConnected,
              onChanged: (v) =>
                  notifier.setExpressionIntensity(v.round()),
            ),

            // ── Mouth ──
            const SizedBox(height: 24),
            _SectionHeader('Mouth'),
            const SizedBox(height: 12),
            _MouthSlider(
              value: _mouth,
              enabled: state.isConnected && !state.autoDrive,
              onChanged: (v) {
                setState(() => _mouth = v);
                notifier.setMouth(v.round());
              },
            ),
            if (state.autoDrive)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: _Hint(
                  text:
                      'Auto-drive is on — Brutus is lip-syncing to his own voice. Turn it off to drive the mouth manually.',
                ),
              ),

            // ── Eyes ──
            const SizedBox(height: 24),
            _SectionHeader('Eyes'),
            const SizedBox(height: 12),
            _EyeJoystick(
              value: _eye,
              enabled: state.isConnected,
              onChanged: (offset) {
                setState(() => _eye = offset);
                final lr = ((offset.dx + 1) / 2 * 180).round();
                final ud = ((offset.dy + 1) / 2 * 180).round();
                notifier.lookAt(lr: lr, ud: ud);
              },
            ),

            // ── Quick Actions ──
            const SizedBox(height: 24),
            _SectionHeader('Quick'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionTile(
                    icon: Iconsax.eye,
                    label: 'Blink',
                    enabled: state.isConnected,
                    onTap: notifier.blink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionTile(
                    icon: Iconsax.refresh,
                    label: 'Re-center',
                    enabled: state.isConnected,
                    onTap: () {
                      setState(() => _eye = Offset.zero);
                      notifier.lookAt(lr: 90, ud: 90);
                    },
                  ),
                ),
              ],
            ),

            // ── LED Control ──
            const SizedBox(height: 24),
            _SectionHeader('LED Pattern'),
            const SizedBox(height: 12),
            _LedPatternPicker(
              current: state.ledPattern,
              enabled: state.isConnected,
              onPicked: (p) => notifier.setLedPattern(p),
            ),

            // ── Animations ──
            const SizedBox(height: 24),
            _SectionHeader('Animations'),
            const SizedBox(height: 4),
            const _Hint(
              text: 'Pre-baked sequences — tap to play on the robot.',
            ),
            const SizedBox(height: 12),
            _AnimationGrid(
              enabled: state.isConnected,
              onTap: (i) => notifier.playAnimation(i),
            ),

            // ── Movement Tricks ──
            const SizedBox(height: 24),
            _SectionHeader('Movement Tricks'),
            const SizedBox(height: 4),
            const _Hint(
              text: 'Dramatic & fun movements — great for demos!',
            ),
            const SizedBox(height: 12),
            _TrickGrid(
              enabled: state.isConnected,
              onTap: (i) => notifier.playMovementTrick(i),
            ),

            // ── Last Message ──
            if (state.lastMessage != null) ...[
              const SizedBox(height: 24),
              _SectionHeader('Last Message'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  state.lastMessage!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _ConnectionCard extends StatelessWidget {
  final RobotState state;
  const _ConnectionCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = state.isConnected
        ? AppColors.success
        : state.isConnecting
            ? AppColors.warning
            : AppColors.textTertiary;
    final label = state.isConnected
        ? 'Connected${state.lastDeviceName != null ? ' · ${state.lastDeviceName}' : ''}'
        : state.isConnecting
            ? 'Connecting…'
            : 'Disconnected';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Iconsax.bluetooth, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BLE',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Iconsax.warning_2, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _DevicesCard extends ConsumerWidget {
  final RobotState state;
  const _DevicesCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(robotProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Devices',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (state.scanning)
                TextButton.icon(
                  icon: const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  label: const Text('Stop'),
                  onPressed: notifier.stopScan,
                )
              else
                TextButton.icon(
                  icon: const Icon(Iconsax.search_normal, size: 16),
                  label: const Text('Scan'),
                  onPressed: notifier.startScan,
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap a device to connect. The HM-10 typically advertises '
            'as "HMSoft", "BT05", or "MLT-BT05". No pairing needed.',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 12),
          if (state.discovered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                state.scanning
                    ? 'Scanning for nearby BLE devices…'
                    : 'No devices yet. Tap Scan to search.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                ),
              ),
            )
          else
            Column(
              children: state.discovered
                  .map(
                    (d) => _DeviceTile(
                      device: d,
                      selected: state.lastDeviceAddress == d.address &&
                          state.isConnected,
                      busy: state.isConnecting &&
                          state.lastDeviceAddress == d.address,
                      onTap: state.isConnecting
                          ? null
                          : () => notifier.connect(d),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final BleDevice device;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  const _DeviceTile({
    required this.device,
    required this.selected,
    required this.busy,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = StringBuffer(device.address);
    if (device.rssi != null) subtitle.write('  ·  ${device.rssi} dBm');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? AppColors.primarySurface : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected ? Iconsax.tick_circle : Iconsax.bluetooth,
                  size: 18,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textTertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle.toString(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AutoDriveCard extends ConsumerWidget {
  final RobotState state;
  const _AutoDriveCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppColors.subtleGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Iconsax.cpu,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-drive',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Sync expression to voice state. Lip-sync mouth to Brutus.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: state.autoDrive,
            onChanged: state.isConnected && !state.freezeMode
                ? (v) =>
                    ref.read(robotProvider.notifier).setAutoDrive(v)
                : null,
          ),
        ],
      ),
    );
  }
}

class _FreezeCard extends ConsumerWidget {
  final RobotState state;
  const _FreezeCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: state.freezeMode ? AppColors.primarySurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: state.freezeMode ? AppColors.primary : AppColors.border,
          width: state.freezeMode ? 1.2 : 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: state.freezeMode
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Iconsax.pause_circle,
              color: state.freezeMode
                  ? AppColors.primary
                  : AppColors.textTertiary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Freeze Mode',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state.freezeMode
                      ? 'Robot is frozen. Only your controls work.'
                      : 'Hold the robot perfectly still for manual control.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: state.freezeMode,
            onChanged: state.isConnected
                ? (v) =>
                    ref.read(robotProvider.notifier).setFreezeMode(v)
                : null,
          ),
        ],
      ),
    );
  }
}

class _ExpressionPicker extends StatelessWidget {
  final int current;
  final bool enabled;
  final ValueChanged<int> onPicked;
  const _ExpressionPicker({
    required this.current,
    required this.enabled,
    required this.onPicked,
  });

  static const _options = [
    (RobotExpression.happy, '😊', 'Happy'),
    (RobotExpression.angry, '😠', 'Angry'),
    (RobotExpression.sad, '😢', 'Sad'),
    (RobotExpression.thinking, '🤔', 'Thinking'),
    (RobotExpression.sleepy, '😴', 'Sleepy'),
    (RobotExpression.surprised, '😲', 'Surprised'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _options.map((entry) {
        final selected = entry.$1 == current;
        return _ExpressionChip(
          emoji: entry.$2,
          label: entry.$3,
          selected: selected,
          enabled: enabled,
          onTap: () => onPicked(entry.$1),
        );
      }).toList(),
    );
  }
}

class _ExpressionChip extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _ExpressionChip({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.primarySurface : AppColors.surface;
    final border =
        selected ? AppColors.primary : AppColors.border;
    final fg = enabled
        ? (selected ? AppColors.primary : AppColors.textPrimary)
        : AppColors.textTertiary;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: selected ? 1.2 : 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Expression Intensity Slider ──────────────────────────────────────────────

class _IntensitySlider extends StatelessWidget {
  final int value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  const _IntensitySlider({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Iconsax.setting_4,
                  size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              const Text(
                'Intensity',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$value%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            min: 0,
            max: 100,
            divisions: 20,
            value: value.toDouble(),
            onChanged: enabled ? onChanged : null,
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Subtle',
                    style: TextStyle(
                        fontSize: 10, color: AppColors.textTertiary)),
                Text('Full',
                    style: TextStyle(
                        fontSize: 10, color: AppColors.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mouth Slider ─────────────────────────────────────────────────────────────

class _MouthSlider extends StatelessWidget {
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  const _MouthSlider({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 8),
              const Text('Closed', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
              const Spacer(),
              Text(
                value.round().toString(),
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              const Text('Wide', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
              const SizedBox(width: 8),
            ],
          ),
          Slider(
            min: 20,
            max: 180,
            value: value.clamp(20, 180),
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

// ── Eye Joystick ─────────────────────────────────────────────────────────────
//
// The joystick lives inside a ListView. Without special handling, the
// ListView's VerticalDragGestureRecognizer wins the gesture arena for
// vertical drags — making the joystick unresponsive. Fix:
//   1. _EagerPanRecognizer immediately wins the arena via resolve(accepted),
//      preventing the ListView from scrolling when the finger is on the pad.
//   2. A Listener widget tracks raw pointer events (bypasses arena entirely)
//      for instant, lag-free position updates.

class _EyeJoystick extends StatefulWidget {
  final Offset value;
  final bool enabled;
  final ValueChanged<Offset> onChanged;
  const _EyeJoystick({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_EyeJoystick> createState() => _EyeJoystickState();
}

class _EyeJoystickState extends State<_EyeJoystick> {
  static const double _size = 220;

  void _emit(Offset local) {
    final centered = Offset(
      ((local.dx / _size) * 2 - 1).clamp(-1.0, 1.0),
      ((local.dy / _size) * 2 - 1).clamp(-1.0, 1.0),
    );
    widget.onChanged(centered);
  }

  @override
  Widget build(BuildContext context) {
    final dot = Offset(
      (widget.value.dx + 1) / 2 * _size,
      (widget.value.dy + 1) / 2 * _size,
    );
    return Center(
      child: Opacity(
        opacity: widget.enabled ? 1.0 : 0.5,
        child: SizedBox(
          width: _size,
          height: _size,
          // RawGestureDetector wins the gesture arena immediately,
          // preventing the parent ListView from stealing vertical drags.
          child: RawGestureDetector(
            gestures: widget.enabled
                ? <Type, GestureRecognizerFactory>{
                    _EagerPanRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                            _EagerPanRecognizer>(
                      () => _EagerPanRecognizer(),
                      (_) {},
                    ),
                  }
                : <Type, GestureRecognizerFactory>{},
            // Listener bypasses the gesture arena entirely, giving us
            // instant, reliable pointer-position updates.
            child: Listener(
              onPointerDown: widget.enabled
                  ? (e) => _emit(e.localPosition)
                  : null,
              onPointerMove: widget.enabled
                  ? (e) => _emit(e.localPosition)
                  : null,
              behavior: HitTestBehavior.opaque,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: AppColors.border, width: 0.5),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      left: dot.dx - 18,
                      top: dot.dy - 18,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: AppColors.primaryGlow,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── LED Pattern Picker ───────────────────────────────────────────────────────

class _LedPatternPicker extends StatelessWidget {
  final int current;
  final bool enabled;
  final ValueChanged<int> onPicked;
  const _LedPatternPicker({
    required this.current,
    required this.enabled,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(RobotLedPattern.labels.length, (i) {
        final selected = i == current;
        return _PatternChip(
          emoji: RobotLedPattern.emojis[i],
          label: RobotLedPattern.labels[i],
          selected: selected,
          enabled: enabled,
          onTap: () => onPicked(i),
        );
      }),
    );
  }
}

class _PatternChip extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _PatternChip({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.primarySurface : AppColors.surface;
    final borderColor =
        selected ? AppColors.primary : AppColors.border;
    final fg = enabled
        ? (selected ? AppColors.primary : AppColors.textPrimary)
        : AppColors.textTertiary;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: borderColor, width: selected ? 1.2 : 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Animation Grid ───────────────────────────────────────────────────────────

class _AnimationGrid extends StatelessWidget {
  final bool enabled;
  final ValueChanged<int> onTap;
  const _AnimationGrid({required this.enabled, required this.onTap});

  // Distinct warm colors for each animation card
  static const _colors = [
    Color(0xFF4F46E5), // Nod — indigo
    Color(0xFFEF4444), // Shake — red
    Color(0xFF0EA5E9), // Look Around — sky
    Color(0xFFF59E0B), // Wink — amber
    Color(0xFF8B5CF6), // Yawn — violet
    Color(0xFF10B981), // Laugh — emerald
    Color(0xFFEC4899), // Eye Roll — pink
    Color(0xFF06B6D4), // Mouth Cycle — cyan
    Color(0xFF6366F1), // Eye Cycle — indigo
    Color(0xFFF97316), // Wiggle — orange
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: RobotAnimation.labels.length,
      itemBuilder: (context, i) {
        return _AnimCard(
          emoji: RobotAnimation.emojis[i],
          label: RobotAnimation.labels[i],
          color: _colors[i],
          enabled: enabled,
          onTap: () => onTap(i),
        );
      },
    );
  }
}

class _AnimCard extends StatefulWidget {
  final String emoji;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _AnimCard({
    required this.emoji,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_AnimCard> createState() => _AnimCardState();
}

class _AnimCardState extends State<_AnimCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.45,
      child: GestureDetector(
        onTapDown: widget.enabled
            ? (_) => setState(() => _pressed = true)
            : null,
        onTapUp: widget.enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onTap();
              }
            : null,
        onTapCancel:
            widget.enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.93 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 0.5),
              boxShadow: AppColors.cardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      widget.emoji,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.enabled
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
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

// ── Movement Trick Grid ──────────────────────────────────────────────────────

class _TrickGrid extends StatelessWidget {
  final bool enabled;
  final ValueChanged<int> onTap;
  const _TrickGrid({required this.enabled, required this.onTap});

  static const _colors = [
    Color(0xFFDC2626), // Crazy Eyes — red
    Color(0xFF7C3AED), // Chatter — violet
    Color(0xFF0284C7), // Slow Scan — blue
    Color(0xFFEA580C), // Peek-a-boo — orange
    Color(0xFF059669), // Double Blink — green
    Color(0xFFBE185D), // Jaw Drop — pink
    Color(0xFF6366F1), // Drowsy — indigo
    Color(0xFFCA8A04), // Side Eye — yellow
    Color(0xFF16A34A), // Happy Bounce — green
    Color(0xFF9333EA), // Confused — purple
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: RobotMovementTrick.labels.length,
      itemBuilder: (context, i) {
        return _AnimCard(
          emoji: RobotMovementTrick.emojis[i],
          label: RobotMovementTrick.labels[i],
          color: _colors[i],
          enabled: enabled,
          onTap: () => onTap(i),
        );
      },
    );
  }
}

// ── Shared Small Widgets ─────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Column(
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.textTertiary,
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Iconsax.info_circle,
              color: AppColors.primary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Eager Pan Recognizer ─────────────────────────────────────────────────────
//
// A PanGestureRecognizer that immediately wins the gesture arena as soon as
// the pointer touches down. This prevents the parent ListView's
// VerticalDragGestureRecognizer from stealing vertical drags when the user
// is trying to control the eye joystick.

class _EagerPanRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    // Accept immediately — don't wait for kTouchSlop displacement.
    // This makes us win over the ListView's scroll recognizer.
    resolve(GestureDisposition.accepted);
  }
}
