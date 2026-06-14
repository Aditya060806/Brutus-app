import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:brutus_app/data/services/gmail_service.dart';
import 'package:brutus_app/data/services/network_guard.dart';

export 'package:brutus_app/data/services/gmail_service.dart'
    show BrutusEmail, BrutusEmailDetail, GmailService, GmailNotSignedInException;

class EmailState {
  final bool initialising;
  final bool isSignedIn;
  final String? userEmail;
  final String? userName;
  final List<BrutusEmail> inbox;
  final bool loading;
  final String? errorMessage;
  final bool offline;

  const EmailState({
    this.initialising = true,
    this.isSignedIn = false,
    this.userEmail,
    this.userName,
    this.inbox = const [],
    this.loading = false,
    this.errorMessage,
    this.offline = false,
  });

  EmailState copyWith({
    bool? initialising,
    bool? isSignedIn,
    String? userEmail,
    String? userName,
    List<BrutusEmail>? inbox,
    bool? loading,
    String? errorMessage,
    bool? offline,
    bool clearError = false,
  }) {
    return EmailState(
      initialising: initialising ?? this.initialising,
      isSignedIn: isSignedIn ?? this.isSignedIn,
      userEmail: userEmail ?? this.userEmail,
      userName: userName ?? this.userName,
      inbox: inbox ?? this.inbox,
      loading: loading ?? this.loading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      offline: offline ?? this.offline,
    );
  }

  int get unreadCount => inbox.where((e) => e.isUnread).length;
}

class EmailNotifier extends StateNotifier<EmailState> {
  EmailNotifier({GmailService? service})
      : _service = service ?? GmailService.instance,
        super(const EmailState()) {
    _initialise();
  }

  final GmailService _service;
  // Resolved when the constructor's silent-sign-in attempt finishes (whether
  // it found a stored account or not). Voice-tool runners await this so the
  // first tool call after app boot doesn't race with the still-in-flight
  // silent restore.
  final Completer<void> _initReady = Completer<void>();

  void _log(String msg) => dev.log('[EmailProv] $msg', name: 'BrutusAI');

  Future<void> _initialise() async {
    final account = await _service.trySilentSignIn();
    if (account != null) {
      state = state.copyWith(
        initialising: false,
        isSignedIn: true,
        userEmail: account.email,
        userName: account.displayName,
      );
      await refresh();
    } else {
      state = state.copyWith(
        initialising: false,
        isSignedIn: false,
      );
    }
    if (!_initReady.isCompleted) _initReady.complete();
  }

  Future<void> signIn() async {
    state = state.copyWith(loading: true, clearError: true, offline: false);
    try {
      final account = await _service.signIn();
      if (account == null) {
        state = state.copyWith(loading: false);
        return;
      }
      state = state.copyWith(
        isSignedIn: true,
        userEmail: account.email,
        userName: account.displayName,
        loading: false,
      );
      await refresh();
    } on OfflineException catch (e) {
      state = state.copyWith(
        loading: false,
        offline: true,
        errorMessage: e.toString(),
      );
    } catch (e) {
      _log('signIn failed: $e');
      state = state.copyWith(
        loading: false,
        errorMessage: 'Sign-in failed: $e',
      );
    }
  }

  Future<void> signOut() async {
    await _service.signOut();
    state = const EmailState(initialising: false, isSignedIn: false);
  }

  /// Refresh the inbox list.
  Future<void> refresh({int maxResults = 20}) async {
    if (!state.isSignedIn) return;
    state = state.copyWith(loading: true, clearError: true, offline: false);
    try {
      final list = await _service.listInbox(maxResults: maxResults);
      state = state.copyWith(loading: false, inbox: list);
    } on GmailNotSignedInException {
      state = state.copyWith(loading: false, isSignedIn: false);
    } on OfflineException catch (e) {
      state = state.copyWith(
        loading: false,
        offline: true,
        errorMessage: e.toString(),
      );
    } catch (e) {
      _log('refresh failed: $e');
      state = state.copyWith(
        loading: false,
        errorMessage: 'Could not load inbox: $e',
      );
    }
  }

  Future<BrutusEmailDetail?> getMessage(String id) async {
    try {
      return await _service.getMessage(id);
    } catch (e) {
      _log('getMessage failed: $e');
      state = state.copyWith(errorMessage: 'Could not load message: $e');
      return null;
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _service.markRead(id);
      // Optimistic local update — flip the flag without refetching.
      state = state.copyWith(
        inbox: state.inbox
            .map((e) => e.id == id
                ? BrutusEmail(
                    id: e.id,
                    threadId: e.threadId,
                    fromName: e.fromName,
                    fromEmail: e.fromEmail,
                    subject: e.subject,
                    snippet: e.snippet,
                    date: e.date,
                    isUnread: false,
                  )
                : e)
            .toList(),
      );
    } catch (e) {
      _log('markRead failed: $e');
    }
  }

  Future<void> archive(String id) async {
    try {
      await _service.archive(id);
      state = state.copyWith(
        inbox: state.inbox.where((e) => e.id != id).toList(),
      );
    } catch (e) {
      _log('archive failed: $e');
      state = state.copyWith(errorMessage: 'Archive failed: $e');
    }
  }

  Future<String?> send({
    required String to,
    required String subject,
    required String body,
    String? cc,
    String? bcc,
  }) async {
    try {
      final id = await _service.send(
        to: to,
        subject: subject,
        body: body,
        cc: cc,
        bcc: bcc,
      );
      // Refresh inbox in the background — the sent message lives under SENT,
      // not INBOX, so no list change is expected; this is a courtesy refresh
      // to surface any new arrivals while the compose modal was open.
      unawaited(refresh());
      return id;
    } on GmailNotSignedInException {
      state = state.copyWith(isSignedIn: false);
      return null;
    } catch (e) {
      _log('send failed: $e');
      state = state.copyWith(errorMessage: 'Send failed: $e');
      return null;
    }
  }

  // ── Voice tool surface ──────────────────────────────────────────────────

  /// Used by `read_emails` voice tool. Returns a structured map the
  /// dispatcher hands back to Gemini. Awaits the silent-sign-in attempt so
  /// the first call after app boot doesn't race with it.
  Future<Map<String, dynamic>> runReadEmailsForTool({int max = 5}) async {
    await _initReady.future;
    if (!state.isSignedIn) {
      return {
        'count': 0,
        'emails': const <Map<String, dynamic>>[],
        'note':
            'Open Tools → Email and sign in with Google so Brutus can read your inbox.',
      };
    }
    try {
      final list = await _service.listInbox(maxResults: max);
      return {
        'count': list.length,
        'emails': list
            .map((e) => {
                  'from': e.fromName.isEmpty ? e.fromEmail : e.fromName,
                  'subject': e.subject,
                  'snippet': e.snippet,
                  'time': e.date?.toIso8601String(),
                  'unread': e.isUnread,
                })
            .toList(),
      };
    } catch (e) {
      return {'error': 'Could not fetch inbox: $e'};
    }
  }

  /// Used by `send_email` voice tool. Same race-safety as
  /// [runReadEmailsForTool] — awaits the silent restore first.
  Future<Map<String, dynamic>> runSendEmailForTool({
    required String to,
    required String subject,
    required String body,
  }) async {
    await _initReady.future;
    if (!state.isSignedIn) {
      return {
        'success': false,
        'error':
            'Open Tools → Email and sign in with Google before asking Brutus to send mail.',
      };
    }
    final id = await send(to: to, subject: subject, body: body);
    if (id == null || id.isEmpty) {
      return {'success': false, 'error': state.errorMessage ?? 'Send failed.'};
    }
    return {
      'success': true,
      'messageId': id,
      'message': 'Sent to $to',
    };
  }
}

final emailProvider = StateNotifierProvider<EmailNotifier, EmailState>(
  (ref) => EmailNotifier(),
);
