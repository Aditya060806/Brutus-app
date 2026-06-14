import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class Note {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int colorIndex; // 0=primary, 1=success, 2=warning, 3=research, 4=info

  Note({
    String? id,
    required this.title,
    required this.content,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.colorIndex = 0,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Note copyWith({String? title, String? content, int? colorIndex}) => Note(
    id: id,
    title: title ?? this.title,
    content: content ?? this.content,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    colorIndex: colorIndex ?? this.colorIndex,
  );

  // Hive serialization
  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'content': content,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'colorIndex': colorIndex,
  };

  factory Note.fromMap(Map map) => Note(
    id: map['id'] as String?,
    title: map['title'] as String? ?? '',
    content: map['content'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int? ?? 0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int? ?? 0),
    colorIndex: map['colorIndex'] as int? ?? 0,
  );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class NotesNotifier extends StateNotifier<List<Note>> {
  late Box _box;
  static const _boxName = 'notes';

  NotesNotifier() : super([]) {
    _init();
  }

  Future<void> _init() async {
    _box = Hive.box(_boxName);
    _loadAll();
  }

  void _loadAll() {
    final notes = _box.values
        .map((v) => Note.fromMap(Map<String, dynamic>.from(v as Map)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = notes;
  }

  Future<void> createNote({required String title, required String content, int colorIndex = 0}) async {
    final note = Note(title: title, content: content, colorIndex: colorIndex);
    await _box.put(note.id, note.toMap());
    _loadAll();
  }

  Future<void> updateNote(String id, {String? title, String? content, int? colorIndex}) async {
    final existing = state.firstWhere((n) => n.id == id, orElse: () => throw Exception('Note not found'));
    final updated = existing.copyWith(title: title, content: content, colorIndex: colorIndex);
    await _box.put(id, updated.toMap());
    _loadAll();
  }

  Future<void> deleteNote(String id) async {
    await _box.delete(id);
    _loadAll();
  }

  List<Note> search(String query) {
    if (query.isEmpty) return state;
    final q = query.toLowerCase();
    return state.where((n) =>
      n.title.toLowerCase().contains(q) || n.content.toLowerCase().contains(q)
    ).toList();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final notesProvider = StateNotifierProvider<NotesNotifier, List<Note>>(
  (ref) => NotesNotifier(),
);
