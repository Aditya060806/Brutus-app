import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/providers/email_provider.dart';

/// Compose / reply screen.
class ComposeEmailScreen extends ConsumerStatefulWidget {
  final String? replyTo;
  final String? replySubject;
  const ComposeEmailScreen({super.key, this.replyTo, this.replySubject});

  @override
  ConsumerState<ComposeEmailScreen> createState() =>
      _ComposeEmailScreenState();
}

class _ComposeEmailScreenState extends ConsumerState<ComposeEmailScreen> {
  late final TextEditingController _to;
  late final TextEditingController _subject;
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _to = TextEditingController(text: widget.replyTo ?? '');
    final replySubj = widget.replySubject ?? '';
    _subject = TextEditingController(
      text: replySubj.isEmpty
          ? ''
          : replySubj.startsWith('Re:')
              ? replySubj
              : 'Re: $replySubj',
    );
  }

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final to = _to.text.trim();
    final subject = _subject.text.trim();
    final body = _body.text.trim();
    if (to.isEmpty) {
      _snack('Add a recipient.');
      return;
    }
    if (subject.isEmpty) {
      _snack('Subject is empty — send anyway?', actionLabel: 'Send', onAction: _doSend);
      return;
    }
    if (body.isEmpty) {
      _snack('Body is empty — send anyway?',
          actionLabel: 'Send', onAction: _doSend);
      return;
    }
    await _doSend();
  }

  Future<void> _doSend() async {
    setState(() => _sending = true);
    final id = await ref.read(emailProvider.notifier).send(
          to: _to.text.trim(),
          subject: _subject.text.trim(),
          body: _body.text.trim(),
        );
    if (!mounted) return;
    setState(() => _sending = false);
    if (id != null && id.isNotEmpty) {
      _snack('Sent ✓');
      Navigator.pop(context);
    } else {
      _snack(ref.read(emailProvider).errorMessage ?? 'Send failed.');
    }
  }

  void _snack(String msg, {String? actionLabel, VoidCallback? onAction}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        action: (actionLabel == null || onAction == null)
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.replyTo == null ? 'New email' : 'Reply'),
        actions: [
          TextButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Iconsax.send_1, size: 16),
            label: Text(_sending ? 'Sending…' : 'Send'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Field(
              label: 'To',
              controller: _to,
              hint: 'name@example.com',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),
            _Field(
              label: 'Subject',
              controller: _subject,
              hint: '(optional)',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _body,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Write your message…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textTertiary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
