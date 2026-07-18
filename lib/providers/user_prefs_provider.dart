import 'dart:async';
import 'dart:developer' as dev;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:brutus_app/core/constants/api_constants.dart';

/// Brutus voice profile — mirrors the values GeminiVoiceService and
/// GeminiTtsService read from the `brutus_voice_profile` pref:
/// 'MALE' → Puck, 'FEMALE' → Aoede.
enum VoicePref { male, female }

extension VoicePrefX on VoicePref {
  String get storageValue => this == VoicePref.female ? 'FEMALE' : 'MALE';
  String get label => this == VoicePref.female ? 'Aoede · Female' : 'Puck · Male';
}

class UserPrefs {
  final String userName;
  final VoicePref voice;

  const UserPrefs({this.userName = 'Aditya', this.voice = VoicePref.male});

  /// Initials for the avatar chip — first letter of up to two words.
  String get initials {
    final parts = userName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'B';
    final first = parts.first[0];
    final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  /// First name only, for the greeting.
  String get firstName {
    final parts = userName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'there' : parts.first;
  }

  UserPrefs copyWith({String? userName, VoicePref? voice}) => UserPrefs(
        userName: userName ?? this.userName,
        voice: voice ?? this.voice,
      );
}

/// Persists the user-facing preferences the voice services already read:
/// `brutus_user_name` (system-prompt personalisation) and
/// `brutus_voice_profile` (Puck/Aoede). Until now these keys were read but
/// nothing in the UI could write them — this notifier closes that gap.
class UserPrefsNotifier extends StateNotifier<UserPrefs> {
  UserPrefsNotifier() : super(const UserPrefs()) {
    _restore();
  }

  static const _kName = 'brutus_user_name';
  static const _kVoice = 'brutus_voice_profile';

  void _restore() {
    try {
      final box = Hive.box(ApiConstants.boxPreferences);
      final name = box.get(_kName) as String?;
      final voiceRaw = box.get(_kVoice) as String?;
      state = UserPrefs(
        userName: (name == null || name.trim().isEmpty) ? 'Aditya' : name.trim(),
        voice: voiceRaw == 'FEMALE' ? VoicePref.female : VoicePref.male,
      );
    } catch (e) {
      dev.log('[Prefs] restore failed: $e', name: 'BrutusAI');
    }
  }

  void setUserName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return;
    state = state.copyWith(userName: clean);
    _persist(_kName, clean);
  }

  void setVoice(VoicePref voice) {
    state = state.copyWith(voice: voice);
    _persist(_kVoice, voice.storageValue);
  }

  void _persist(String key, String value) {
    // Fire-and-forget write, hopped to the root zone: if the caller runs
    // inside a fake-async zone (widget tests), a zone-captured Hive write
    // never completes and deadlocks Hive's write queue. In production the
    // root zone is the normal event loop — no behaviour change.
    Zone.root.run(() {
      try {
        Hive.box(ApiConstants.boxPreferences).put(key, value);
      } catch (e) {
        dev.log('[Prefs] persist $key failed: $e', name: 'BrutusAI');
      }
    });
  }
}

final userPrefsProvider =
    StateNotifierProvider<UserPrefsNotifier, UserPrefs>((ref) {
  return UserPrefsNotifier();
});

/// Live network status — drives the Connection status card on Home.
/// Emits true when at least one data path (wifi/cellular/ethernet) is up.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield (await connectivity.checkConnectivity())
      .any((r) => r != ConnectivityResult.none);
  await for (final results in connectivity.onConnectivityChanged) {
    yield results.any((r) => r != ConnectivityResult.none);
  }
});
