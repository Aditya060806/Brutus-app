import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:brutus_app/data/services/bridge_protocol.dart';

/// Connection lifecycle for the desktop bridge link.
enum BridgeConnState {
  disconnected,
  discovering,
  connecting,
  connected,
  unauthorized,
  error,
}

/// A chat message arriving from the desktop (or another paired device).
class BridgeIncomingChat {
  final String role; // user | assistant | tool
  final String text;
  final String? emotion;
  final String origin; // host | mobile
  const BridgeIncomingChat({
    required this.role,
    required this.text,
    this.emotion,
    this.origin = 'host',
  });
}

/// The desktop's live AI/voice state.
class BridgeRemoteState {
  final String status; // idle | listening | thinking | speaking | ...
  final String? emotion;
  final String? engine;
  const BridgeRemoteState({required this.status, this.emotion, this.engine});
}

class BridgeDeviceInfo {
  final String id;
  final String name;
  final String platform;
  final String role; // host | mobile
  final bool online;
  const BridgeDeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.role,
    required this.online,
  });

  factory BridgeDeviceInfo.fromJson(Map<String, dynamic> j) => BridgeDeviceInfo(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? 'Device').toString(),
        platform: (j['platform'] ?? '').toString(),
        role: (j['role'] ?? 'mobile').toString(),
        online: j['online'] != false,
      );
}

/// BRUTUS — Desktop Bridge client
/// ------------------------------
/// Finds the Command PC over UDP, opens a paired WebSocket to it, and keeps it
/// alive (heartbeat + auto-reconnect). Chat + state flow both ways through here.
/// Mirror of the desktop host in `Brutus-AI/src/main/services/desktop-bridge.ts`.
class DesktopBridgeService {
  DesktopBridgeService({required this.deviceId, required this.deviceName});

  final String deviceId;
  final String deviceName;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;

  bool _paired = false;
  bool _userClosed = false;
  DateTime _lastRx = DateTime.now();
  int _reconnectAttempts = 0;

  String? _host;
  int? _port;
  String? _code;
  String _serverName = 'Brutus PC';

  // ── Streams (broadcast so multiple listeners / provider + UI can attach) ──
  final _connCtrl = StreamController<BridgeConnState>.broadcast();
  final _chatCtrl = StreamController<BridgeIncomingChat>.broadcast();
  final _stateCtrl = StreamController<BridgeRemoteState>.broadcast();
  final _devicesCtrl = StreamController<List<BridgeDeviceInfo>>.broadcast();
  final _commandCtrl = StreamController<Map<String, dynamic>>.broadcast();

  Stream<BridgeConnState> get connection => _connCtrl.stream;
  Stream<BridgeIncomingChat> get incomingChat => _chatCtrl.stream;
  Stream<BridgeRemoteState> get remoteState => _stateCtrl.stream;
  Stream<List<BridgeDeviceInfo>> get devices => _devicesCtrl.stream;

  /// Generic cross-device commands (e.g. Duet Mode control messages).
  Stream<Map<String, dynamic>> get incomingCommand => _commandCtrl.stream;

  BridgeConnState _conn = BridgeConnState.disconnected;
  BridgeConnState get connState => _conn;
  bool get isConnected => _conn == BridgeConnState.connected;
  String get serverName => _serverName;
  String? get host => _host;
  int? get port => _port;

  void _setConn(BridgeConnState s) {
    _conn = s;
    if (!_connCtrl.isClosed) _connCtrl.add(s);
  }

  // ── Discovery ──────────────────────────────────────────────────────────────
  /// Broadcast a discovery probe and collect host replies for [timeout].
  Future<List<DiscoveredHost>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    // Don't disturb a live link while scanning for others.
    if (_conn != BridgeConnState.connected) _setConn(BridgeConnState.discovering);
    final found = <String, DiscoveredHost>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final probe = utf8.encode(kDiscoveryRequest);
      final targets = await _broadcastTargets();

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket!.receive();
        if (dg == null) return;
        try {
          final decoded = jsonDecode(utf8.decode(dg.data));
          if (decoded is Map && decoded['magic'] == kDiscoveryMagic) {
            final host = DiscoveredHost.fromReply(
              Map<String, dynamic>.from(decoded),
              dg.address.address,
            );
            found[host.id.isNotEmpty ? host.id : host.host] = host;
          }
        } catch (_) {/* ignore malformed */}
      });

      // A few bursts to survive dropped UDP packets.
      for (var i = 0; i < 3; i++) {
        for (final t in targets) {
          try {
            socket.send(probe, InternetAddress(t), kDiscoveryPort);
          } catch (_) {/* interface may not allow this target */}
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
      await Future.delayed(timeout);
    } catch (e) {
      dev.log('discover failed: $e', name: 'Bridge');
    } finally {
      socket?.close();
    }

    if (_conn == BridgeConnState.discovering) {
      _setConn(_paired ? BridgeConnState.connected : BridgeConnState.disconnected);
    }
    return found.values.toList();
  }

  Future<List<String>> _broadcastTargets() async {
    final targets = <String>{'255.255.255.255'};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255'); // assume /24
          }
        }
      }
    } catch (_) {/* fall back to global broadcast */}
    return targets.toList();
  }

  // ── Connect / disconnect ─────────────────────────────────────────────────────
  Future<void> connect({
    required String host,
    required int port,
    required String code,
  }) async {
    await _teardownSocket();
    _host = host;
    _port = port;
    _code = code;
    _userClosed = false;
    _paired = false;
    _setConn(BridgeConnState.connecting);

    try {
      final channel = WebSocketChannel.connect(Uri.parse('ws://$host:$port'));
      _channel = channel;
      await channel.ready;

      _lastRx = DateTime.now();
      _sub = channel.stream.listen(
        _onMessage,
        onDone: _onDone,
        onError: (_) => _onDone(),
        cancelOnError: true,
      );

      // Announce ourselves + present the pairing code.
      _send(BridgeEnvelope.build(BridgeMsg.hello, deviceId, {
        'token': code,
        'protocol': kBridgeProtocolVersion,
        'device': {
          'id': deviceId,
          'name': deviceName,
          'platform': 'android',
          'role': 'mobile',
        },
      }));
      _startHeartbeat();
    } catch (e) {
      dev.log('connect failed: $e', name: 'Bridge');
      _setConn(BridgeConnState.error);
      _scheduleReconnect();
    }
  }

  /// Disconnect and stop auto-reconnecting (user-initiated).
  Future<void> disconnect() async {
    _userClosed = true;
    _reconnect?.cancel();
    await _teardownSocket();
    _paired = false;
    _setConn(BridgeConnState.disconnected);
  }

  Future<void> _teardownSocket() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {/* ignore */}
    _channel = null;
  }

  // ── Publishing (mobile → desktop) ────────────────────────────────────────────
  void publishChat({required String role, required String text, String? emotion}) {
    if (!isConnected || text.trim().isEmpty) return;
    _send(BridgeEnvelope.build(BridgeMsg.chat, deviceId, {
      'messageId': 'ph-${DateTime.now().millisecondsSinceEpoch}',
      'role': role,
      'text': text,
      'emotion': emotion,
      'origin': 'mobile',
    }));
  }

  void publishState({required String status, String? emotion, String? engine}) {
    if (!isConnected) return;
    _send(BridgeEnvelope.build(BridgeMsg.state, deviceId, {
      'status': status,
      'emotion': emotion,
      'engine': engine,
    }));
  }

  /// Send a generic command (e.g. Duet Mode control) to the desktop / room.
  void publishCommand(Map<String, dynamic> data) {
    if (!isConnected) return;
    _send(BridgeEnvelope.build(BridgeMsg.command, deviceId, data));
  }

  void _send(BridgeEnvelope env) {
    try {
      _channel?.sink.add(jsonEncode(env.toJson()));
    } catch (e) {
      dev.log('send failed: $e', name: 'Bridge');
    }
  }

  // ── Incoming (desktop → mobile) ──────────────────────────────────────────────
  void _onMessage(dynamic raw) {
    _lastRx = DateTime.now();
    dynamic decoded;
    try {
      decoded = jsonDecode(raw is String ? raw : utf8.decode(raw as List<int>));
    } catch (_) {
      return;
    }
    final env = BridgeEnvelope.tryParse(decoded);
    if (env == null) return;

    switch (env.t) {
      case BridgeMsg.welcome:
        _paired = true;
        _reconnectAttempts = 0;
        final server = env.data['server'];
        if (server is Map && server['name'] != null) {
          _serverName = server['name'].toString();
        }
        _setConn(BridgeConnState.connected);
        final st = env.data['state'];
        if (st is Map) {
          _stateCtrl.add(BridgeRemoteState(
            status: (st['status'] ?? 'idle').toString(),
            emotion: st['emotion']?.toString(),
            engine: st['engine']?.toString(),
          ));
        }
        break;

      case BridgeMsg.unauthorized:
        _userClosed = true; // bad code — don't hammer reconnect
        _setConn(BridgeConnState.unauthorized);
        _teardownSocket();
        break;

      case BridgeMsg.ping:
        _send(BridgeEnvelope.build(BridgeMsg.pong, deviceId, {
          't0': env.data['t0'],
        }));
        break;

      case BridgeMsg.pong:
        break; // liveness already refreshed via _lastRx

      case BridgeMsg.presence:
        final list = env.data['devices'];
        if (list is List) {
          _devicesCtrl.add(list
              .whereType<Map>()
              .map((m) => BridgeDeviceInfo.fromJson(Map<String, dynamic>.from(m)))
              .toList());
        }
        break;

      case BridgeMsg.chat:
        final text = (env.data['text'] ?? '').toString();
        if (text.trim().isEmpty) return;
        _chatCtrl.add(BridgeIncomingChat(
          role: (env.data['role'] ?? 'assistant').toString(),
          text: text,
          emotion: env.data['emotion']?.toString(),
          origin: (env.data['origin'] ?? 'host').toString(),
        ));
        break;

      case BridgeMsg.state:
        _stateCtrl.add(BridgeRemoteState(
          status: (env.data['status'] ?? 'idle').toString(),
          emotion: env.data['emotion']?.toString(),
          engine: env.data['engine']?.toString(),
        ));
        break;

      case BridgeMsg.command:
        _commandCtrl.add(env.data);
        break;

      default:
        break;
    }
  }

  void _onDone() {
    if (_userClosed) return;
    _paired = false;
    _setConn(BridgeConnState.disconnected);
    _scheduleReconnect();
  }

  // ── Heartbeat + reconnect ────────────────────────────────────────────────────
  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      // No traffic for 30s → assume the link died and cycle it.
      if (DateTime.now().difference(_lastRx) > const Duration(seconds: 30)) {
        _onDone();
        return;
      }
      _send(BridgeEnvelope.build(BridgeMsg.ping, deviceId, {
        't0': DateTime.now().millisecondsSinceEpoch,
      }));
    });
  }

  void _scheduleReconnect() {
    if (_userClosed || _host == null || _port == null || _code == null) return;
    _reconnect?.cancel();
    _reconnectAttempts++;
    // Backoff 2s → 4s → 6s … capped at 20s.
    final delay = Duration(seconds: (2 * _reconnectAttempts).clamp(2, 20));
    _reconnect = Timer(delay, () {
      if (_userClosed) return;
      connect(host: _host!, port: _port!, code: _code!);
    });
  }

  Future<void> dispose() async {
    _userClosed = true;
    _reconnect?.cancel();
    await _teardownSocket();
    await _connCtrl.close();
    await _chatCtrl.close();
    await _stateCtrl.close();
    await _devicesCtrl.close();
    await _commandCtrl.close();
  }
}
