import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io' show HttpDate;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;

import 'package:brutus_app/data/services/network_guard.dart';

/// Brutus Mobile — Gmail service.
///
/// Wraps Google Sign-In + Gmail v1 REST. Handles:
///   • Silent sign-in on app start (no prompt if previously authorised)
///   • Interactive sign-in on demand
///   • Listing inbox with primary metadata (sender, subject, snippet, time, read state)
///   • Fetching a single message body (text + HTML)
///   • Sending an RFC-2822 encoded email
///   • Marking as read / archive
///   • Sign-out + revoke
class GmailService {
  GmailService._();
  static final GmailService instance = GmailService._();

  static const _scopes = <String>[
    gmail.GmailApi.gmailReadonlyScope,
    gmail.GmailApi.gmailSendScope,
    gmail.GmailApi.gmailModifyScope,
    'email',
    'profile',
  ];

  late final GoogleSignIn _gsi = GoogleSignIn(scopes: _scopes);

  /// In-memory http client built from the current account's auth headers.
  /// Refreshed each time we need a Gmail API call so token expiry is handled.
  Future<gmail.GmailApi> _api(GoogleSignInAccount account) async {
    final headers = await account.authHeaders;
    final client = _GoogleAuthClient(headers);
    return gmail.GmailApi(client);
  }

  void _log(String msg) => dev.log('[Gmail] $msg', name: 'BrutusAI');

  /// Currently signed-in account, or null.
  GoogleSignInAccount? get currentAccount => _gsi.currentUser;

  /// True when the user has an active Google session for Brutus.
  bool get isSignedIn => _gsi.currentUser != null;

  /// Try to silently restore a prior session. Safe to call on app boot.
  Future<GoogleSignInAccount?> trySilentSignIn() async {
    try {
      final account = await _gsi.signInSilently();
      if (account != null) _log('silent sign-in restored ${account.email}');
      return account;
    } catch (e) {
      _log('silent sign-in failed: $e');
      return null;
    }
  }

  /// Show the interactive Google account picker.
  Future<GoogleSignInAccount?> signIn() async {
    await NetworkGuard.ensureOnline();
    final account = await _gsi.signIn();
    if (account != null) _log('sign-in completed for ${account.email}');
    return account;
  }

  /// Sign out, revoke the OAuth grant, and forget the account.
  Future<void> signOut() async {
    try {
      await _gsi.disconnect();
    } catch (e) {
      _log('disconnect failed: $e');
    }
    try {
      await _gsi.signOut();
    } catch (_) {}
  }

  // ── List ────────────────────────────────────────────────────────────────

  /// Fetch up to [maxResults] inbox messages. Each `BrutusEmail` is a
  /// lightweight metadata view — body fetching is done lazily on demand.
  Future<List<BrutusEmail>> listInbox({
    int maxResults = 20,
    String? pageToken,
    String query = 'in:inbox',
  }) async {
    final account = _gsi.currentUser;
    if (account == null) throw const GmailNotSignedInException();

    await NetworkGuard.ensureOnline();
    final api = await _api(account);

    final list = await api.users.messages.list(
      'me',
      maxResults: maxResults,
      q: query,
      pageToken: pageToken,
    );
    final messageIds = list.messages ?? const <gmail.Message>[];

    // Fetch headers in parallel for speed.
    final futures = messageIds.map((m) async {
      final full = await api.users.messages.get(
        'me',
        m.id!,
        format: 'metadata',
        metadataHeaders: const ['From', 'Subject', 'Date'],
      );
      return BrutusEmail.fromMessage(full);
    });
    return Future.wait(futures);
  }

  // ── Detail ──────────────────────────────────────────────────────────────

  /// Fetch one message in full so we can render body text or HTML.
  Future<BrutusEmailDetail> getMessage(String id) async {
    final account = _gsi.currentUser;
    if (account == null) throw const GmailNotSignedInException();

    await NetworkGuard.ensureOnline();
    final api = await _api(account);

    final full = await api.users.messages.get('me', id, format: 'full');
    return BrutusEmailDetail.fromMessage(full);
  }

  // ── Send ────────────────────────────────────────────────────────────────

  /// Send a plaintext email. Returns the new Gmail message id.
  Future<String> send({
    required String to,
    required String subject,
    required String body,
    String? cc,
    String? bcc,
  }) async {
    final account = _gsi.currentUser;
    if (account == null) throw const GmailNotSignedInException();

    await NetworkGuard.ensureOnline();
    final api = await _api(account);
    final from = account.email;

    final raw = StringBuffer()
      ..writeln('From: $from')
      ..writeln('To: $to');
    if (cc != null && cc.trim().isNotEmpty) raw.writeln('Cc: $cc');
    if (bcc != null && bcc.trim().isNotEmpty) raw.writeln('Bcc: $bcc');
    raw
      ..writeln('Subject: $subject')
      ..writeln('Content-Type: text/plain; charset="UTF-8"')
      ..writeln('MIME-Version: 1.0')
      ..writeln()
      ..writeln(body);

    final encoded = base64Url.encode(utf8.encode(raw.toString()));
    final msg = gmail.Message(raw: encoded);
    final sent = await api.users.messages.send(msg, 'me');
    _log('sent message ${sent.id}');
    return sent.id ?? '';
  }

  // ── Mutate ──────────────────────────────────────────────────────────────

  /// Strip the UNREAD label.
  Future<void> markRead(String id) async {
    final account = _gsi.currentUser;
    if (account == null) throw const GmailNotSignedInException();
    await NetworkGuard.ensureOnline();
    final api = await _api(account);
    await api.users.messages.modify(
      gmail.ModifyMessageRequest(removeLabelIds: const ['UNREAD']),
      'me',
      id,
    );
  }

  /// Strip INBOX (Gmail's "archive").
  Future<void> archive(String id) async {
    final account = _gsi.currentUser;
    if (account == null) throw const GmailNotSignedInException();
    await NetworkGuard.ensureOnline();
    final api = await _api(account);
    await api.users.messages.modify(
      gmail.ModifyMessageRequest(removeLabelIds: const ['INBOX']),
      'me',
      id,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

/// Lightweight email view used by the inbox list.
class BrutusEmail {
  final String id;
  final String threadId;
  final String fromName;
  final String fromEmail;
  final String subject;
  final String snippet;
  final DateTime? date;
  final bool isUnread;

  const BrutusEmail({
    required this.id,
    required this.threadId,
    required this.fromName,
    required this.fromEmail,
    required this.subject,
    required this.snippet,
    required this.date,
    required this.isUnread,
  });

  String get avatarLetters {
    final source = fromName.isEmpty ? fromEmail : fromName;
    final words = source.split(RegExp(r'\s+'));
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      return source.substring(0, source.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }

  factory BrutusEmail.fromMessage(gmail.Message m) {
    final headers = (m.payload?.headers ?? const <gmail.MessagePartHeader>[]);
    String h(String name) {
      final hh = headers.firstWhere(
        (e) => (e.name?.toLowerCase() ?? '') == name.toLowerCase(),
        orElse: () => gmail.MessagePartHeader(),
      );
      return hh.value ?? '';
    }

    final fromRaw = h('From');
    final mailMatch = RegExp(r'<([^>]+)>').firstMatch(fromRaw);
    final email = (mailMatch != null) ? mailMatch.group(1)! : fromRaw.trim();
    final namePart = (mailMatch != null)
        ? fromRaw.substring(0, mailMatch.start).trim().replaceAll('"', '')
        : '';

    return BrutusEmail(
      id: m.id ?? '',
      threadId: m.threadId ?? '',
      fromName: namePart.isEmpty ? email : namePart,
      fromEmail: email,
      subject: h('Subject'),
      snippet: m.snippet ?? '',
      date: _parseDateHeader(h('Date')),
      isUnread:
          (m.labelIds ?? const <String>[]).contains('UNREAD'),
    );
  }
}

/// Full message body — text and (optionally) HTML.
class BrutusEmailDetail {
  final BrutusEmail meta;
  final String? plainBody;
  final String? htmlBody;

  const BrutusEmailDetail({
    required this.meta,
    this.plainBody,
    this.htmlBody,
  });

  factory BrutusEmailDetail.fromMessage(gmail.Message m) {
    final meta = BrutusEmail.fromMessage(m);
    String? plain;
    String? html;

    void walk(gmail.MessagePart? p) {
      if (p == null) return;
      final mime = p.mimeType ?? '';
      final bodyData = p.body?.data;
      if (mime == 'text/plain' && bodyData != null && plain == null) {
        plain = utf8.decode(
          base64Url.decode(_padBase64(bodyData)),
          allowMalformed: true,
        );
      } else if (mime == 'text/html' && bodyData != null && html == null) {
        html = utf8.decode(
          base64Url.decode(_padBase64(bodyData)),
          allowMalformed: true,
        );
      }
      for (final part in p.parts ?? const <gmail.MessagePart>[]) {
        walk(part);
      }
    }

    walk(m.payload);
    return BrutusEmailDetail(meta: meta, plainBody: plain, htmlBody: html);
  }
}

DateTime? _parseDateHeader(String raw) {
  if (raw.isEmpty) return null;
  // Trim a trailing "(GMT)" / "(UTC)" comment some clients append.
  final cleaned = raw.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
  try {
    return HttpDate.parse(cleaned);
  } catch (_) {
    return null;
  }
}

String _padBase64(String s) {
  final mod = s.length % 4;
  if (mod == 0) return s;
  return s + ('=' * (4 - mod));
}

// ─────────────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────────────

class GmailNotSignedInException implements Exception {
  const GmailNotSignedInException();
  @override
  String toString() =>
      'Sign in with Google in Tools → Email to use Gmail features.';
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP client wrapper that injects Google Sign-In auth headers.
// ─────────────────────────────────────────────────────────────────────────────

class _GoogleAuthClient extends http.BaseClient implements auth.AuthClient {
  _GoogleAuthClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();

  @override
  auth.AccessCredentials get credentials => throw UnimplementedError(
        'AccessCredentials are not exposed by GoogleSignIn — use authHeaders.',
      );
}
