import 'dart:async';
import 'dart:developer' as dev;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:brutus_app/data/services/screen_share_service.dart';

/// Brutus Mobile — Phone Automation service.
///
/// Single facade over every native Android capability we expose:
///
///   • Permission status checks and deep-links to the relevant settings
///     screens (Accessibility, Notification access, Modify system settings).
///   • Hardware-ish toggles (flashlight, ringer mode, media volume,
///     brightness) via the method channel.
///   • Settings-panel openers for things Android won't let third-party apps
///     toggle programmatically (WiFi, Bluetooth, mobile data) — we open
///     the system "panel" intent, which is the modern, in-app-overlay UX.
///   • App enumeration, launch, and per-app settings.
///   • Accessibility-driven actions: ghost typing, global gestures,
///     WhatsApp auto-send.
///   • Notification listener: snapshot of active notifications and
///     dismiss-by-key, plus a stream of posted/removed events.
///
/// All native side-effects flow through the `phone_automation` MethodChannel.
class PhoneAutomationService {
  PhoneAutomationService._() {
    _channel.setMethodCallHandler(_onChannelCall);
    // Tell the screen-share service that channel routing is now live so it
    // doesn't log a "frames may drop" warning on first start.
    ScreenShareService.instance.markRoutingReady();
  }
  static final PhoneAutomationService instance = PhoneAutomationService._();

  static const _channel =
      MethodChannel('com.adityapandey.brutus_app/phone_automation');

  // ── Push streams from the native notification listener ──
  final _postedController =
      StreamController<NotificationEvent>.broadcast();
  final _removedController =
      StreamController<NotificationEvent>.broadcast();

  Stream<NotificationEvent> get notificationsPosted =>
      _postedController.stream;
  Stream<NotificationEvent> get notificationsRemoved =>
      _removedController.stream;

  void _log(String msg) => dev.log('[Automation] $msg', name: 'BrutusAI');

  Future<dynamic> _onChannelCall(MethodCall call) async {
    switch (call.method) {
      case 'onNotificationPosted':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        if (!_postedController.isClosed) {
          _postedController.add(NotificationEvent.fromMap(m));
        }
        break;
      case 'onNotificationRemoved':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        if (!_removedController.isClosed) {
          _removedController.add(NotificationEvent.fromMap(m));
        }
        break;
      // Screen capture events live on the same channel; forward them so
      // ScreenShareService can drive its own streams without competing for
      // the channel handler slot.
      case 'onScreenCaptureFrame':
      case 'onScreenCaptureStarted':
      case 'onScreenCaptureStopped':
        ScreenShareService.instance.onChannelCall(call);
        break;
    }
    return null;
  }

  // ── Permission status ──────────────────────────────────────────────────

  Future<bool> isAccessibilityEnabled() async =>
      (await _channel.invokeMethod<bool>('isAccessibilityEnabled')) ?? false;

  Future<bool> isNotificationListenerEnabled() async =>
      (await _channel.invokeMethod<bool>('isNotificationListenerEnabled')) ??
      false;

  Future<bool> canWriteSettings() async =>
      (await _channel.invokeMethod<bool>('canWriteSettings')) ?? false;

  Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod('openAccessibilitySettings');

  Future<void> openNotificationListenerSettings() =>
      _channel.invokeMethod('openNotificationListenerSettings');

  Future<void> openWriteSettings() =>
      _channel.invokeMethod('openWriteSettings');

  Future<void> openAppSettings({String? packageName}) =>
      _channel.invokeMethod('openAppSettings', {
        'packageName': ?packageName,
      });

  // ── Settings panels ────────────────────────────────────────────────────

  Future<void> openSettingsPanel(SettingsPanel panel) =>
      _channel.invokeMethod('openSettingsPanel', {'panel': panel.name});

  // ── Hardware-ish toggles ───────────────────────────────────────────────

  Future<bool> setTorch(bool on) async =>
      (await _channel.invokeMethod<bool>('setTorch', {'on': on})) ?? false;

  Future<bool> setRingerMode(RingerMode mode) async =>
      (await _channel
              .invokeMethod<bool>('setRingerMode', {'mode': mode.name})) ??
      false;

  Future<bool> setMediaVolume(double value) async =>
      (await _channel.invokeMethod<bool>(
        'setMediaVolume',
        {'value': value.clamp(0.0, 1.0)},
      )) ??
      false;

  /// Requires WRITE_SETTINGS permission. Caller must check [canWriteSettings]
  /// and prompt with [openWriteSettings] if false.
  Future<bool> setBrightness(double value) async {
    try {
      return (await _channel.invokeMethod<bool>(
            'setBrightness',
            {'value': value.clamp(0.0, 1.0)},
          )) ??
          false;
    } on PlatformException catch (e) {
      _log('setBrightness failed: ${e.message}');
      rethrow;
    }
  }

  // ── Accessibility primitives ──────────────────────────────────────────

  Future<bool> ghostType(String text) async {
    try {
      return (await _channel
              .invokeMethod<bool>('ghostType', {'text': text})) ??
          false;
    } on PlatformException catch (e) {
      _log('ghostType failed: ${e.message}');
      return false;
    }
  }

  Future<bool> pasteText(String text) async {
    try {
      return (await _channel
              .invokeMethod<bool>('pasteText', {'text': text})) ??
          false;
    } on PlatformException catch (e) {
      _log('pasteText failed: ${e.message}');
      return false;
    }
  }

  Future<bool> clickByText(String query) async {
    try {
      return (await _channel
              .invokeMethod<bool>('clickByText', {'query': query})) ??
          false;
    } on PlatformException catch (e) {
      _log('clickByText failed: ${e.message}');
      return false;
    }
  }

  Future<bool> ghostTap(double x, double y) async {
    try {
      return (await _channel
              .invokeMethod<bool>('ghostTap', {'x': x, 'y': y})) ??
          false;
    } on PlatformException catch (e) {
      _log('ghostTap failed: ${e.message}');
      return false;
    }
  }

  Future<bool> ghostSwipe({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    int durationMs = 300,
  }) async {
    try {
      return (await _channel.invokeMethod<bool>('ghostSwipe', {
            'x1': x1,
            'y1': y1,
            'x2': x2,
            'y2': y2,
            'durationMs': durationMs,
          })) ??
          false;
    } on PlatformException catch (e) {
      _log('ghostSwipe failed: ${e.message}');
      return false;
    }
  }

  Future<bool> ghostScroll({String direction = 'down'}) async {
    try {
      return (await _channel
              .invokeMethod<bool>('ghostScroll', {'direction': direction})) ??
          false;
    } on PlatformException catch (e) {
      _log('ghostScroll failed: ${e.message}');
      return false;
    }
  }

  Future<String> readScreenText() async {
    try {
      return (await _channel.invokeMethod<String>('readScreenText')) ?? '';
    } on PlatformException catch (e) {
      _log('readScreenText failed: ${e.message}');
      return '';
    }
  }

  /// Run an arbitrary list of [GhostAction] primitives. Mirrors the desktop
  /// `ghost-sequence` IPC. Returns true only if every step succeeded.
  Future<GhostSequenceResult> ghostSequence(List<GhostAction> actions) async {
    if (actions.isEmpty) {
      return const GhostSequenceResult(success: true, completed: 0, total: 0);
    }
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'ghostSequence',
        {'actions': actions.map((a) => a.toMap()).toList()},
      );
      if (raw == null) {
        return GhostSequenceResult(
          success: false,
          completed: 0,
          total: actions.length,
        );
      }
      return GhostSequenceResult(
        success: raw['success'] as bool? ?? false,
        completed: (raw['completed'] as num?)?.toInt() ?? 0,
        total: (raw['total'] as num?)?.toInt() ?? actions.length,
      );
    } on PlatformException catch (e) {
      _log('ghostSequence failed: ${e.message}');
      return GhostSequenceResult(
        success: false,
        completed: 0,
        total: actions.length,
        error: e.message,
      );
    }
  }

  Future<bool> globalAction(GlobalAction action) async {
    try {
      return (await _channel.invokeMethod<bool>(
            'globalAction',
            {'action': action.name},
          )) ??
          false;
    } on PlatformException catch (e) {
      _log('globalAction failed: ${e.message}');
      return false;
    }
  }

  // ── App launcher ───────────────────────────────────────────────────────

  /// Returns every user-visible installed app, sorted by name.
  Future<List<InstalledApp>> listInstalledApps() async {
    try {
      final raw = await InstalledApps.getInstalledApps(
        excludeSystemApps: true,
        excludeNonLaunchableApps: true,
        withIcon: true,
      );
      return raw
          .map((a) => InstalledApp(
                packageName: a.packageName,
                name: a.name,
                versionName: a.versionName,
                iconBytes: a.icon,
              ))
          .toList();
    } catch (e) {
      _log('listInstalledApps failed: $e');
      return const [];
    }
  }

  Future<bool> launchApp(String packageName) async {
    try {
      return (await _channel
              .invokeMethod<bool>('launchApp', {'packageName': packageName})) ??
          false;
    } on PlatformException catch (e) {
      _log('launchApp failed: ${e.message}');
      return false;
    }
  }

  /// Best-effort fuzzy match — used by voice tool "open `appName`".
  /// Returns the launched app or null if no match.
  Future<InstalledApp?> launchAppByName(String query) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return null;
    final apps = await listInstalledApps();
    InstalledApp? exact;
    InstalledApp? prefix;
    InstalledApp? contains;
    for (final a in apps) {
      final name = a.name.toLowerCase();
      if (name == clean) {
        exact = a;
        break;
      }
      if (prefix == null && name.startsWith(clean)) prefix = a;
      if (contains == null && name.contains(clean)) contains = a;
    }
    final pick = exact ?? prefix ?? contains;
    if (pick == null) return null;
    final ok = await launchApp(pick.packageName);
    return ok ? pick : null;
  }

  // ── Accessibility-driven actions (legacy aliases) ─────────────────────
  // (ghostType + globalAction live in the "Accessibility primitives" section
  //  above. This block is intentionally left blank for organisational clarity.)

  // ── SMS / Dialer / Direct Call ────────────────────────────────────────

  /// Open the system SMS composer pre-filled with [body] for [phone].
  /// User still has to tap Send.
  Future<bool> openSmsComposer({
    required String phone,
    required String body,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanPhone.isEmpty) return false;
    final uri = Uri(
      scheme: 'smsto',
      path: cleanPhone,
      queryParameters: {'body': body},
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Open the dialer for [phone] (user taps the call button).
  Future<bool> openDialer(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanPhone.isEmpty) return false;
    final uri = Uri(scheme: 'tel', path: cleanPhone);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Place an outgoing call directly (requires CALL_PHONE permission;
  /// caller is responsible for the runtime grant). On failure or denial
  /// falls back to [openDialer].
  Future<bool> placeCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanPhone.isEmpty) return false;
    try {
      // CALL_PHONE: ACTION_CALL bypasses the dialer.
      const platform = MethodChannel('com.adityapandey.brutus_app/phone_automation');
      final ok = (await platform.invokeMethod<bool>('placeCall', {
            'phone': cleanPhone,
          })) ??
          false;
      if (ok) return true;
    } on PlatformException catch (e) {
      _log('placeCall failed: ${e.message}');
    }
    return openDialer(phone);
  }

  // ── WhatsApp click-to-chat ────────────────────────────────────────────

  /// Open a WhatsApp chat with the [phone] (E.164 with no spaces or `+`)
  /// and pre-filled [message]. If the accessibility service is enabled, we
  /// also arm the auto-send so the user doesn't need to tap Send.
  Future<bool> sendWhatsApp({
    required String phone,
    required String message,
    bool autoSend = true,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.isEmpty) return false;

    final uri = Uri.parse(
      'https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}',
    );

    if (autoSend && await isAccessibilityEnabled()) {
      await _channel.invokeMethod('armWhatsAppAutoSend');
    }

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── Spotify deep links ────────────────────────────────────────────────

  /// Direct-play [query] on Spotify using Android's "play from search"
  /// intent — the same one Google Assistant fires for "play X on Spotify".
  /// No SDK registration required, no UI scripting; Spotify handles the
  /// search and starts playback natively.
  ///
  /// Falls back, in order:
  ///   1. Native intent + Spotify package
  ///   2. `spotify:search:<query>` deep link (app)
  ///   3. `https://open.spotify.com/search/<query>` (web)
  Future<bool> spotifySearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return false;

    // 1. Direct play via system MediaStore intent. This works whenever
    //    Spotify is installed and configured as a music provider.
    try {
      final ok = (await _channel
              .invokeMethod<bool>('playSpotifySong', {'query': clean})) ??
          false;
      if (ok) return true;
    } on PlatformException catch (e) {
      _log('playSpotifySong failed: ${e.message}');
    }

    // 2. Search deep link inside the app.
    final encoded = Uri.encodeComponent(clean);
    final native = Uri.parse('spotify:search:$encoded');
    if (await canLaunchUrl(native)) {
      return launchUrl(native, mode: LaunchMode.externalApplication);
    }

    // 3. Web player fallback.
    final web = Uri.parse('https://open.spotify.com/search/$encoded');
    return launchUrl(web, mode: LaunchMode.externalApplication);
  }

  /// Same as [spotifySearch] but lets the system pick the music app.
  Future<bool> playMusicSearch(String query) async {
    try {
      return (await _channel
              .invokeMethod<bool>('playMusicSearch', {'query': query})) ??
          false;
    } on PlatformException catch (e) {
      _log('playMusicSearch failed: ${e.message}');
      return false;
    }
  }

  /// Open a known Spotify URI like `spotify:playlist:abc` or `spotify:track:xyz`.
  Future<bool> spotifyOpen(String spotifyUri) async {
    final uri = Uri.tryParse(spotifyUri);
    if (uri == null) return false;
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  // ── System timer (AlarmClock intent) ──────────────────────────────────

  /// Start a countdown timer in the system Clock app. Uses the public
  /// `ACTION_SET_TIMER` intent — needs the install-time
  /// `com.android.alarm.permission.SET_ALARM` permission, no runtime prompt.
  ///
  /// With SKIP_UI the timer starts silently in the background; if the
  /// device's clock app refuses SKIP_UI it opens pre-filled instead, which
  /// is still a working timer.
  Future<bool> setTimer({
    required int seconds,
    String label = 'Brutus timer',
  }) async {
    if (seconds <= 0) return false;
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.SET_TIMER',
        arguments: <String, dynamic>{
          'android.intent.extra.alarm.LENGTH': seconds,
          'android.intent.extra.alarm.MESSAGE': label,
          'android.intent.extra.alarm.SKIP_UI': true,
        },
      );
      await intent.launch();
      return true;
    } catch (e) {
      _log('setTimer failed: $e');
      return false;
    }
  }

  // ── Notification listener queries ─────────────────────────────────────

  Future<List<NotificationEvent>> listActiveNotifications() async {
    final raw =
        await _channel.invokeMethod<List<dynamic>>('listNotifications') ??
            const [];
    return raw
        .map((e) => NotificationEvent.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<bool> dismissNotification(String key) async {
    try {
      return (await _channel
              .invokeMethod<bool>('dismissNotification', {'key': key})) ??
          false;
    } on PlatformException catch (e) {
      _log('dismissNotification failed: ${e.message}');
      return false;
    }
  }

  void dispose() {
    _postedController.close();
    _removedController.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

enum SettingsPanel { wifi, bluetooth, data, internet, volume, nfc, location, airplane }

enum RingerMode { silent, vibrate, normal }

enum GlobalAction {
  back,
  home,
  recents,
  notifications,
  quickSettings,
  powerDialog,
}

/// One step in a ghost-typing sequence. Mirrors the desktop `ghost-sequence`
/// IPC payload — see `Brutus-AI/src/main/logic/ghost-control.ts`.
sealed class GhostAction {
  const GhostAction();
  Map<String, dynamic> toMap();
}

class GhostWait extends GhostAction {
  final int ms;
  const GhostWait(this.ms);
  @override
  Map<String, dynamic> toMap() => {'type': 'wait', 'ms': ms};
}

class GhostTypeText extends GhostAction {
  final String text;
  const GhostTypeText(this.text);
  @override
  Map<String, dynamic> toMap() => {'type': 'type', 'text': text};
}

class GhostPaste extends GhostAction {
  final String text;
  const GhostPaste(this.text);
  @override
  Map<String, dynamic> toMap() => {'type': 'paste', 'text': text};
}

class GhostTap extends GhostAction {
  final double x;
  final double y;
  const GhostTap(this.x, this.y);
  @override
  Map<String, dynamic> toMap() => {'type': 'tap', 'x': x, 'y': y};
}

class GhostSwipe extends GhostAction {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final int durationMs;
  const GhostSwipe({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.durationMs = 300,
  });
  @override
  Map<String, dynamic> toMap() => {
        'type': 'swipe',
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'durationMs': durationMs,
      };
}

class GhostScroll extends GhostAction {
  final String direction; // up | down
  const GhostScroll(this.direction);
  @override
  Map<String, dynamic> toMap() => {'type': 'scroll', 'direction': direction};
}

class GhostClick extends GhostAction {
  final String query;
  const GhostClick(this.query);
  @override
  Map<String, dynamic> toMap() => {'type': 'click', 'query': query};
}

class GhostGlobal extends GhostAction {
  final GlobalAction action;
  const GhostGlobal(this.action);
  @override
  Map<String, dynamic> toMap() => {'type': 'global', 'action': action.name};
}

class GhostSequenceResult {
  final bool success;
  final int completed;
  final int total;
  final String? error;
  const GhostSequenceResult({
    required this.success,
    required this.completed,
    required this.total,
    this.error,
  });
}

class InstalledApp {
  final String packageName;
  final String name;
  final String? versionName;
  final List<int>? iconBytes;

  const InstalledApp({
    required this.packageName,
    required this.name,
    this.versionName,
    this.iconBytes,
  });
}

class NotificationEvent {
  final String key;
  final int id;
  final String packageName;
  final int postTime;
  final String? title;
  final String? text;
  final String? bigText;
  final bool isOngoing;
  final String? category;

  const NotificationEvent({
    required this.key,
    required this.id,
    required this.packageName,
    required this.postTime,
    this.title,
    this.text,
    this.bigText,
    this.isOngoing = false,
    this.category,
  });

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(postTime);

  factory NotificationEvent.fromMap(Map<String, dynamic> m) => NotificationEvent(
        key: m['key'] as String? ?? '',
        id: (m['id'] as num?)?.toInt() ?? 0,
        packageName: m['packageName'] as String? ?? '',
        postTime: (m['postTime'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        title: m['title'] as String?,
        text: m['text'] as String?,
        bigText: m['bigText'] as String?,
        isOngoing: m['isOngoing'] as bool? ?? false,
        category: m['category'] as String?,
      );
}
