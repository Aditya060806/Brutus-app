import 'package:connectivity_plus/connectivity_plus.dart';

/// Brutus Mobile — Connectivity guard.
///
/// Every Phase-3 service calls [ensureOnline] before firing an HTTP request
/// so that an offline device fails fast (instant inline error) instead of
/// waiting for the 60s receive timeout.
class NetworkGuard {
  static final Connectivity _connectivity = Connectivity();

  /// Returns true when there's at least one live data connection.
  static Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Throws [OfflineException] when the device has no data connection.
  static Future<void> ensureOnline() async {
    if (!await isOnline()) {
      throw const OfflineException();
    }
  }
}

/// Thrown by services when the device is offline. Caught by callers to
/// surface a friendly inline state without retrying.
class OfflineException implements Exception {
  const OfflineException();
  @override
  String toString() => "You're offline. Reconnect and try again.";
}
