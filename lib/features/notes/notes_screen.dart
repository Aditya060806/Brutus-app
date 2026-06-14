import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/providers/notes_provider.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});
  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String _searchQuery = '';

  static const _noteColors = [
    AppColors.primary, AppColors.success, AppColors.warning,
    AppColors.research, AppColors.info,
  ];

  @override
  Widget build(BuildContext context) {
    final allNotes = ref.watch(notesProvider);
    final notes = _searchQuery.isEmpty
        ? allNotes
        : ref.read(notesProvider.notifier).search(_searchQuery);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(icon: const Icon(Iconsax.search_normal_1), onPressed: _showSearchBar),
        ],
      ),
      body: notes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Iconsax.note, size: 48, color: AppColors.textTertiary),
                  const SizedBox(height: 16),
                  Text(_searchQuery.isEmpty ? 'No notes yet' : 'No results', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Tap + to create your first note', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary)),
                ],
              ),
            )
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                final color = _noteColors[note.colorIndex % _noteColors.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Dismissible(
                    key: Key(note.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Iconsax.trash, color: AppColors.error),
                    ),
                    onDismissed: (_) => ref.read(notesProvider.notifier).deleteNote(note.id),
                    child: Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showNoteEditor(context, existing: note),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border, width: 0.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(width: 4, height: 20, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(note.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                                  Text(_relativeDate(note.updatedAt), style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                                ],
                              ),
                              if (note.content.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.only(left: 14),
                                  child: Text(note.content, style: const TextStyle(fontSize: 13, color: AppColors.textTertiary, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ).animate(delay: Duration(milliseconds: 60 * index)).fadeIn(duration: 300.ms).slideX(begin: 0.03);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNoteEditor(context),
        child: const Icon(Iconsax.add),
      ),
    );
  }

  void _showSearchBar() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Notes'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search...'),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
        actions: [
          TextButton(
            onPressed: () { setState(() => _searchQuery = ''); Navigator.pop(context); },
            child: const Text('Clear'),
          ),
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }

  void _showNoteEditor(BuildContext context, {Note? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final contentCtrl = TextEditingController(text: existing?.content ?? '');
    int colorIndex = existing?.colorIndex ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              // Title bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(existing == null ? 'New Note' : 'Edit Note', style: Theme.of(context).textTheme.titleLarge),
                    ),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) return;
                        if (existing != null) {
                          ref.read(notesProvider.notifier).updateNote(
                            existing.id, title: title, content: contentCtrl.text.trim(), colorIndex: colorIndex,
                          );
                        } else {
                          ref.read(notesProvider.notifier).createNote(
                            title: title, content: contentCtrl.text.trim(), colorIndex: colorIndex,
                          );
                        }
                        Navigator.pop(context);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
              // Color picker
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: List.generate(5, (i) {
                    final color = [AppColors.primary, AppColors.success, AppColors.warning, AppColors.research, AppColors.info][i];
                    return GestureDetector(
                      onTap: () => setModalState(() => colorIndex = i),
                      child: Container(
                        width: 28, height: 28,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: colorIndex == i ? Border.all(color: AppColors.textPrimary, width: 2) : null,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              // Fields
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
                  child: Column(
                    children: [
                      TextField(
                        controller: titleCtrl,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        decoration: const InputDecoration(hintText: 'Title', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
                      ),
                      Expanded(
                        child: TextField(
                          controller: contentCtrl,
                          maxLines: null,
                          expands: true,
                          style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, height: 1.6),
                          decoration: const InputDecoration(hintText: 'Start writing...', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}';
  }
}
