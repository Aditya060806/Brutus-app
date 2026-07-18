import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:brutus_app/data/services/contacts_service.dart';
import 'package:brutus_app/data/services/phone_automation_service.dart';
import 'package:brutus_app/data/services/screen_ocr_service.dart';

export 'package:brutus_app/data/services/phone_automation_service.dart'
    show
        PhoneAutomationService,
        SettingsPanel,
        RingerMode,
        GlobalAction,
        InstalledApp,
        NotificationEvent,
        GhostAction,
        GhostWait,
        GhostTypeText,
        GhostPaste,
        GhostTap,
        GhostSwipe,
        GhostScroll,
        GhostClick,
        GhostGlobal,
        GhostSequenceResult;

class AutomationState {
  final bool accessibilityEnabled;
  final bool notificationListenerEnabled;
  final bool canWriteSettings;
  final bool torchOn;
  final RingerMode? ringerMode;
  final List<InstalledApp> installedApps;
  final bool loadingApps;
  final List<NotificationEvent> notifications;
  final String? toast;

  const AutomationState({
    this.accessibilityEnabled = false,
    this.notificationListenerEnabled = false,
    this.canWriteSettings = false,
    this.torchOn = false,
    this.ringerMode,
    this.installedApps = const [],
    this.loadingApps = false,
    this.notifications = const [],
    this.toast,
  });

  AutomationState copyWith({
    bool? accessibilityEnabled,
    bool? notificationListenerEnabled,
    bool? canWriteSettings,
    bool? torchOn,
    RingerMode? ringerMode,
    List<InstalledApp>? installedApps,
    bool? loadingApps,
    List<NotificationEvent>? notifications,
    String? toast,
    bool clearToast = false,
  }) {
    return AutomationState(
      accessibilityEnabled: accessibilityEnabled ?? this.accessibilityEnabled,
      notificationListenerEnabled:
          notificationListenerEnabled ?? this.notificationListenerEnabled,
      canWriteSettings: canWriteSettings ?? this.canWriteSettings,
      torchOn: torchOn ?? this.torchOn,
      ringerMode: ringerMode ?? this.ringerMode,
      installedApps: installedApps ?? this.installedApps,
      loadingApps: loadingApps ?? this.loadingApps,
      notifications: notifications ?? this.notifications,
      toast: clearToast ? null : (toast ?? this.toast),
    );
  }
}

class AutomationNotifier extends StateNotifier<AutomationState> {
  AutomationNotifier({PhoneAutomationService? service})
      : _service = service ?? PhoneAutomationService.instance,
        super(const AutomationState()) {
    _init();
  }

  final PhoneAutomationService _service;
  StreamSubscription<NotificationEvent>? _postedSub;
  StreamSubscription<NotificationEvent>? _removedSub;

  Future<void> _init() async {
    await refreshPermissions();
    _postedSub = _service.notificationsPosted.listen((event) {
      if (!mounted) return;
      // Push to the head — newest first.
      final next = <NotificationEvent>[
        event,
        ...state.notifications.where((n) => n.key != event.key),
      ].take(50).toList();
      state = state.copyWith(notifications: next);
    });
    _removedSub = _service.notificationsRemoved.listen((event) {
      if (!mounted) return;
      state = state.copyWith(
        notifications: state.notifications.where((n) => n.key != event.key).toList(),
      );
    });
    if (state.notificationListenerEnabled) {
      await refreshNotifications();
    }
    // Warm up contacts cache in the background so the first WhatsApp /
    // SMS / call command resolves instantly.
    unawaited(ContactsService.instance.warmUp());
  }

  // ── Permissions ─────────────────────────────────────────────────────────

  Future<void> refreshPermissions() async {
    final acc = await _service.isAccessibilityEnabled();
    final nl = await _service.isNotificationListenerEnabled();
    final ws = await _service.canWriteSettings();
    state = state.copyWith(
      accessibilityEnabled: acc,
      notificationListenerEnabled: nl,
      canWriteSettings: ws,
    );
  }

  Future<void> openAccessibilitySettings() =>
      _service.openAccessibilitySettings();

  Future<void> openNotificationListenerSettings() =>
      _service.openNotificationListenerSettings();

  Future<void> openWriteSettings() => _service.openWriteSettings();

  // ── Hardware-ish ────────────────────────────────────────────────────────

  Future<void> toggleTorch() async {
    final next = !state.torchOn;
    final ok = await _service.setTorch(next);
    if (ok) {
      state = state.copyWith(torchOn: next);
    } else {
      state = state.copyWith(toast: 'Could not toggle the flashlight.');
    }
  }

  Future<void> setRinger(RingerMode mode) async {
    final ok = await _service.setRingerMode(mode);
    if (ok) {
      state = state.copyWith(ringerMode: mode);
    }
  }

  Future<bool> setBrightness(double value) async {
    if (!state.canWriteSettings) return false;
    try {
      return await _service.setBrightness(value);
    } catch (_) {
      return false;
    }
  }

  Future<void> setMediaVolume(double value) async {
    await _service.setMediaVolume(value);
  }

  Future<void> openSettingsPanel(SettingsPanel panel) =>
      _service.openSettingsPanel(panel);

  // ── Apps ────────────────────────────────────────────────────────────────

  Future<void> loadApps({bool force = false}) async {
    if (state.loadingApps) return;
    if (!force && state.installedApps.isNotEmpty) return;
    state = state.copyWith(loadingApps: true);
    final apps = await _service.listInstalledApps();
    if (!mounted) return;
    state = state.copyWith(installedApps: apps, loadingApps: false);
  }

  Future<bool> launchApp(String packageName) =>
      _service.launchApp(packageName);

  // ── Notifications ──────────────────────────────────────────────────────

  Future<void> refreshNotifications() async {
    final list = await _service.listActiveNotifications();
    if (!mounted) return;
    state = state.copyWith(notifications: list);
  }

  Future<void> dismissNotification(String key) async {
    final ok = await _service.dismissNotification(key);
    if (ok) {
      state = state.copyWith(
        notifications:
            state.notifications.where((n) => n.key != key).toList(),
      );
    }
  }

  // ── Voice tool runners ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> runOpenApp(String name) async {
    final hit = await _service.launchAppByName(name);
    if (hit == null) {
      return {
        'success': false,
        'message': 'No installed app matched "$name".',
      };
    }
    return {
      'success': true,
      'app': hit.name,
      'package': hit.packageName,
      'message': 'Launched ${hit.name}',
    };
  }

  Future<Map<String, dynamic>> runFlashlight(bool on) async {
    final ok = await _service.setTorch(on);
    if (ok) state = state.copyWith(torchOn: on);
    return {
      'success': ok,
      'state': on ? 'on' : 'off',
      'message': ok
          ? 'Flashlight ${on ? "on" : "off"}'
          : 'Could not toggle the flashlight.',
    };
  }

  Future<Map<String, dynamic>> runOpenSettingsPanel(String panel) async {
    final p = SettingsPanel.values.firstWhere(
      (e) => e.name == panel.toLowerCase(),
      orElse: () => SettingsPanel.wifi,
    );
    await _service.openSettingsPanel(p);
    return {
      'success': true,
      'panel': p.name,
      'message': 'Opened ${p.name} settings',
    };
  }

  Future<Map<String, dynamic>> runSetTimer(int minutes) async {
    if (minutes <= 0) {
      return {
        'success': false,
        'message': 'Timer length must be at least 1 minute.',
      };
    }
    final ok = await _service.setTimer(
      seconds: minutes * 60,
      label: 'Brutus — $minutes min timer',
    );
    return {
      'success': ok,
      'minutes': minutes,
      'message': ok
          ? 'Timer set for $minutes minute${minutes == 1 ? '' : 's'}.'
          : 'Could not reach the system clock app to set a timer.',
    };
  }

  Future<Map<String, dynamic>> runRingerMode(String mode) async {
    final m = RingerMode.values.firstWhere(
      (e) => e.name == mode.toLowerCase(),
      orElse: () => RingerMode.normal,
    );
    final ok = await _service.setRingerMode(m);
    if (ok) state = state.copyWith(ringerMode: m);
    return {
      'success': ok,
      'mode': m.name,
      'message': 'Ringer set to ${m.name}',
    };
  }

  Future<Map<String, dynamic>> runWhatsApp({
    required String phone,
    required String message,
  }) async {
    final resolved = await _resolveRecipient(phone);
    if (resolved == null) {
      return {
        'success': false,
        'message':
            'No matching contact for "$phone" — say a saved contact name or a number with country code.',
      };
    }
    final ok = await _service.sendWhatsApp(
      phone: resolved.e164,
      message: message,
      autoSend: state.accessibilityEnabled,
    );
    return {
      'success': ok,
      'recipient': resolved.displayName,
      'phone': resolved.e164,
      'autoSent': state.accessibilityEnabled && ok,
      'message': ok
          ? state.accessibilityEnabled
              ? 'WhatsApp sent to ${resolved.displayName}.'
              : 'WhatsApp opened to ${resolved.displayName} — tap send.'
          : 'Could not open WhatsApp.',
    };
  }

  Future<Map<String, dynamic>> runSendSms({
    required String to,
    required String body,
  }) async {
    final resolved = await _resolveRecipient(to);
    if (resolved == null) {
      return {
        'success': false,
        'message':
            'No matching contact for "$to" — say a saved contact name or a number.',
      };
    }
    final ok = await _service.openSmsComposer(
      phone: resolved.e164,
      body: body,
    );
    return {
      'success': ok,
      'recipient': resolved.displayName,
      'phone': resolved.e164,
      'message': ok
          ? 'SMS composer opened for ${resolved.displayName}.'
          : 'Could not open the SMS composer.',
    };
  }

  Future<Map<String, dynamic>> runCall(String to) async {
    final resolved = await _resolveRecipient(to);
    if (resolved == null) {
      return {
        'success': false,
        'message':
            'No matching contact for "$to" — say a saved contact name or a number.',
      };
    }
    // Try the direct CALL_PHONE path first; falls back to the dialer
    // automatically inside the service.
    final ok = await _service.placeCall(resolved.e164);
    return {
      'success': ok,
      'recipient': resolved.displayName,
      'phone': resolved.e164,
      'message': ok
          ? 'Calling ${resolved.displayName}.'
          : 'Could not start the call.',
    };
  }

  Future<Map<String, dynamic>> runFindContact(String name) async {
    final hits = await ContactsService.instance.searchByName(name, limit: 5);
    if (hits.isEmpty) {
      return {
        'count': 0,
        'message': 'No saved contact matches "$name".',
      };
    }
    return {
      'count': hits.length,
      'contacts': hits.map((c) => c.toMap()).toList(),
      'message': hits.length == 1
          ? '${hits.first.displayName} — ${hits.first.rawNumber}'
          : 'Found ${hits.length} matches for "$name".',
    };
  }

  /// Try to convert [raw] (a name or number from a voice command) into a
  /// concrete [ContactMatch]. If [raw] already contains 7+ digits, treat it
  /// as a number and skip the contact lookup.
  Future<ContactMatch?> _resolveRecipient(String raw) async {
    final clean = raw.trim();
    if (clean.isEmpty) return null;

    final digitOnly = clean.replaceAll(RegExp(r'[^0-9+]'), '');
    final digitCount = digitOnly.replaceAll('+', '').length;
    if (digitCount >= 7) {
      // Already looks like a phone number.
      return ContactMatch(
        displayName: clean,
        rawNumber: clean,
        e164: digitOnly.startsWith('+')
            ? digitOnly.substring(1)
            : (digitCount == 10 ? '91$digitOnly' : digitOnly),
      );
    }

    // Resolve via contact book.
    return ContactsService.instance.findByName(clean);
  }

  Future<Map<String, dynamic>> runSpotify(String query) async {
    final ok = await _service.spotifySearch(query);
    return {
      'success': ok,
      'query': query,
      'message': ok
          ? 'Now playing on Spotify: $query'
          : 'Could not start Spotify',
    };
  }

  Future<Map<String, dynamic>> runReadNotifications() async {
    if (!state.notificationListenerEnabled) {
      return {
        'count': 0,
        'notifications': const <Map<String, dynamic>>[],
        'note':
            'Open Tools → Automation and grant Notification access so Brutus can read your notifications.',
      };
    }
    final list = await _service.listActiveNotifications();
    return {
      'count': list.length,
      'notifications': list
          .take(10)
          .map((n) => {
                'app': n.packageName,
                'title': n.title,
                'text': n.text,
                'time': n.time.toIso8601String(),
              })
          .toList(),
    };
  }

  // ── Ghost-type / accessibility primitives ───────────────────────────────

  Future<Map<String, dynamic>> runGhostType(String text) async {
    if (!state.accessibilityEnabled) {
      return {
        'success': false,
        'message':
            'Accessibility service is off. Open Tools → Automation and grant it.',
      };
    }
    final clean = text.trim();
    if (clean.isEmpty) {
      return {'success': false, 'message': 'Nothing to type.'};
    }
    var ok = await _service.ghostType(clean);
    // Some text fields ignore ACTION_SET_TEXT (notably some WebViews and
    // certain custom inputs). Fall back to clipboard paste in that case.
    if (!ok) ok = await _service.pasteText(clean);
    return {
      'success': ok,
      'method': ok ? 'ghostType' : 'failed',
      'message': ok
          ? 'Typed "${clean.length > 40 ? '${clean.substring(0, 40)}…' : clean}"'
          : 'Could not find a focused text field.',
    };
  }

  Future<Map<String, dynamic>> runClickByText(String query) async {
    if (!state.accessibilityEnabled) {
      return {
        'success': false,
        'message':
            'Accessibility service is off. Open Tools → Automation and grant it.',
      };
    }
    final ok = await _service.clickByText(query);
    return {
      'success': ok,
      'query': query,
      'message': ok
          ? 'Tapped "$query"'
          : 'Could not find anything matching "$query" on screen.',
    };
  }

  Future<Map<String, dynamic>> runReadScreen() async {
    if (!state.accessibilityEnabled) {
      return {
        'success': false,
        'text': '',
        'message':
            'Accessibility service is off. Open Tools → Automation and grant it.',
      };
    }
    final raw = await _service.readScreenText();
    if (raw.isEmpty) {
      return {
        'success': false,
        'text': '',
        'message': 'No readable text on screen right now.',
      };
    }
    return {
      'success': true,
      'characters': raw.length,
      'text': raw.length > 4000 ? '${raw.substring(0, 4000)}…' : raw,
    };
  }

  Future<Map<String, dynamic>> runOcr() async {
    final r = await ScreenOcrService.instance.recognizeFromCamera();
    if (!r.success) {
      return {
        'success': false,
        'message': r.error ?? 'OCR failed.',
      };
    }
    if (r.text.isEmpty) {
      return {
        'success': false,
        'message': 'No text detected in the photo.',
      };
    }
    return {
      'success': true,
      'blocks': r.blockCount,
      'characters': r.text.length,
      'text': r.text.length > 4000
          ? '${r.text.substring(0, 4000)}…'
          : r.text,
    };
  }

  Future<Map<String, dynamic>> runGhostSequence(
    List<GhostAction> actions,
  ) async {
    if (!state.accessibilityEnabled) {
      return {
        'success': false,
        'message':
            'Accessibility service is off. Open Tools → Automation and grant it.',
      };
    }
    final r = await _service.ghostSequence(actions);
    return {
      'success': r.success,
      'completed': r.completed,
      'total': r.total,
      'message': r.success
          ? 'Sequence completed (${r.completed}/${r.total})'
          : (r.error ?? 'Sequence stopped at step ${r.completed}/${r.total}'),
    };
  }

  Future<Map<String, dynamic>> runGlobalAction(String action) async {
    if (!state.accessibilityEnabled) {
      return {
        'success': false,
        'message':
            'Accessibility service is off. Open Tools → Automation and grant it.',
      };
    }
    final ga = GlobalAction.values.firstWhere(
      (e) => e.name.toLowerCase() == action.toLowerCase(),
      orElse: () => GlobalAction.home,
    );
    final ok = await _service.globalAction(ga);
    return {
      'success': ok,
      'action': ga.name,
      'message': ok ? 'Triggered ${ga.name}' : 'Failed to trigger ${ga.name}',
    };
  }

  @override
  void dispose() {
    _postedSub?.cancel();
    _removedSub?.cancel();
    super.dispose();
  }
}

final automationProvider =
    StateNotifierProvider<AutomationNotifier, AutomationState>(
  (ref) {
    final n = AutomationNotifier();
    ref.onDispose(n.dispose);
    return n;
  },
);
