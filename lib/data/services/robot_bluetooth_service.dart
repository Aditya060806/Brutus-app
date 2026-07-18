import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Brutus — Robot Bluetooth (BLE) Service
///
/// Pure-Dart BLE bridge to the HM-10 module on the robot's Arduino.
/// Replaces the old MethodChannel → Kotlin → Brutus Link → SerialService
/// (classic SPP) stack with a direct GATT connection.
///
/// HM-10 GATT profile:
///   Service:        0000FFE0-0000-1000-8000-00805F9B34FB
///   Characteristic: 0000FFE1-0000-1000-8000-00805F9B34FB  (read/write/notify)
///
/// Protocol:
///   `E<n>`         set expression (0..5)
///   `E<n>,<i>`     set expression with intensity (0..100)
///   `M<a>`         set mouth angle (0..180)
///   `L<lr>,<ud>`   look at
///   `B`            blink
///   `I<0|1>`       idle fallback
///   `S<0|1>`       freeze mode
///   `H`            heartbeat — expects "OK\n"
///   `A<n>`         play animation macro (0..9)
///   `W<n>`         play movement trick (0..9)
///   `C<n>`         set LED pattern (0=off,1=solid,2=pulse,3=fast)
class RobotBluetoothService {
  static final RobotBluetoothService _instance = RobotBluetoothService._();
  static RobotBluetoothService get instance => _instance;
  RobotBluetoothService._();

  // ── HM-10 GATT UUIDs ──
  static final _serviceUuid =
      Guid('0000FFE0-0000-1000-8000-00805F9B34FB');
  static final _characteristicUuid =
      Guid('0000FFE1-0000-1000-8000-00805F9B34FB');

  // Common HM-10 advertising names (varies by clone vendor). Used to flag
  // scan results that are probably the robot so the UI can surface them
  // above phones/earbuds/watches in the discovery list.
  static const _knownNames = [
    'hmsoft',
    'bt05',
    'mlt-bt05',
    'dsd tech',
    'hm-10',
    'brutus',
    'ble',
    'cc41-a',
    'jdy-08',
    'jdy-10',
  ];

  /// True when [name] matches a known HM-10 / BLE-serial module name.
  static bool _isLikelyRobotName(String name) {
    final lower = name.toLowerCase();
    return _knownNames.any(lower.contains);
  }

  // ── State ──
  BluetoothDevice? _device;
  BluetoothCharacteristic? _ffe1;
  RobotConnectionState _connectionState = RobotConnectionState.disconnected;

  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _heartbeatTimer;

  // ── Stream controllers ──
  final _connectionController =
      StreamController<RobotConnectionState>.broadcast();
  final _messageController = StreamController<String>.broadcast();
  final _discoveryController = StreamController<BleDevice>.broadcast();
  final _scanEventController = StreamController<RobotScanEvent>.broadcast();
  final _connectErrorController = StreamController<String>.broadcast();

  Stream<RobotConnectionState> get connectionStream =>
      _connectionController.stream;
  Stream<String> get messageStream => _messageController.stream;
  Stream<BleDevice> get discoveryStream => _discoveryController.stream;
  Stream<RobotScanEvent> get scanEventStream => _scanEventController.stream;
  Stream<String> get connectErrorStream => _connectErrorController.stream;

  bool get isConnected => _connectionState == RobotConnectionState.connected;

  // ── Mouth rate-limiting (same as old SPP service) ──
  int _lastMouthAngle = -1;
  DateTime _lastMouthAt = DateTime(2000);
  static const _mouthMinInterval = Duration(milliseconds: 25); // ~40 Hz
  static const _mouthDeadZone = 3; // degrees

  // ── Eye (lookAt) rate-limiting ──
  // The joystick fires on every pointer-move — without a throttle this
  // floods the slow HM-10 link (20-byte MTU), making the eyes lag/stutter
  // and delaying other commands (like animations) queued behind it.
  int _lastLr = -1;
  int _lastUd = -1;
  DateTime _lastLookAt = DateTime(2000);
  static const _lookMinInterval = Duration(milliseconds: 33); // ~30 Hz
  static const _lookDeadZone = 4; // degrees

  // ── Line buffer for incoming data ──
  String _lineBuffer = '';

  void _log(String msg) => dev.log('[BLE] $msg', name: 'BrutusAI');

  // ═══════════════════════════════════════════════════════════════════
  //  PERMISSIONS & ADAPTER
  // ═══════════════════════════════════════════════════════════════════

  Future<bool> isSupported() async {
    return FlutterBluePlus.isSupported;
  }

  Future<bool> isEnabled() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  /// Request BLUETOOTH_CONNECT + BLUETOOTH_SCAN.
  /// flutter_blue_plus handles the permission check internally on
  /// first scan/connect, but we call this explicitly so the UI can
  /// react before the user taps a device.
  Future<bool> ensurePermissions() async {
    try {
      // On Android 12+, startScan triggers the permission request.
      // We do a 0-second scan just to prompt the dialog.
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 0));
      await FlutterBluePlus.stopScan();
      return true;
    } catch (e) {
      _log('Permission check failed: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SCANNING
  // ═══════════════════════════════════════════════════════════════════

  Future<void> startScan() async {
    _log('Starting BLE scan...');
    _scanEventController.add(RobotScanEvent.started);

    // Cancel any previous scan subscription
    await _scanSub?.cancel();

    _scanSub = FlutterBluePlus.onScanResults.listen(
      (results) {
        for (final r in results) {
          final name = r.advertisementData.advName.isNotEmpty
              ? r.advertisementData.advName
              : r.device.platformName;
          final device = BleDevice(
            name: name.isNotEmpty ? name : 'Unknown',
            address: r.device.remoteId.str,
            rssi: r.rssi,
            likelyRobot: _isLikelyRobotName(name) ||
                r.advertisementData.serviceUuids.contains(_serviceUuid),
          );
          _discoveryController.add(device);
        }
      },
      onError: (e) => _log('Scan error: $e'),
    );

    try {
      await FlutterBluePlus.startScan(
        withServices: [_serviceUuid],
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      _log('startScan failed: $e — retrying without service filter');
      // Some HM-10 clones don't advertise FFE0. Fall back to name-based scan.
      try {
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 15),
        );
      } catch (e2) {
        _log('startScan (unfiltered) also failed: $e2');
      }
    }

    // When scan completes (timeout or stopScan), emit finished.
    FlutterBluePlus.isScanning
        .where((scanning) => !scanning)
        .first
        .then((_) {
      _scanEventController.add(RobotScanEvent.complete);
    });
  }

  Future<void> stopScan() async {
    _log('Stopping BLE scan');
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      _log('stopScan failed: $e');
    }
    _scanEventController.add(RobotScanEvent.complete);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CONNECT / DISCONNECT
  // ═══════════════════════════════════════════════════════════════════

  Future<bool> connect(String address) async {
    _log('Connecting to $address...');
    _setConnectionState(RobotConnectionState.connecting);

    try {
      _device = BluetoothDevice.fromId(address);

      // Listen for disconnection.
      // IMPORTANT: only react to 'disconnected' once we are actually connected.
      // connectionState emits its current value immediately on subscribe — if the
      // device isn't connected yet that initial emit is 'disconnected', which
      // would call _onDisconnected() and null _device before discoverServices().
      await _connectionSub?.cancel();
      _connectionSub = _device!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected &&
            _connectionState == RobotConnectionState.connected) {
          _log('BLE disconnected: ${_device?.disconnectReason?.description}');
          _onDisconnected();
        }
      });

      // Connect with a timeout
      await _device!.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
      );

      _log('Connected — discovering services...');

      // Discover services and find FFE0/FFE1
      final services = await _device!.discoverServices();
      BluetoothCharacteristic? ffe1;

      for (final service in services) {
        if (service.serviceUuid == _serviceUuid) {
          for (final c in service.characteristics) {
            if (c.characteristicUuid == _characteristicUuid) {
              ffe1 = c;
              break;
            }
          }
        }
      }

      if (ffe1 == null) {
        _log('FFE1 characteristic not found!');
        _connectErrorController.add(
            'Device connected but HM-10 serial service not found. '
            'Make sure this is an HM-10 BLE module.');
        await _device!.disconnect();
        _setConnectionState(RobotConnectionState.disconnected);
        return false;
      }

      _ffe1 = ffe1;

      // Enable notifications (for heartbeat "OK\n" replies)
      await _notifySub?.cancel();
      _notifySub = ffe1.onValueReceived.listen(_onData);
      await ffe1.setNotifyValue(true);

      _setConnectionState(RobotConnectionState.connected);
      _log('BLE ready — FFE1 characteristic found, notifications on');

      // Start heartbeat
      _startHeartbeat();

      return true;
    } catch (e) {
      _log('Connect failed: $e');
      _connectErrorController.add(e.toString());
      _setConnectionState(RobotConnectionState.disconnected);
      return false;
    }
  }

  Future<void> disconnect() async {
    _log('Disconnecting...');
    _stopHeartbeat();
    await _notifySub?.cancel();
    _notifySub = null;
    try {
      await _device?.disconnect();
    } catch (e) {
      _log('Disconnect error: $e');
    }
    _ffe1 = null;
    _device = null;
    _setConnectionState(RobotConnectionState.disconnected);
  }

  void _onDisconnected() {
    _stopHeartbeat();
    _notifySub?.cancel();
    _notifySub = null;
    _ffe1 = null;
    _device = null;
    _setConnectionState(RobotConnectionState.disconnected);
  }

  void _setConnectionState(RobotConnectionState state) {
    if (_connectionState == state) return;
    _connectionState = state;
    if (!_connectionController.isClosed) {
      _connectionController.add(state);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DATA IN (notifications from HM-10)
  // ═══════════════════════════════════════════════════════════════════

  void _onData(List<int> data) {
    if (data.isEmpty) return;
    final chunk = utf8.decode(data, allowMalformed: true);
    _lineBuffer += chunk;

    // Process complete lines
    while (_lineBuffer.contains('\n')) {
      final idx = _lineBuffer.indexOf('\n');
      final line = _lineBuffer.substring(0, idx).trim();
      _lineBuffer = _lineBuffer.substring(idx + 1);

      if (line.isNotEmpty) {
        if (!_messageController.isClosed) {
          _messageController.add(line);
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  WRITE (commands to HM-10 → Arduino)
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _write(String command) async {
    final c = _ffe1;
    if (c == null) return;
    try {
      // withoutResponse = true for speed (mouth commands at 40Hz).
      // HM-10 MTU is 20 bytes — all our commands are ≤ 8 bytes.
      await c.write(
        utf8.encode(command),
        withoutResponse: true,
      );
    } catch (e) {
      _log('Write failed: $e');
    }
  }

  // ── Protocol commands ──

  Future<void> setExpression(int mode) async {
    if (!isConnected) return;
    await _write('E$mode\n');
  }

  /// Mouth servo — rate-limited to ~40 Hz with a 3° dead zone.
  /// The same logic from the old SPP service to prevent servo jitter
  /// over the wireless link.
  Future<void> setMouth(int angle, {bool force = false}) async {
    if (!isConnected) return;
    final clamped = angle.clamp(0, 180);

    if (!force) {
      // Dead zone: skip if the angle hasn't changed enough
      if (_lastMouthAngle >= 0 &&
          (clamped - _lastMouthAngle).abs() < _mouthDeadZone) {
        return;
      }
      // Rate limit: skip if we sent one too recently
      final now = DateTime.now();
      if (now.difference(_lastMouthAt) < _mouthMinInterval) {
        return;
      }
      _lastMouthAt = now;
    }

    _lastMouthAngle = clamped;
    await _write('M$clamped\n');
  }

  Future<void> closeMouth() async {
    _lastMouthAngle = 90;
    await _write('M90\n');
  }

  /// Eye look — rate-limited to ~30 Hz with a 4° dead zone so the joystick
  /// can't flood the BLE link. Pass [force] for one-off moves (re-center,
  /// voice-status) that must always land.
  Future<void> lookAt({
    required int lr,
    required int ud,
    bool force = false,
  }) async {
    if (!isConnected) return;
    final clampedLR = lr.clamp(0, 180);
    final clampedUD = ud.clamp(0, 180);

    if (!force) {
      if (_lastLr >= 0 &&
          (clampedLR - _lastLr).abs() < _lookDeadZone &&
          (clampedUD - _lastUd).abs() < _lookDeadZone) {
        return;
      }
      final now = DateTime.now();
      if (now.difference(_lastLookAt) < _lookMinInterval) return;
      _lastLookAt = now;
    }

    _lastLr = clampedLR;
    _lastUd = clampedUD;
    await _write('L$clampedLR,$clampedUD\n');
  }

  Future<void> blink() async {
    if (!isConnected) return;
    await _write('B\n');
  }

  Future<void> setIdleFallback(bool on) async {
    if (!isConnected) return;
    await _write('I${on ? 1 : 0}\n');
  }

  /// Freeze / still mode — disables ALL autonomous Arduino behavior.
  /// Only BLE commands can move the servos when frozen.
  Future<void> setFreezeMode(bool on) async {
    if (!isConnected) return;
    await _write('S${on ? 1 : 0}\n');
  }

  // ── New: Animation macros, movement tricks, intensity, LED ──

  /// Play a pre-baked animation macro on the Arduino.
  /// Index 0..9: nod, shake, look-around, wink, yawn, laugh,
  ///             eye-roll, mouth-cycle, eye-cycle, wiggle.
  Future<void> playAnimation(int index) async {
    if (!isConnected) return;
    await _write('A$index\n');
  }

  /// Play a movement trick on the Arduino.
  /// Index 0..9: crazy-eyes, chatter, slow-scan, peek-a-boo,
  ///             double-blink, jaw-drop, drowsy, side-eye,
  ///             happy-bounce, confused.
  Future<void> playMovementTrick(int index) async {
    if (!isConnected) return;
    await _write('W$index\n');
  }

  /// Set expression with intensity (0–100).
  /// intensity=0 → neutral face, intensity=100 → full expression.
  Future<void> setExpressionWithIntensity(int mode, int intensity) async {
    if (!isConnected) return;
    final clamped = intensity.clamp(0, 100);
    await _write('E$mode,$clamped\n');
  }

  /// Set LED blink pattern on D8.
  /// 0=off, 1=solid, 2=slow pulse, 3=fast blink.
  Future<void> setLedPattern(int pattern) async {
    if (!isConnected) return;
    final clamped = pattern.clamp(0, 3);
    await _write('C$clamped\n');
  }

  // ═══════════════════════════════════════════════════════════════════
  //  HEARTBEAT
  // ═══════════════════════════════════════════════════════════════════

  static const _heartbeatInterval = Duration(seconds: 2);

  void _startHeartbeat() {
    _stopHeartbeat();
    // Send H\n every 2 s to keep the HM-10 link alive.
    // We do NOT disconnect on missing replies — many HM-10 clones (BT05)
    // echo our own writes back as onCharacteristicChanged events, making
    // it impossible to distinguish a real 'OK\n' reply from an echo.
    // Real disconnection is handled by the Android GATT stack which fires
    // connectionState → disconnected when the link is truly lost.
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (!isConnected) return;
      _write('H\n');
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════

  void dispose() {
    _stopHeartbeat();
    _connectionSub?.cancel();
    _notifySub?.cancel();
    _scanSub?.cancel();
    _connectionController.close();
    _messageController.close();
    _discoveryController.close();
    _scanEventController.close();
    _connectErrorController.close();
    try {
      _device?.disconnect();
    } catch (_) {}
  }
}

// ═══════════════════════════════════════════════════════════════════
//  DATA MODELS
// ═══════════════════════════════════════════════════════════════════

enum RobotConnectionState { disconnected, connecting, connected }

enum RobotScanEvent { started, complete }

/// Discovered BLE device. Replaces the old RobotPairedDevice (no bonding
/// concept in BLE for HM-10 — it just connects directly).
class BleDevice {
  final String name;
  final String address;
  final int? rssi;

  /// True when the advertised name or service UUID matches a known
  /// HM-10-style serial module — almost certainly the robot.
  final bool likelyRobot;

  const BleDevice({
    required this.name,
    required this.address,
    this.rssi,
    this.likelyRobot = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleDevice && address == other.address;

  @override
  int get hashCode => address.hashCode;
}
