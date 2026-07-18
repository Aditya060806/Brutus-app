import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

/// Brutus — contacts lookup.
///
/// Resolves a spoken name like "Aditya" or "Mom" to a phone number so the
/// voice tools can address WhatsApp / SMS / calls without forcing the user
/// to dictate raw digits.
///
/// Caches the device contact book in memory after the first read so
/// repeated lookups don't keep poking the system content provider.
/// The cache is invalidated whenever the OS broadcasts a contacts change
/// (handled via [FlutterContacts.onDatabaseChange]).
class ContactsService {
  ContactsService._();
  static final ContactsService instance = ContactsService._();

  List<Contact>? _cache;
  Future<List<Contact>>? _inFlight;
  StreamSubscription<void>? _changesSub;

  void _log(String msg) => dev.log('[Contacts] $msg', name: 'BrutusAI');

  /// Request READ_CONTACTS at runtime. Returns true if granted.
  Future<bool> ensurePermission() async {
    final status = await Permission.contacts.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;
    final asked = await Permission.contacts.request();
    return asked.isGranted;
  }

  Future<bool> hasPermission() async => Permission.contacts.isGranted;

  /// Returns every contact that has at least one phone number, or an empty
  /// list if permission is denied / not granted yet.
  Future<List<Contact>> _loadAll({bool force = false}) async {
    if (!force && _cache != null) return _cache!;
    if (_inFlight != null) return _inFlight!;

    if (!await ensurePermission()) {
      _log('permission denied');
      return const <Contact>[];
    }

    _startChangeListener();

    final completer = Completer<List<Contact>>();
    _inFlight = completer.future;
    try {
      // We only need names + phone numbers — skip photos, emails, etc.
      final list = await FlutterContacts.getAll(
        properties: const {ContactProperty.name, ContactProperty.phone},
      );
      // Drop any contact with no phone number — useless for voice routing.
      final filtered = list.where((c) => c.phones.isNotEmpty).toList();
      _cache = filtered;
      completer.complete(filtered);
      _log('loaded ${filtered.length} contacts');
      return filtered;
    } catch (e) {
      _log('load failed: $e');
      completer.complete(const <Contact>[]);
      return const <Contact>[];
    } finally {
      _inFlight = null;
    }
  }

  void _startChangeListener() {
    if (_changesSub != null) return;
    try {
      _changesSub = FlutterContacts.onDatabaseChange.listen((_) {
        _cache = null;
        _log('contacts changed; cache invalidated');
      });
    } catch (e) {
      _log('listener setup failed: $e');
    }
  }

  /// Find the best phone match for [name]. Strategy:
  ///   1. Exact display-name match (case-insensitive)
  ///   2. Display name starts with the query
  ///   3. First-name match
  ///   4. Display name contains the query
  /// Within each tier, prefer mobile/cell numbers over landline.
  Future<ContactMatch?> findByName(String name) async {
    final clean = name.trim().toLowerCase();
    if (clean.isEmpty) return null;

    final all = await _loadAll();
    if (all.isEmpty) return null;

    Contact? exact;
    Contact? prefix;
    Contact? contains;
    Contact? firstName;

    for (final c in all) {
      final display = (c.displayName ?? '').toLowerCase();
      if (display.isEmpty) continue;
      if (display == clean) {
        exact = c;
        break;
      }
      if (prefix == null && display.startsWith(clean)) prefix = c;
      if (contains == null && display.contains(clean)) contains = c;
      final fn = (c.name?.first ?? '').toLowerCase();
      if (firstName == null && fn.isNotEmpty && fn == clean) firstName = c;
    }

    final pick = exact ?? prefix ?? firstName ?? contains;
    if (pick == null) return null;

    final phone = _bestPhone(pick);
    if (phone == null) return null;

    return ContactMatch(
      displayName: pick.displayName ?? phone,
      rawNumber: phone,
      e164: _toE164(phone),
    );
  }

  /// Multi-match — for "show contacts named X". Useful for resolving
  /// ambiguity ("which Aditya?").
  Future<List<ContactMatch>> searchByName(String name, {int limit = 5}) async {
    final clean = name.trim().toLowerCase();
    if (clean.isEmpty) return const [];
    final all = await _loadAll();
    final hits = <ContactMatch>[];
    for (final c in all) {
      final display = (c.displayName ?? '').toLowerCase();
      if (display.isEmpty || !display.contains(clean)) continue;
      final phone = _bestPhone(c);
      if (phone == null) continue;
      hits.add(ContactMatch(
        displayName: c.displayName ?? phone,
        rawNumber: phone,
        e164: _toE164(phone),
      ));
      if (hits.length >= limit) break;
    }
    return hits;
  }

  String? _bestPhone(Contact c) {
    if (c.phones.isEmpty) return null;
    // Prefer mobile / cell labels, then anything else.
    for (final p in c.phones) {
      final lbl = p.label.label;
      if (lbl == PhoneLabel.mobile || lbl == PhoneLabel.iPhone) {
        return p.number;
      }
    }
    return c.phones.first.number;
  }

  /// Best-effort E.164 conversion. Strips non-digits; if the cleaned number
  /// is exactly 10 digits and starts with a non-zero, prepends India's +91.
  /// Otherwise returns the cleaned digits as-is — Android's `tel:`/`smsto:`
  /// schemes accept both formats.
  String _toE164(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.startsWith('+')) return cleaned.substring(1);
    if (cleaned.length == 10 && !cleaned.startsWith('0')) {
      // Default region: India (+91). Override later if you ship internationally.
      return '91$cleaned';
    }
    return cleaned;
  }

  Future<void> warmUp() async {
    if (_cache != null) return;
    if (await hasPermission()) {
      unawaited(_loadAll());
    }
  }

  void dispose() {
    _changesSub?.cancel();
    _changesSub = null;
  }
}

class ContactMatch {
  /// The display name as stored on the device.
  final String displayName;

  /// The phone number as the user originally entered it (with formatting).
  final String rawNumber;

  /// Digits-only E.164 (no leading `+`) ready for `wa.me/` and `tel:`.
  final String e164;

  const ContactMatch({
    required this.displayName,
    required this.rawNumber,
    required this.e164,
  });

  Map<String, dynamic> toMap() => {
        'name': displayName,
        'number': rawNumber,
        'e164': e164,
      };
}
