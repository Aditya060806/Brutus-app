import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:brutus_app/core/constants/api_constants.dart';
import 'package:brutus_app/data/services/bridge_protocol.dart';
import 'package:brutus_app/data/services/desktop_bridge_service.dart';
import 'package:brutus_app/providers/chat_provider.dart';
import 'package:brutus_app/providers/robot_provider.dart';

/// UI-facing snapshot of the desktop bridge link.
class DesktopBridgeState {
  final BridgeConnState conn;
  final String serverName;
  final String? host;
  final int? port;
  final List<DiscoveredHost> discovered;
  final List<BridgeDeviceInfo> devices;
  final BridgeRemoteState? remote;
  final bool scanning;
  final String? error;
  final bool duetActive;

  const DesktopBridgeState({
    this.conn = BridgeConnState.disconnected,
    this.serverName = 'Brutus PC',
    this.host,
    this.port,
    this.discovered = const [],
    this.devices = const [],
    this.remote,
    this.scanning = false,
    this.error,
    this.duetActive = false,
  });

  bool get isConnected => conn == BridgeConnState.connected;

  DesktopBridgeState copyWith({
    BridgeConnState? conn,
    String? serverName,
    String? host,
    int? port,
    List<DiscoveredHost>? discovered,
    List<BridgeDeviceInfo>? devices,
    BridgeRemoteState? remote,
    bool? scanning,
    String? error,
    bool? duetActive,
    bool clearError = false,
    bool clearRemote = false,
  }) {
    return DesktopBridgeState(
      conn: conn ?? this.conn,
      serverName: serverName ?? this.serverName,
      host: host ?? this.host,
      port: port ?? this.port,
      discovered: discovered ?? this.discovered,
      devices: devices ?? this.devices,
      remote: clearRemote ? null : (remote ?? this.remote),
      scanning: scanning ?? this.scanning,
      error: clearError ? null : (error ?? this.error),
      duetActive: duetActive ?? this.duetActive,
    );
  }
}

/// Owns the [DesktopBridgeService] and mirrors chat + live state between the
/// phone's [chatProvider] and a paired desktop. Loop-safe: messages injected
/// from the desktop are tagged so they are not echoed back.
class DesktopBridgeNotifier extends StateNotifier<DesktopBridgeState> {
  DesktopBridgeNotifier(this._ref) : super(const DesktopBridgeState()) {
    _init();
  }

  final Ref _ref;
  late final DesktopBridgeService _service;
  final List<StreamSubscription> _subs = [];
  ProviderSubscription<ChatState>? _chatSub;

  final Set<String> _publishedIds = {}; // local message ids already sent
  final Set<String> _injectedIds = {}; // remote message ids (never re-send)
  String _lastStateKey = '';

  Box get _prefs => Hive.box(ApiConstants.boxPreferences);

  Future<void> _init() async {
    // Stable per-install device identity.
    var id = _prefs.get('bridge_device_id') as String?;
    if (id == null || id.isEmpty) {
      id = 'ph-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 30)}';
      await _prefs.put('bridge_device_id', id);
    }
    final name = (_prefs.get('bridge_device_name') as String?) ?? 'Brutus Phone';

    _service = DesktopBridgeService(deviceId: id, deviceName: name);

    _subs.add(_service.connection.listen(_onConn));
    _subs.add(_service.incomingChat.listen(_onIncomingChat));
    _subs.add(_service.remoteState.listen((s) => state = state.copyWith(remote: s)));
    _subs.add(_service.devices.listen((d) => state = state.copyWith(devices: d)));
    _subs.add(_service.incomingCommand.listen(_onCommand));

    // Don't backfill existing history — only mirror messages from now on.
    for (final m in _ref.read(chatProvider).messages) {
      _publishedIds.add(m.id);
    }
    _chatSub = _ref.listen<ChatState>(chatProvider, _onChatChanged);

    // Auto-reconnect to the last paired PC.
    final host = _prefs.get('bridge_host') as String?;
    final port = _prefs.get('bridge_port') as int?;
    final code = _prefs.get('bridge_code') as String?;
    if (host != null && port != null && code != null) {
      await connect(host: host, port: port, code: code);
    }
  }

  // ── Public API (UI) ─────────────────────────────────────────────────────────
  Future<void> scan() async {
    state = state.copyWith(scanning: true, clearError: true);
    try {
      final hosts = await _service.discover();
      state = state.copyWith(discovered: hosts, scanning: false);
    } catch (e) {
      state = state.copyWith(scanning: false, error: e.toString());
    }
  }

  Future<void> connect({
    required String host,
    required int port,
    required String code,
  }) async {
    state = state.copyWith(host: host, port: port, clearError: true);
    await _prefs.put('bridge_host', host);
    await _prefs.put('bridge_port', port);
    await _prefs.put('bridge_code', code);
    await _service.connect(host: host, port: port, code: code);
  }

  Future<void> connectTo(DiscoveredHost host, String code) =>
      connect(host: host.host, port: host.wsPort, code: code);

  Future<void> disconnect() async {
    await _service.disconnect();
    await _prefs.delete('bridge_host');
    await _prefs.delete('bridge_port');
    await _prefs.delete('bridge_code');
    state = state.copyWith(clearRemote: true, duetActive: false);
  }

  // ── Duet Mode ────────────────────────────────────────────────────────────────
  /// Ask the desktop (the brain) to start a self-aware banter between the two
  /// Brutus instances. The PC generates every line; this phone voices its own.
  void startDuet() {
    if (!state.isConnected) return;
    _service.publishCommand({'name': 'duet', 'action': 'start', 'initiator': 'mobile'});
    state = state.copyWith(duetActive: true);
  }

  void stopDuet() {
    _service.publishCommand({'name': 'duet', 'action': 'stop', 'reason': 'user'});
    state = state.copyWith(duetActive: false);
  }

  void _onCommand(Map<String, dynamic> data) {
    if (data['name'] != 'duet') return;
    final action = data['action'];
    if (action == 'start') {
      state = state.copyWith(duetActive: true);
    } else if (action == 'stop') {
      state = state.copyWith(duetActive: false);
      _resetRobotAfterDuet();
    } else if (action == 'turn') {
      final text = (data['text'] ?? '').toString().trim();
      if (text.isEmpty) return;
      final speaker = (data['speaker'] ?? 'host').toString();
      final emotion = data['emotion']?.toString();
      state = state.copyWith(duetActive: true);
      // Display every line on the phone…
      final id = 'duet-${DateTime.now().microsecondsSinceEpoch}';
      _injectedIds.add(id);
      _publishedIds.add(id);
      _ref.read(chatProvider.notifier).injectRemoteMessage(
            role: MessageRole.assistant,
            text: text,
            id: id,
          );
      // …but only VOICE the lines that belong to this device (Robo-Brutus).
      // Speaking drives the physical robot's mouth via the playback pipeline.
      if (speaker == 'mobile') {
        _ref.read(chatProvider.notifier).speakText(text);
      }
      // Physical reaction: expression + LED, on top of mouth lip-sync.
      _driveRobot(speaker, emotion);
    }
  }

  /// Make the physical robot react during a duet. Robo-Brutus emotes on its own
  /// lines and glances attentively while PC-Brutus talks. No-ops if unpaired.
  void _driveRobot(String speaker, String? emotion) {
    final robot = _ref.read(robotProvider.notifier);
    if (speaker == 'mobile') {
      final expr = RobotExpression.fromEmotionTag(emotion) ?? RobotExpression.excited;
      robot.setExpression(expr);
    } else {
      robot.setExpression(RobotExpression.thinking);
      robot.lookAt(lr: 65, ud: 72);
    }
  }

  void _resetRobotAfterDuet() {
    final robot = _ref.read(robotProvider.notifier);
    robot.setExpression(RobotExpression.happy);
    robot.lookAt(lr: 90, ud: 90);
  }

  /// Detect a hands-free duet command in something the user just said/typed.
  void _maybeVoiceTriggerDuet(String raw) {
    final t = raw.toLowerCase().trim();
    if (t.isEmpty) return;
    final isStop = (t.contains('stop') || t.contains('end ') || t.contains('enough')) &&
        (t.contains('duet') || t.contains('talk'));
    if (isStop && state.duetActive) {
      stopDuet();
      return;
    }
    final isStart = t.contains('duet') ||
        RegExp(r'talk(ing)?\s+to\s+(each ?other|yourself|your other self|your ?self|itself|themselves)')
            .hasMatch(t) ||
        t.contains('talk amongst yourselves');
    if (isStart && !state.duetActive && state.isConnected) {
      startDuet();
    }
  }

  // ── Service → UI / chat ──────────────────────────────────────────────────────
  void _onConn(BridgeConnState c) {
    state = state.copyWith(
      conn: c,
      serverName: _service.serverName,
      error: c == BridgeConnState.unauthorized ? 'Pairing code rejected.' : null,
      clearError: c != BridgeConnState.unauthorized && c != BridgeConnState.error,
    );
    if (c == BridgeConnState.connected) {
      // Push our current state so the desktop face syncs immediately.
      _publishCurrentState(force: true);
    }
  }

  void _onIncomingChat(BridgeIncomingChat c) {
    final role = _roleFromWire(c.role);
    // Tag BEFORE injecting so the chat listener skips re-publishing it.
    final id = 'rm-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
    _injectedIds.add(id);
    _publishedIds.add(id);
    _ref.read(chatProvider.notifier).injectRemoteMessage(
          role: role,
          text: c.text,
          id: id,
        );
  }

  // ── Local chat → desktop ─────────────────────────────────────────────────────
  void _onChatChanged(ChatState? prev, ChatState next) {
    // 1) Mirror any brand-new local messages.
    for (final m in next.messages) {
      if (_publishedIds.contains(m.id)) continue;
      _publishedIds.add(m.id);
      if (_injectedIds.contains(m.id)) continue; // came from the desktop
      if (m.role == MessageRole.tool) continue;
      // Hands-free Duet trigger from what the user said/typed on the phone.
      if (m.role == MessageRole.user) _maybeVoiceTriggerDuet(m.text);
      _service.publishChat(
        role: _wireFromRole(m.role),
        text: m.text,
        emotion: m.role == MessageRole.assistant ? next.detectedEmotion : null,
      );
    }
    // 2) Mirror live voice state (throttled by change).
    _publishCurrentState(next: next);
  }

  void _publishCurrentState({ChatState? next, bool force = false}) {
    final ChatState s = next ?? _ref.read(chatProvider);
    final String status = s.status.name;
    final String? emotion = s.detectedEmotion;
    final key = '$status|${emotion ?? ''}';
    if (!force && key == _lastStateKey) return;
    _lastStateKey = key;
    _service.publishState(status: status, emotion: emotion);
  }

  MessageRole _roleFromWire(String r) {
    switch (r) {
      case BridgeRole.user:
        return MessageRole.user;
      case BridgeRole.tool:
        return MessageRole.tool;
      default:
        return MessageRole.assistant;
    }
  }

  String _wireFromRole(MessageRole r) {
    switch (r) {
      case MessageRole.user:
        return BridgeRole.user;
      case MessageRole.tool:
        return BridgeRole.tool;
      case MessageRole.assistant:
        return BridgeRole.assistant;
    }
  }

  @override
  void dispose() {
    _chatSub?.close();
    for (final s in _subs) {
      s.cancel();
    }
    _service.dispose();
    super.dispose();
  }
}

final desktopBridgeProvider =
    StateNotifierProvider<DesktopBridgeNotifier, DesktopBridgeState>((ref) {
  return DesktopBridgeNotifier(ref);
});
