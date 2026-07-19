/// BRUTUS Desktop Bridge — shared wire protocol (Flutter client side)
/// -------------------------------------------------------------------
/// Mirror of the desktop host's `src/main/services/bridge-protocol.ts`. Keep the
/// two in lockstep. Every WebSocket frame is a single JSON [BridgeEnvelope].
library;

const int kBridgeProtocolVersion = 1;

/// UDP port the host listens on for discovery requests.
const int kDiscoveryPort = 48752;

/// Default TCP port for the host's WebSocket sync server.
const int kDefaultWsPort = 48753;

/// Magic payload broadcast to find hosts on the LAN.
const String kDiscoveryRequest = 'BRUTUS_BRIDGE_DISCOVER_V1';

/// Marker the host puts in its discovery reply.
const String kDiscoveryMagic = 'brutus-bridge';

/// Message types carried in [BridgeEnvelope.t].
class BridgeMsg {
  static const hello = 'hello';
  static const welcome = 'welcome';
  static const unauthorized = 'unauthorized';
  static const ping = 'ping';
  static const pong = 'pong';
  static const presence = 'presence';
  static const chat = 'chat';
  static const state = 'state';
  static const robot = 'robot';
  static const command = 'command';
  static const error = 'error';
}

/// Roles are normalised across desktop ('model') and mobile ('assistant').
class BridgeRole {
  static const user = 'user';
  static const assistant = 'assistant';
  static const tool = 'tool';
}

class BridgeEnvelope {
  final int v;
  final String t;
  final String id;
  final int ts;
  final String src;
  final Map<String, dynamic> data;

  const BridgeEnvelope({
    required this.v,
    required this.t,
    required this.id,
    required this.ts,
    required this.src,
    required this.data,
  });

  static int _counter = 0;

  factory BridgeEnvelope.build(String type, String src, Map<String, dynamic> data) {
    _counter = (_counter + 1) % 1000000;
    final now = DateTime.now().millisecondsSinceEpoch;
    return BridgeEnvelope(
      v: kBridgeProtocolVersion,
      t: type,
      id: '${now.toRadixString(36)}-${_counter.toRadixString(36)}',
      ts: now,
      src: src,
      data: data,
    );
  }

  Map<String, dynamic> toJson() => {
        'v': v,
        't': t,
        'id': id,
        'ts': ts,
        'src': src,
        'data': data,
      };

  /// Parse + shallow-validate. Returns null on anything bogus.
  static BridgeEnvelope? tryParse(dynamic raw) {
    try {
      if (raw is! Map) return null;
      final t = raw['t'];
      final v = raw['v'];
      if (t is! String || v is! num) return null;
      final data = raw['data'];
      return BridgeEnvelope(
        v: v.toInt(),
        t: t,
        id: (raw['id'] ?? '').toString(),
        ts: (raw['ts'] is num) ? (raw['ts'] as num).toInt() : 0,
        src: (raw['src'] ?? '').toString(),
        data: data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
      );
    } catch (_) {
      return null;
    }
  }
}

/// A host discovered on the LAN via UDP.
class DiscoveredHost {
  final String id;
  final String name;
  final String host;
  final int wsPort;
  final String platform;
  final bool requiresPairing;

  const DiscoveredHost({
    required this.id,
    required this.name,
    required this.host,
    required this.wsPort,
    required this.platform,
    required this.requiresPairing,
  });

  String get wsUrl => 'ws://$host:$wsPort';

  factory DiscoveredHost.fromReply(Map<String, dynamic> json, String host) {
    return DiscoveredHost(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Brutus PC').toString(),
      host: host,
      wsPort: (json['ws'] is num) ? (json['ws'] as num).toInt() : kDefaultWsPort,
      platform: (json['platform'] ?? 'desktop').toString(),
      requiresPairing: json['requiresPairing'] == true,
    );
  }
}
