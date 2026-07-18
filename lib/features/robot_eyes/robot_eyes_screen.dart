import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/data/services/esp_cam_service.dart';
import 'package:brutus_app/providers/robot_eyes_provider.dart';

/// Brutus's eyes — live ESP32-CAM view + "let Brutus see" (feeds the stream to
/// Gemini so he can describe/identify what the robot is looking at).
class RobotEyesScreen extends ConsumerStatefulWidget {
  const RobotEyesScreen({super.key});

  @override
  ConsumerState<RobotEyesScreen> createState() => _RobotEyesScreenState();
}

class _RobotEyesScreenState extends ConsumerState<RobotEyesScreen> {
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: ref.read(robotEyesProvider).camUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(robotEyesProvider);
    final n = ref.read(robotEyesProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Robot Eyes'),
        actions: [
          if (state.isStreaming)
            IconButton(
              icon: const Icon(Iconsax.close_square),
              tooltip: 'Disconnect',
              onPressed: n.disconnect,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _UrlCard(state: state, controller: _urlCtrl),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: state.errorMessage!),
            ],
            const SizedBox(height: 16),
            const _LiveView(),
            const SizedBox(height: 16),
            _ToggleCard(
              icon: Iconsax.eye,
              title: 'Brutus sees',
              subtitle:
                  'Stream the view to Brutus so he can describe and recognise '
                  'what he\'s looking at.',
              value: state.brutusSees,
              enabled: state.isStreaming,
              onChanged: n.setBrutusSees,
            ),
            if (state.brutusSees) ...[
              const SizedBox(height: 8),
              Text('Frames sent to Brutus: ${state.framesToBrutus}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textTertiary)),
            ],
            const SizedBox(height: 12),
            _ToggleCard(
              icon: Iconsax.flash_1,
              title: 'Flash / eye light',
              subtitle: 'Turn the camera\'s on-board LED on or off.',
              value: state.flashOn,
              enabled: state.isStreaming,
              onChanged: n.setFlash,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: state.isStreaming ? n.askBrutusWhatHeSees : null,
                icon: const Icon(Iconsax.message_question, size: 18),
                label: const Text('Ask Brutus what he sees'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Camera URL / connection ──

class _UrlCard extends ConsumerWidget {
  final RobotEyesState state;
  final TextEditingController controller;
  const _UrlCard({required this.state, required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(robotEyesProvider.notifier);
    final color = state.isStreaming
        ? AppColors.success
        : state.isConnecting
            ? AppColors.warning
            : AppColors.textTertiary;
    final label = state.isStreaming
        ? 'Streaming'
        : state.isConnecting
            ? 'Connecting…'
            : 'Not connected';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Iconsax.camera, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ESP32-CAM',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textTertiary)),
                    Text(label,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            onChanged: n.setUrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Camera IP or URL',
              hintText: '192.168.1.50',
              prefixIcon: const Icon(Iconsax.global, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Find the IP in the ESP32-CAM Serial Monitor (e.g. http://192.168.1.50). '
            'Port 81 is added automatically.',
            style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: state.isStreaming
                ? OutlinedButton.icon(
                    onPressed: n.disconnect,
                    icon: const Icon(Iconsax.close_circle, size: 18),
                    label: const Text('Disconnect'),
                  )
                : FilledButton.icon(
                    onPressed: state.isConnecting ? null : n.connect,
                    icon: state.isConnecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Iconsax.play, size: 18),
                    label: Text(state.isConnecting ? 'Connecting…' : 'Connect'),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Live MJPEG view ──

class _LiveView extends StatelessWidget {
  const _LiveView();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 4 / 3, // ESP32-CAM QVGA is 320x240
        child: Container(
          color: Colors.black,
          child: StreamBuilder<Uint8List>(
            stream: EspCamService.instance.frameStream,
            builder: (context, snap) {
              if (snap.hasData) {
                return Image.memory(
                  snap.data!,
                  gaplessPlayback: true, // no flicker between frames
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                );
              }
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Iconsax.eye_slash, color: Colors.white38, size: 40),
                    SizedBox(height: 8),
                    Text('No video yet',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Shared bits ──

class _ToggleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _ToggleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: value ? AppColors.primarySurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value ? AppColors.primary : AppColors.border,
          width: value ? 1.2 : 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: value
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon,
                color: value ? AppColors.primary : AppColors.textTertiary,
                size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textTertiary)),
              ],
            ),
          ),
          Switch(value: value, onChanged: enabled ? onChanged : null),
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
            child: Text(message,
                style: const TextStyle(fontSize: 13, color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
