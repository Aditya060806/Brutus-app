import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/shared_widgets.dart';
import 'package:brutus_app/features/email/compose_email_screen.dart';
import 'package:brutus_app/providers/email_provider.dart';

/// Brutus Mobile — single-message view.
///
/// Loads the message body lazily on open. Body is rendered as plain text
/// (Gmail HTML is intentionally not rendered to avoid embedded JS / tracking
/// pixels — fall back to Gmail web for rich layouts).
class EmailDetailScreen extends ConsumerStatefulWidget {
  final String emailId;
  const EmailDetailScreen({super.key, required this.emailId});

  @override
  ConsumerState<EmailDetailScreen> createState() => _EmailDetailScreenState();
}

class _EmailDetailScreenState extends ConsumerState<EmailDetailScreen> {
  BrutusEmailDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final detail = await ref
        .read(emailProvider.notifier)
        .getMessage(widget.emailId);
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loading = false;
      _error = detail == null ? 'Could not load message.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Message'),
        actions: [
          if (_detail != null)
            IconButton(
              tooltip: 'Archive',
              icon: const Icon(Iconsax.archive, size: 20),
              onPressed: () async {
                final navigator = Navigator.of(context);
                await ref
                    .read(emailProvider.notifier)
                    .archive(widget.emailId);
                if (mounted) navigator.pop();
              },
            ),
        ],
      ),
      floatingActionButton: _detail == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ComposeEmailScreen(
                    replyTo: _detail!.meta.fromEmail,
                    replySubject: _detail!.meta.subject,
                  ),
                ),
              ),
              icon: const Icon(Iconsax.refresh_2),
              label: const Text('Reply'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                )
              : _Body(detail: _detail!),
    );
  }
}

class _Body extends StatelessWidget {
  final BrutusEmailDetail detail;
  const _Body({required this.detail});

  @override
  Widget build(BuildContext context) {
    final m = detail.meta;
    final dateLabel = m.date == null
        ? ''
        : '${m.date!.day}/${m.date!.month}/${m.date!.year} '
            '${m.date!.hour.toString().padLeft(2, '0')}:'
            '${m.date!.minute.toString().padLeft(2, '0')}';

    final body = (detail.plainBody?.trim().isNotEmpty ?? false)
        ? detail.plainBody!
        : (detail.htmlBody ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      physics: const BouncingScrollPhysics(),
      children: [
        Text(
          m.subject.isEmpty ? '(no subject)' : m.subject,
          style: Theme.of(context).textTheme.headlineSmall,
        ).animate().fadeIn(duration: 250.ms),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  m.avatarLetters,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.fromName.isEmpty ? m.fromEmail : m.fromName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    m.fromEmail,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              dateLabel,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Divider(height: 1),
        const SizedBox(height: 16),
        if (body.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'This message has no plain-text body. Open it in Gmail for the full HTML version.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              body,
              style: const TextStyle(
                fontSize: 14,
                height: 1.55,
                color: AppColors.textPrimary,
              ),
            ),
          ),
      ],
    );
  }
}
