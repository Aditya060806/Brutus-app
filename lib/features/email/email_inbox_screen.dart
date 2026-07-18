import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/shared_widgets.dart';
import 'package:brutus_app/features/email/compose_email_screen.dart';
import 'package:brutus_app/features/email/email_detail_screen.dart';
import 'package:brutus_app/providers/email_provider.dart';

/// Brutus Mobile — Gmail inbox.
///
/// Real Google Sign-In + Gmail v1. Three states:
///   • initialising  → silent sign-in is in flight
///   • signed-out    → sign-in CTA card
///   • signed-in     → inbox list with refresh + compose + archive
class EmailInboxScreen extends ConsumerStatefulWidget {
  const EmailInboxScreen({super.key});

  @override
  ConsumerState<EmailInboxScreen> createState() => _EmailInboxScreenState();
}

class _EmailInboxScreenState extends ConsumerState<EmailInboxScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(emailProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Email'),
        actions: state.isSignedIn
            ? [
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Iconsax.refresh, size: 20),
                  onPressed: () => ref.read(emailProvider.notifier).refresh(),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Iconsax.more, size: 20),
                  onSelected: (v) {
                    if (v == 'signout') {
                      ref.read(emailProvider.notifier).signOut();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'signout',
                      child: Text('Sign out'),
                    ),
                  ],
                ),
              ]
            : null,
      ),
      floatingActionButton: state.isSignedIn
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ComposeEmailScreen(),
                ),
              ),
              icon: const Icon(Iconsax.edit),
              label: const Text('Compose'),
            )
          : null,
      body: state.initialising
          ? const Center(child: CircularProgressIndicator())
          : !state.isSignedIn
              ? _SignInCta(
                  loading: state.loading,
                  errorMessage: state.errorMessage,
                  offline: state.offline,
                  onSignIn: () => ref.read(emailProvider.notifier).signIn(),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.read(emailProvider.notifier).refresh(),
                  child: _InboxList(state: state),
                ),
    );
  }
}

class _InboxList extends ConsumerWidget {
  final EmailState state;
  const _InboxList({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading && state.inbox.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorMessage != null && state.inbox.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            state.errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      );
    }
    if (state.inbox.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          const SizedBox(height: 80),
          const Icon(Iconsax.sms_tracking,
              size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Inbox is clear',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'Pull down to refresh.',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: state.inbox.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return _AccountHeader(state: state)
              .animate()
              .fadeIn(duration: 250.ms);
        }
        final email = state.inbox[i - 1];
        return _EmailTile(email: email)
            .animate(delay: Duration(milliseconds: 30 * (i > 6 ? 0 : i)))
            .fadeIn(duration: 250.ms)
            .slideX(begin: 0.03);
      },
    );
  }
}

class _AccountHeader extends StatelessWidget {
  final EmailState state;
  const _AccountHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.primaryGlow,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Iconsax.user, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.userName ?? 'Signed in',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  state.userEmail ?? '',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (state.unreadCount > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${state.unreadCount} unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmailTile extends ConsumerWidget {
  final BrutusEmail email;
  const _EmailTile({required this.email});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: Key(email.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 18),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Iconsax.archive, color: AppColors.warning),
        ),
        onDismissed: (_) =>
            ref.read(emailProvider.notifier).archive(email.id),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              if (email.isUnread) {
                ref.read(emailProvider.notifier).markRead(email.id);
              }
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EmailDetailScreen(emailId: email.id),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: email.isUnread
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : AppColors.border,
                  width: 0.5,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        email.avatarLetters,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                email.fromName.isEmpty
                                    ? email.fromEmail
                                    : email.fromName,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: email.isUnread
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _relative(email.date),
                              style: TextStyle(
                                fontSize: 11,
                                color: email.isUnread
                                    ? AppColors.primary
                                    : AppColors.textTertiary,
                                fontWeight: email.isUnread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email.subject.isEmpty
                              ? '(no subject)'
                              : email.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: email.isUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          email.snippet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (email.isUnread) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _relative(DateTime? dt) {
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays == 1) return 'Yesterday';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${dt.day}/${dt.month}';
  }
}

class _SignInCta extends StatelessWidget {
  final bool loading;
  final bool offline;
  final String? errorMessage;
  final VoidCallback onSignIn;

  const _SignInCta({
    required this.loading,
    required this.offline,
    required this.errorMessage,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: AppColors.primaryGlow,
                ),
                child: const Icon(
                  Iconsax.sms,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Connect your Gmail',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Brutus reads recent messages, sends new ones, and helps you triage by voice.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: loading ? null : onSignIn,
                  icon: loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Iconsax.user_octagon, size: 16),
                  label: Text(loading ? 'Signing in…' : 'Sign in with Google'),
                ),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (offline ? AppColors.warning : AppColors.error)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        offline ? Iconsax.wifi : Iconsax.warning_2,
                        size: 14,
                        color: offline ? AppColors.warning : AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                offline ? AppColors.warning : AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                'Brutus uses Google\'s official OAuth — your credentials never touch our servers.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
