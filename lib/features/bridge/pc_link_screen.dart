import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/data/services/bridge_protocol.dart';
import 'package:brutus_app/data/services/desktop_bridge_service.dart';
import 'package:brutus_app/providers/desktop_bridge_provider.dart';

/// Phone Bridge — pair the phone with the Brutus desktop app over Wi-Fi so both
/// share one conversation and one live state.
class PcLinkScreen extends ConsumerStatefulWidget {
  const PcLinkScreen({super.key});

  @override
  ConsumerState<PcLinkScreen> createState() => _PcLinkScreenState();
}

class _PcLinkScreenState extends ConsumerState<PcLinkScreen> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '$kDefaultWsPort');
  final _codeCtrl = TextEditingController();
  bool _showManual = false;

  @override
  void initState() {
    super.initState();
    // Kick off a scan as soon as the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(desktopBridgeProvider.notifier).scan();
    });
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(desktopBridgeProvider);
    final notifier = ref.read(desktopBridgeProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Phone Bridge'),
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left_2, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _StatusCard(state: state, onDisconnect: notifier.disconnect),
            if (state.isConnected) ...[
              const SizedBox(height: 14),
              _DuetButton(
                active: state.duetActive,
                onToggle: () {
                  HapticFeedback.mediumImpact();
                  state.duetActive ? notifier.stopDuet() : notifier.startDuet();
                },
              ),
            ],
            const SizedBox(height: 20),
            _sectionLabel('FIND YOUR PC'),
            const SizedBox(height: 8),
            _DiscoverCard(
              state: state,
              onScan: notifier.scan,
              onPick: (host) => _promptCode(context, host),
            ),
            const SizedBox(height: 20),
            _ManualSection(
              expanded: _showManual,
              onToggle: () => setState(() => _showManual = !_showManual),
              hostCtrl: _hostCtrl,
              portCtrl: _portCtrl,
              codeCtrl: _codeCtrl,
              onConnect: () {
                final host = _hostCtrl.text.trim();
                final port = int.tryParse(_portCtrl.text.trim()) ?? kDefaultWsPort;
                final code = _codeCtrl.text.trim();
                if (host.isEmpty) return;
                HapticFeedback.mediumImpact();
                notifier.connect(host: host, port: port, code: code);
              },
            ),
            const SizedBox(height: 24),
            _helpCard(),
          ],
        ),
      ),
    );
  }

  Future<void> _promptCode(BuildContext context, DiscoveredHost host) async {
    _codeCtrl.clear();
    final connect = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Pair with ${host.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${host.host}:${host.wsPort}',
              style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 14),
            const Text(
              'Enter the 6-digit code shown on the PC (Settings → Phone Bridge).',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: host.requiresPairing,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(counterText: '', hintText: '000000'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Connect'),
          ),
        ],
      ),
    );

    if (connect == true) {
      HapticFeedback.mediumImpact();
      await ref
          .read(desktopBridgeProvider.notifier)
          .connectTo(host, _codeCtrl.text.trim());
    }
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textTertiary,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _helpCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.coolGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Iconsax.info_circle, size: 18, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.5),
                  children: [
                    TextSpan(
                      text: 'Same Wi-Fi required.\n',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    TextSpan(
                      text:
                          'On your PC, open Brutus → Settings → Phone Bridge and press Start. '
                          'It shows a 6-digit code. Scan finds it automatically; then enter the code here.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

// ── Duet button ───────────────────────────────────────────────────────────────
class _DuetButton extends StatelessWidget {
  final bool active;
  final VoidCallback onToggle;
  const _DuetButton({required this.active, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? [AppColors.error, AppColors.error.withValues(alpha: 0.7)]
                : [AppColors.primary, AppColors.maps],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (active ? AppColors.error : AppColors.primary).withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(active ? Iconsax.stop_circle : Iconsax.magicpen, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active ? 'Duet in progress…' : 'Start a Duet',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  Text(
                    active
                        ? 'Tap to stop the two Brutus selves'
                        : 'Let PC-Brutus & Robo-Brutus talk to each other',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
            if (active)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final DesktopBridgeState state;
  final Future<void> Function() onDisconnect;
  const _StatusCard({required this.state, required this.onDisconnect});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _look(state.conn);
    final connected = state.conn == BridgeConnState.connected;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: connected ? AppColors.heroGradient : null,
        color: connected ? null : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: connected ? null : Border.all(color: AppColors.border, width: 0.5),
        boxShadow: connected ? AppColors.primaryGlow : AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: connected
                      ? Colors.white.withValues(alpha: 0.2)
                      : color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: connected ? Colors.white : color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connected ? state.serverName : label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: connected ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      connected
                          ? _remoteLine(state)
                          : (state.error ?? 'Not linked to a PC yet'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: connected ? Colors.white70 : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (connected)
                TextButton(
                  onPressed: onDisconnect,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  child: const Text('Unlink'),
                ),
            ],
          ),
          if (connected && state.devices.length > 1) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: state.devices
                  .map((d) => _chip(d.name, d.role == 'host'))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  String _remoteLine(DesktopBridgeState s) {
    final st = s.remote?.status;
    if (st == null || st == 'idle') return 'Linked · sharing chat & state';
    return 'PC is $st…';
  }

  Widget _chip(String name, bool isHost) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isHost ? Iconsax.monitor : Iconsax.mobile, size: 12, color: Colors.white),
            const SizedBox(width: 6),
            Text(name,
                style: const TextStyle(
                    fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  (String, Color, IconData) _look(BridgeConnState c) {
    switch (c) {
      case BridgeConnState.connected:
        return ('Connected', AppColors.success, Iconsax.tick_circle);
      case BridgeConnState.connecting:
        return ('Connecting…', AppColors.warning, Iconsax.refresh);
      case BridgeConnState.discovering:
        return ('Searching…', AppColors.info, Iconsax.radar_2);
      case BridgeConnState.unauthorized:
        return ('Pairing rejected', AppColors.error, Iconsax.shield_cross);
      case BridgeConnState.error:
        return ('Connection error', AppColors.error, Iconsax.warning_2);
      case BridgeConnState.disconnected:
        return ('Not connected', AppColors.textTertiary, Iconsax.monitor);
    }
  }
}

// ── Discover card ─────────────────────────────────────────────────────────────
class _DiscoverCard extends StatelessWidget {
  final DesktopBridgeState state;
  final Future<void> Function() onScan;
  final void Function(DiscoveredHost host) onPick;
  const _DiscoverCard({required this.state, required this.onScan, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                const Icon(Iconsax.radar_2, size: 18, color: AppColors.maps),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Nearby computers',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ),
                if (state.scanning)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  TextButton.icon(
                    onPressed: onScan,
                    icon: const Icon(Iconsax.refresh, size: 15),
                    label: const Text('Scan'),
                  ),
              ],
            ),
          ),
          if (state.discovered.isEmpty && !state.scanning)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'No PCs found yet. Make sure Brutus Desktop is running with the bridge started, then Scan again.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary, height: 1.4),
              ),
            ),
          ...state.discovered.map((h) => _hostRow(context, h)),
        ],
      ),
    );
  }

  Widget _hostRow(BuildContext context, DiscoveredHost h) => InkWell(
        onTap: () => onPick(h),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.borderLight, width: 0.5)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Iconsax.monitor, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h.name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    Text('${h.host}:${h.wsPort}',
                        style:
                            const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
              ),
              if (h.requiresPairing)
                const Icon(Iconsax.lock_1, size: 15, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              const Icon(Iconsax.arrow_right_3, size: 16, color: AppColors.textTertiary),
            ],
          ),
        ),
      );
}

// ── Manual section ────────────────────────────────────────────────────────────
class _ManualSection extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final TextEditingController hostCtrl;
  final TextEditingController portCtrl;
  final TextEditingController codeCtrl;
  final VoidCallback onConnect;

  const _ManualSection({
    required this.expanded,
    required this.onToggle,
    required this.hostCtrl,
    required this.portCtrl,
    required this.codeCtrl,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(Iconsax.keyboard, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Enter address manually',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ),
                  Icon(expanded ? Iconsax.arrow_up_2 : Iconsax.arrow_down_1,
                      size: 16, color: AppColors.textTertiary),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: hostCtrl,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'PC IP address',
                            hintText: '192.168.1.42',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: portCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Port'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Pairing code',
                      counterText: '',
                      hintText: '6 digits from the PC',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onConnect,
                      icon: const Icon(Iconsax.link_21, size: 16),
                      label: const Text('Connect'),
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
