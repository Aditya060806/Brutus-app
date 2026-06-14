import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:brutus_app/core/constants/api_constants.dart';
import 'package:brutus_app/data/services/audio_playback_service.dart';
import 'package:brutus_app/data/services/robot_bluetooth_service.dart';
import 'package:brutus_app/providers/chat_provider.dart';

// ── Robot expressions (mirrors Arduino firmware) ──
class RobotExpression {
  RobotExpression._();
  static const happy = 0;
  static const angry = 1;
  static const sad = 2;
  static const thinking = 3;
  static const sleepy = 4;
  static const surprised = 5;

  /// Map an emotion string (from Gemini's [EMOTION:xxx] tag) to a constant.
  static int? fromEmotionTag(String? tag) {
    if (tag == null || tag.isEmpty) return null;
    switch (tag.toLowerCase()) {
      case 'happy':
        return happy;
      case 'angry':
        return angry;
      case 'sad':
        return sad;
      case 'thinking':
        return thinking;
      case 'sleepy':
        return sleepy;
      case 'surprised':
        return surprised;
      default:
        return null;
    }
  }

  /// Map an expression to an LED pattern.
  /// happy→solid, angry→fast, sad→pulse, thinking→pulse,
  /// sleepy→off, surprised→fast.
  static int toLedPattern(int expr) {
    switch (expr) {
      case happy:
        return RobotLedPattern.solid;
      case angry:
        return RobotLedPattern.fastBlink;
      case sad:
        return RobotLedPattern.pulse;
      case thinking:
        return RobotLedPattern.pulse;
      case sleepy:
        return RobotLedPattern.off;
      case surprised:
        return RobotLedPattern.fastBlink;
      default:
        return RobotLedPattern.solid;
    }
  }
}

// ── Animation macros (mirrors Arduino A<n> command) ──
class RobotAnimation {
  RobotAnimation._();
  static const nod = 0;
  static const shake = 1;
  static const lookAround = 2;
  static const wink = 3;
  static const yawn = 4;
  static const laugh = 5;
  static const eyeRoll = 6;
  static const mouthCycle = 7;
  static const eyeCycle = 8;
  static const wiggle = 9;

  static const labels = [
    'Nod',
    'Shake',
    'Look Around',
    'Wink',
    'Yawn',
    'Laugh',
    'Eye Roll',
    'Mouth Cycle',
    'Eye Cycle',
    'Wiggle',
  ];

  static const emojis = [
    '🙌',  // nod
    '🙅',  // shake
    '👀',  // look around
    '😉',  // wink
    '🥱',  // yawn
    '😂',  // laugh
    '🙄',  // eye roll
    '💬',  // mouth cycle
    '👁️',  // eye cycle
    '🕺',  // wiggle
  ];

  /// Map a string name to an index (for Gemini tool dispatch).
  static int? fromName(String name) {
    switch (name.toLowerCase().replaceAll(RegExp(r'[_\-\s]+'), '')) {
      case 'nod':
      case 'nodyes':
        return nod;
      case 'shake':
      case 'shakeno':
        return shake;
      case 'lookaround':
        return lookAround;
      case 'wink':
        return wink;
      case 'yawn':
        return yawn;
      case 'laugh':
        return laugh;
      case 'eyeroll':
        return eyeRoll;
      case 'mouthcycle':
        return mouthCycle;
      case 'eyecycle':
        return eyeCycle;
      case 'wiggle':
        return wiggle;
      default:
        return null;
    }
  }
}

// ── Movement tricks (mirrors Arduino W<n> command) ──
class RobotMovementTrick {
  RobotMovementTrick._();
  static const crazyEyes = 0;
  static const chatter = 1;
  static const slowScan = 2;
  static const peekaboo = 3;
  static const doubleBlink = 4;
  static const jawDrop = 5;
  static const drowsy = 6;
  static const sideEye = 7;
  static const happyBounce = 8;
  static const confused = 9;

  static const labels = [
    'Crazy Eyes',
    'Chatter',
    'Slow Scan',
    'Peek-a-boo',
    'Double Blink',
    'Jaw Drop',
    'Drowsy',
    'Side Eye',
    'Happy Bounce',
    'Confused',
  ];

  static const emojis = [
    '🫨',  // crazy eyes
    '🦷',  // chatter
    '🔍',  // slow scan
    '🙈',  // peek-a-boo
    '✨',  // double blink
    '😱',  // jaw drop
    '😴',  // drowsy
    '😒',  // side eye
    '🤩',  // happy bounce
    '🤔',  // confused
  ];

  /// Map a string name to an index (for Gemini tool dispatch).
  static int? fromName(String name) {
    switch (name.toLowerCase().replaceAll(RegExp(r'[_\-\s]+'), '')) {
      case 'crazyeyes':
        return crazyEyes;
      case 'chatter':
        return chatter;
      case 'slowscan':
        return slowScan;
      case 'peekaboo':
      case 'peek':
        return peekaboo;
      case 'doubleblink':
        return doubleBlink;
      case 'jawdrop':
        return jawDrop;
      case 'drowsy':
        return drowsy;
      case 'sideeye':
        return sideEye;
      case 'happybounce':
      case 'bounce':
        return happyBounce;
      case 'confused':
        return confused;
      default:
        return null;
    }
  }
}

// ── LED patterns (mirrors Arduino C<n> command) ──
class RobotLedPattern {
  RobotLedPattern._();
  static const off = 0;
  static const solid = 1;
  static const pulse = 2;
  static const fastBlink = 3;

  static const labels = ['Off', 'Solid', 'Pulse', 'Fast Blink'];
  static const emojis = ['⚫', '🟢', '💫', '⚡'];
}

class RobotState {
  final RobotConnectionState connection;
  final String? lastDeviceName;
  final String? lastDeviceAddress;
  final int currentExpression;
  final int expressionIntensity;
  final int lastMouthAngle;
  final bool autoDrive;
  final bool freezeMode;
  final int ledPattern;
  final String? lastMessage;
  final String? errorMessage;

  // Discovery
  final bool scanning;
  final List<BleDevice> discovered;

  const RobotState({
    this.connection = RobotConnectionState.disconnected,
    this.lastDeviceName,
    this.lastDeviceAddress,
    this.currentExpression = RobotExpression.thinking,
    this.expressionIntensity = 100,
    this.lastMouthAngle = 90,
    this.autoDrive = true,
    this.freezeMode = false,
    this.ledPattern = RobotLedPattern.solid,
    this.lastMessage,
    this.errorMessage,
    this.scanning = false,
    this.discovered = const [],
  });

  bool get isConnected => connection == RobotConnectionState.connected;
  bool get isConnecting => connection == RobotConnectionState.connecting;

  RobotState copyWith({
    RobotConnectionState? connection,
    String? lastDeviceName,
    String? lastDeviceAddress,
    int? currentExpression,
    int? expressionIntensity,
    int? lastMouthAngle,
    bool? autoDrive,
    bool? freezeMode,
    int? ledPattern,
    String? lastMessage,
    String? errorMessage,
    bool? scanning,
    List<BleDevice>? discovered,
    bool clearError = false,
  }) {
    return RobotState(
      connection: connection ?? this.connection,
      lastDeviceName: lastDeviceName ?? this.lastDeviceName,
      lastDeviceAddress: lastDeviceAddress ?? this.lastDeviceAddress,
      currentExpression: currentExpression ?? this.currentExpression,
      expressionIntensity: expressionIntensity ?? this.expressionIntensity,
      lastMouthAngle: lastMouthAngle ?? this.lastMouthAngle,
      autoDrive: autoDrive ?? this.autoDrive,
      freezeMode: freezeMode ?? this.freezeMode,
      ledPattern: ledPattern ?? this.ledPattern,
      lastMessage: lastMessage ?? this.lastMessage,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      scanning: scanning ?? this.scanning,
      discovered: discovered ?? this.discovered,
    );
  }
}

/// Bridges the Brutus chat state machine to the physical robot.
///
/// All BLE heavy-lifting lives in [RobotBluetoothService], which uses
/// flutter_blue_plus to connect to the HM-10 module via GATT. This
/// notifier is just glue: it watches `chatProvider` for voice-status
/// changes, the audio playback for output level (lip-sync), and exposes
/// manual-control actions to the UI.
class RobotNotifier extends StateNotifier<RobotState> {
  RobotNotifier(this._ref) : super(const RobotState()) {
    _bind();
  }

  static const _kPrefDeviceAddress = 'brutus_robot_device_address';
  static const _kPrefDeviceName = 'brutus_robot_device_name';
  static const _kPrefAutoDrive = 'brutus_robot_auto_drive';

  final Ref _ref;
  final RobotBluetoothService _bt = RobotBluetoothService.instance;
  final AudioPlaybackService _playback = AudioPlaybackService.instance;

  StreamSubscription<RobotConnectionState>? _connectionSub;
  StreamSubscription<String>? _messageSub;
  StreamSubscription<BleDevice>? _discoverySub;
  StreamSubscription<RobotScanEvent>? _scanSub;
  StreamSubscription<String>? _connectErrorSub;
  StreamSubscription<double>? _outputLevelSub;
  StreamSubscription<void>? _outputIdleSub;
  ProviderSubscription<ChatState>? _chatSub;

  VoiceStatus? _lastSeenVoiceStatus;
  String? _lastSeenEmotion;

  void _bind() {
    _restorePrefs();

    _connectionSub = _bt.connectionStream.listen((s) {
      state = state.copyWith(connection: s, clearError: true);
      if (s == RobotConnectionState.connected) {
        // Sync freeze mode to Arduino on reconnect
        if (state.freezeMode) {
          _bt.setFreezeMode(true);
        }
        _applyVoiceStatus(_ref.read(chatProvider).status, force: true);
      }
    });

    _messageSub = _bt.messageStream.listen((line) {
      state = state.copyWith(lastMessage: line);
    });

    _discoverySub = _bt.discoveryStream.listen((device) {
      final existing = state.discovered;
      final idx = existing.indexWhere((d) => d.address == device.address);
      final next = [...existing];
      if (idx >= 0) {
        next[idx] = BleDevice(
          name: device.name,
          address: device.address,
          rssi: device.rssi ?? existing[idx].rssi,
        );
      } else {
        next.add(device);
      }
      next.sort((a, b) {
        final aRssi = a.rssi ?? -999;
        final bRssi = b.rssi ?? -999;
        if (aRssi != bRssi) return bRssi.compareTo(aRssi);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      state = state.copyWith(discovered: next);
    });

    _scanSub = _bt.scanEventStream.listen((evt) {
      switch (evt) {
        case RobotScanEvent.started:
          state = state.copyWith(scanning: true);
          break;
        case RobotScanEvent.complete:
          state = state.copyWith(scanning: false);
          break;
      }
    });

    _connectErrorSub = _bt.connectErrorStream.listen((msg) {
      if (msg.isEmpty) return;
      state = state.copyWith(errorMessage: 'Connection failed: $msg');
    });

    _chatSub = _ref.listen<ChatState>(chatProvider, (prev, next) {
      if (!state.autoDrive || !state.isConnected) return;

      // React to voice status changes
      if (prev?.status != next.status) {
        _applyVoiceStatus(next.status);
      }

      // React to detected emotion changes (Phase 4)
      if (next.status == VoiceStatus.speaking &&
          next.detectedEmotion != null &&
          next.detectedEmotion != _lastSeenEmotion) {
        _lastSeenEmotion = next.detectedEmotion;
        final expr = RobotExpression.fromEmotionTag(next.detectedEmotion);
        if (expr != null) {
          _bt.setExpression(expr);
          state = state.copyWith(currentExpression: expr);
          // Sync LED pattern to emotion
          final led = RobotExpression.toLedPattern(expr);
          _bt.setLedPattern(led);
          state = state.copyWith(ledPattern: led);
        }
      }
    });

    _outputLevelSub = _playback.outputLevelStream.listen((level) {
      if (!state.autoDrive || !state.isConnected) return;
      final angle = level < 0.05 ? 90 : (90 + (level * 90)).round();
      _bt.setMouth(angle);
      state = state.copyWith(lastMouthAngle: angle);
    });

    _outputIdleSub = _playback.onIdleStream.listen((_) {
      if (!state.autoDrive || !state.isConnected) return;
      _bt.closeMouth();
      state = state.copyWith(lastMouthAngle: 90);
    });
  }

  // ── Public actions ──

  Future<bool> ensureReady() async {
    if (!await _bt.isSupported()) {
      state = state.copyWith(
        errorMessage: 'No Bluetooth radio on this device.',
      );
      return false;
    }
    if (!await _bt.isEnabled()) {
      state = state.copyWith(
        errorMessage: 'Turn on Bluetooth and try again.',
      );
      return false;
    }
    final ok = await _bt.ensurePermissions();
    if (!ok) {
      state = state.copyWith(
        errorMessage:
            'Nearby devices permission is required to talk to the robot.',
      );
    }
    return ok;
  }

  Future<void> startScan() async {
    if (!await ensureReady()) return;
    state = state.copyWith(clearError: true);
    await _bt.startScan();
  }

  Future<void> stopScan() async {
    await _bt.stopScan();
    if (state.scanning) {
      state = state.copyWith(scanning: false);
    }
  }

  Future<bool> connect(BleDevice device) async {
    if (!await ensureReady()) return false;
    if (state.isConnecting) return false;
    state = state.copyWith(clearError: true);

    if (state.scanning) {
      await _bt.stopScan();
    }

    final ok = await _bt.connect(device.address);

    if (ok) {
      _persist(_kPrefDeviceAddress, device.address);
      _persist(_kPrefDeviceName, device.name);
      state = state.copyWith(
        lastDeviceAddress: device.address,
        lastDeviceName: device.name,
      );
    } else {
      state = state.copyWith(
        errorMessage:
            'Could not connect to ${device.name}. '
            'Make sure it\'s powered on and in range.',
      );
    }
    return ok;
  }

  Future<bool> reconnectLast() async {
    final addr = state.lastDeviceAddress;
    if (addr == null || addr.isEmpty) return false;
    return connect(
      BleDevice(
        name: state.lastDeviceName ?? 'Brutus Robot',
        address: addr,
      ),
    );
  }

  Future<void> disconnect() async {
    await _bt.disconnect();
  }

  // ── Manual control ──

  Future<void> setExpression(int mode) async {
    if (!state.isConnected) return;
    await _bt.setExpressionWithIntensity(mode, state.expressionIntensity);
    state = state.copyWith(currentExpression: mode);
    // Sync LED pattern to this expression when auto-drive is on
    if (state.autoDrive) {
      final led = RobotExpression.toLedPattern(mode);
      _bt.setLedPattern(led);
      state = state.copyWith(ledPattern: led);
    }
  }

  Future<void> setMouth(int angle) async {
    if (!state.isConnected) return;
    await _bt.setMouth(angle, force: true);
    state = state.copyWith(lastMouthAngle: angle);
  }

  Future<void> lookAt({required int lr, required int ud}) async {
    if (!state.isConnected) return;
    await _bt.lookAt(lr: lr, ud: ud);
  }

  Future<void> blink() async {
    if (!state.isConnected) return;
    await _bt.blink();
  }

  Future<void> setIdleFallback(bool on) async {
    if (!state.isConnected) return;
    await _bt.setIdleFallback(on);
  }

  /// Freeze mode — disables ALL autonomous Arduino behavior.
  /// Robot holds perfectly still. Only manual controls work.
  Future<void> setFreezeMode(bool on) async {
    state = state.copyWith(freezeMode: on);
    if (state.isConnected) {
      await _bt.setFreezeMode(on);
    }
    // When freezing, also disable auto-drive
    if (on && state.autoDrive) {
      state = state.copyWith(autoDrive: false);
      _persist(_kPrefAutoDrive, false);
    }
  }

  Future<void> setAutoDrive(bool on) async {
    // Can't enable auto-drive while frozen
    if (on && state.freezeMode) return;
    state = state.copyWith(autoDrive: on);
    _persist(_kPrefAutoDrive, on);
    if (state.isConnected) {
      await _bt.setIdleFallback(!on);
    }
  }

  // ── New: Animation macros, movement tricks, intensity, LED ──

  Future<void> playAnimation(int index) async {
    if (!state.isConnected) return;
    await _bt.playAnimation(index);
  }

  Future<void> playMovementTrick(int index) async {
    if (!state.isConnected) return;
    await _bt.playMovementTrick(index);
  }

  Future<void> setExpressionIntensity(int intensity) async {
    final clamped = intensity.clamp(0, 100);
    state = state.copyWith(expressionIntensity: clamped);
    if (state.isConnected) {
      await _bt.setExpressionWithIntensity(
          state.currentExpression, clamped);
    }
  }

  Future<void> setLedPattern(int pattern) async {
    final clamped = pattern.clamp(0, 3);
    state = state.copyWith(ledPattern: clamped);
    if (state.isConnected) {
      await _bt.setLedPattern(clamped);
    }
  }

  // ── Internal mapping: chat voice status → robot face ──

  void _applyVoiceStatus(VoiceStatus status, {bool force = false}) {
    if (!force && _lastSeenVoiceStatus == status) return;
    _lastSeenVoiceStatus = status;
    _lastSeenEmotion = null; // reset emotion on status change

    switch (status) {
      case VoiceStatus.idle:
        _bt.setExpression(RobotExpression.thinking);
        _bt.lookAt(lr: 90, ud: 90);
        _bt.closeMouth();
        _bt.setLedPattern(RobotLedPattern.pulse);
        state = state.copyWith(
          currentExpression: RobotExpression.thinking,
          ledPattern: RobotLedPattern.pulse,
        );
        break;
      case VoiceStatus.connecting:
        _bt.setExpression(RobotExpression.thinking);
        _bt.setLedPattern(RobotLedPattern.fastBlink);
        state = state.copyWith(
          currentExpression: RobotExpression.thinking,
          ledPattern: RobotLedPattern.fastBlink,
        );
        break;
      case VoiceStatus.listening:
        _bt.setExpression(RobotExpression.happy);
        _bt.lookAt(lr: 90, ud: 90);
        _bt.setLedPattern(RobotLedPattern.solid);
        state = state.copyWith(
          currentExpression: RobotExpression.happy,
          ledPattern: RobotLedPattern.solid,
        );
        break;
      case VoiceStatus.thinking:
        _bt.setExpression(RobotExpression.thinking);
        _bt.lookAt(lr: 60, ud: 70);
        _bt.setLedPattern(RobotLedPattern.pulse);
        state = state.copyWith(
          currentExpression: RobotExpression.thinking,
          ledPattern: RobotLedPattern.pulse,
        );
        break;
      case VoiceStatus.speaking:
        // Start with happy — will be overridden by emotion tag when detected
        _bt.setExpression(RobotExpression.happy);
        _bt.setLedPattern(RobotLedPattern.solid);
        state = state.copyWith(
          currentExpression: RobotExpression.happy,
          ledPattern: RobotLedPattern.solid,
        );
        break;
      case VoiceStatus.error:
        _bt.setExpression(RobotExpression.sad);
        _bt.blink();
        _bt.closeMouth();
        _bt.setLedPattern(RobotLedPattern.fastBlink);
        state = state.copyWith(
          currentExpression: RobotExpression.sad,
          ledPattern: RobotLedPattern.fastBlink,
        );
        break;
    }
  }

  // ── Persistence ──

  void _restorePrefs() {
    try {
      final box = Hive.box(ApiConstants.boxPreferences);
      final addr = box.get(_kPrefDeviceAddress) as String?;
      final name = box.get(_kPrefDeviceName) as String?;
      final autoDrive = box.get(_kPrefAutoDrive) as bool? ?? true;
      if (addr != null && addr.isNotEmpty) {
        state = state.copyWith(
          lastDeviceAddress: addr,
          lastDeviceName: name,
          autoDrive: autoDrive,
        );
      } else {
        state = state.copyWith(autoDrive: autoDrive);
      }
    } catch (e) {
      dev.log('[Robot] restore prefs failed: $e', name: 'BrutusAI');
    }
  }

  void _persist(String key, dynamic value) {
    try {
      Hive.box(ApiConstants.boxPreferences).put(key, value);
    } catch (e) {
      dev.log('[Robot] persist $key failed: $e', name: 'BrutusAI');
    }
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _messageSub?.cancel();
    _discoverySub?.cancel();
    _scanSub?.cancel();
    _connectErrorSub?.cancel();
    _outputLevelSub?.cancel();
    _outputIdleSub?.cancel();
    _chatSub?.close();
    super.dispose();
  }
}

final robotProvider =
    StateNotifierProvider<RobotNotifier, RobotState>((ref) {
  return RobotNotifier(ref);
});
