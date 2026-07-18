import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/providers/notes_provider.dart' as notes_pkg;
import 'package:brutus_app/providers/rag_oracle_provider.dart';

/// Bottom sheet shown by the FAB on the Library tab. Three add actions —
/// "Add notes", "Paste text", "Import file" — each opens its own modal flow.
class IngestSheet extends ConsumerWidget {
  const IngestSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Add knowledge', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Pick a source. Each item is chunked and embedded so Brutus can answer questions against it.',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 14),
            _Tile(
              icon: Iconsax.note,
              color: AppColors.notes,
              title: 'Add notes',
              subtitle: 'Pick from your existing Brutus notes',
              onTap: () async {
                Navigator.pop(context);
                await _AddNotesFlow.show(context, ref);
              },
            ),
            const SizedBox(height: 8),
            _Tile(
              icon: Iconsax.text,
              color: AppColors.primary,
              title: 'Paste text',
              subtitle: 'Drop in a snippet or article',
              onTap: () async {
                Navigator.pop(context);
                await _PasteFlow.show(context, ref);
              },
            ),
            const SizedBox(height: 8),
            _Tile(
              icon: Iconsax.document_upload,
              color: AppColors.info,
              title: 'Import file',
              subtitle: '.txt or .md up to ~1 MB',
              onTap: () async {
                Navigator.pop(context);
                await _ImportFlow.run(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Iconsax.arrow_right_3,
                size: 16,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add notes flow — multi-select existing notes
// ─────────────────────────────────────────────────────────────────────────────

class _AddNotesFlow {
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final notes = ref.read(notes_pkg.notesProvider);
    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have no notes to add yet.')),
      );
      return;
    }
    final selected = await showModalBottomSheet<List<notes_pkg.Note>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _NotePicker(notes: notes),
    );
    if (selected == null || selected.isEmpty) return;
    if (!context.mounted) return;
    await _IngestProgress.run(
      context,
      ref,
      label: '${selected.length} note(s)',
      action: (notifier, report) async {
        for (var i = 0; i < selected.length; i++) {
          final n = selected[i];
          report('Indexing ${i + 1} of ${selected.length}: ${n.title}');
          final err = await notifier.ingest(
            title: n.title,
            text: n.content.isEmpty ? n.title : n.content,
            source: RagSourceKind.note,
            sourceRef: n.id,
            documentId: 'note:${n.id}',
          );
          if (err != null) return err;
        }
        return null;
      },
    );
  }
}

class _NotePicker extends StatefulWidget {
  final List<notes_pkg.Note> notes;
  const _NotePicker({required this.notes});

  @override
  State<_NotePicker> createState() => _NotePickerState();
}

class _NotePickerState extends State<_NotePicker> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Pick notes (${_selected.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () {
                            final picked = widget.notes
                                .where((n) => _selected.contains(n.id))
                                .toList();
                            Navigator.pop(context, picked);
                          },
                    child: const Text('Index'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: widget.notes.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
                itemBuilder: (context, i) {
                  final n = widget.notes[i];
                  final picked = _selected.contains(n.id);
                  return CheckboxListTile(
                    value: picked,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(n.id);
                      } else {
                        _selected.remove(n.id);
                      }
                    }),
                    title: Text(
                      n.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      n.content.isEmpty ? '(empty)' : n.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    controlAffinity: ListTileControlAffinity.trailing,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Paste flow
// ─────────────────────────────────────────────────────────────────────────────

class _PasteFlow {
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final titleCtrl = TextEditingController();
    final textCtrl = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Paste text',
                style: Theme.of(sheetCtx).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Title (optional)',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: textCtrl,
              maxLines: 8,
              minLines: 5,
              decoration: const InputDecoration(
                labelText: 'Text',
                hintText: 'Paste anything you want Brutus to remember...',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(sheetCtx, false),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => Navigator.pop(sheetCtx, true),
                  child: const Text('Index'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final title = titleCtrl.text.trim();
    final text = textCtrl.text.trim();
    if (text.isEmpty) return;
    if (!context.mounted) return;
    await _IngestProgress.run(
      context,
      ref,
      label: title.isEmpty ? 'Pasted text' : title,
      action: (notifier, report) async {
        report('Indexing pasted text...');
        return await notifier.ingest(
          title: title.isEmpty ? 'Pasted ${DateTime.now()}' : title,
          text: text,
          source: RagSourceKind.pasted,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Import flow — text/markdown file
// ─────────────────────────────────────────────────────────────────────────────

class _ImportFlow {
  static Future<void> run(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'markdown'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final path = file.path;
    if (path == null) return;
    if (!context.mounted) return;

    String content;
    try {
      content = await File(path).readAsString();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read file: $e')),
      );
      return;
    }
    if (!context.mounted) return;
    if (content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File is empty.')),
      );
      return;
    }

    final fileName = file.name;
    if (!context.mounted) return;
    await _IngestProgress.run(
      context,
      ref,
      label: fileName,
      action: (notifier, report) async {
        report('Indexing $fileName...');
        return await notifier.ingest(
          title: fileName,
          text: content,
          source: RagSourceKind.imported,
          sourceRef: path,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared progress dialog used by all three flows
// ─────────────────────────────────────────────────────────────────────────────

class _IngestProgress {
  static Future<void> run(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required Future<String?> Function(
      OracleNotifier notifier,
      void Function(String) reportLabel,
    ) action,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ProgressDialog(),
    );
    final notifier = ref.read(ragOracleProvider.notifier);
    final err = await action(notifier, (_) {
      // The provider already drives a granular per-batch progress UI via
      // OracleProviderState.ingestProgress; the sheet listens to that.
    });
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (err != null) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $err')));
    } else {
      messenger.showSnackBar(SnackBar(content: Text('Indexed $label')));
    }
  }
}

class _ProgressDialog extends ConsumerWidget {
  const _ProgressDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress =
        ref.watch(ragOracleProvider.select((s) => s.ingestProgress));
    final total = progress?.total ?? 0;
    final done = progress?.done ?? 0;
    final value = total == 0 ? null : done / total;
    return AlertDialog(
      title: Text(progress?.label ?? 'Indexing'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: value),
          const SizedBox(height: 12),
          Text(
            total == 0
                ? 'Embedding...'
                : 'Indexing $done of $total chunks',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            ref.read(ragOracleProvider.notifier).cancelIngest();
            Navigator.of(context, rootNavigator: true).pop();
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
