import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:brutus_app/data/services/api_keys.dart';
import 'package:brutus_app/data/services/image_gen_service.dart';
import 'package:brutus_app/data/services/network_guard.dart';

export 'package:brutus_app/data/services/image_gen_service.dart'
    show HfImageModel, ImageGenService, ImageGenException;

class GeneratedImage {
  final String id;
  final String prompt;
  final String? negativePrompt;
  final HfImageModel model;
  final String filePath;
  final DateTime createdAt;

  const GeneratedImage({
    required this.id,
    required this.prompt,
    required this.negativePrompt,
    required this.model,
    required this.filePath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'prompt': prompt,
        'negativePrompt': negativePrompt,
        'model': model.id,
        'filePath': filePath,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory GeneratedImage.fromMap(Map map) {
    final modelId = map['model'] as String?;
    return GeneratedImage(
      id: map['id'] as String? ?? const Uuid().v4(),
      prompt: map['prompt'] as String? ?? '',
      negativePrompt: map['negativePrompt'] as String?,
      model: HfImageModel.values.firstWhere(
        (m) => m.id == modelId,
        orElse: () => HfImageModel.fluxSchnell,
      ),
      filePath: map['filePath'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

class GalleryState {
  final List<GeneratedImage> images;
  final bool isGenerating;
  final String? errorMessage;
  final bool needsKey;
  final bool offline;
  final String draftPrompt;
  final HfImageModel selectedModel;

  const GalleryState({
    this.images = const [],
    this.isGenerating = false,
    this.errorMessage,
    this.needsKey = false,
    this.offline = false,
    this.draftPrompt = '',
    this.selectedModel = HfImageModel.fluxSchnell,
  });

  GalleryState copyWith({
    List<GeneratedImage>? images,
    bool? isGenerating,
    String? errorMessage,
    bool? needsKey,
    bool? offline,
    String? draftPrompt,
    HfImageModel? selectedModel,
    bool clearError = false,
  }) {
    return GalleryState(
      images: images ?? this.images,
      isGenerating: isGenerating ?? this.isGenerating,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      needsKey: needsKey ?? this.needsKey,
      offline: offline ?? this.offline,
      draftPrompt: draftPrompt ?? this.draftPrompt,
      selectedModel: selectedModel ?? this.selectedModel,
    );
  }
}

class GalleryNotifier extends StateNotifier<GalleryState> {
  GalleryNotifier({ImageGenService? service})
      : _service = service ?? ImageGenService(),
        super(const GalleryState()) {
    _load();
  }

  final ImageGenService _service;
  CancelToken? _cancelToken;

  // Hive box `preferences` is reused — generated images live as a list in
  // a dedicated key rather than getting their own box, which keeps the box
  // count manageable.
  static const _boxName = 'preferences';
  static const _key = 'gallery_history';
  static const _maxKept = 60;

  void _log(String msg) => dev.log('[Gallery] $msg', name: 'BrutusAI');

  // ── Persistence ─────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final box = Hive.box(_boxName);
      final raw = (box.get(_key) as List?) ?? const [];
      final loaded = raw
          .map((m) => GeneratedImage.fromMap(Map.from(m as Map)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      // Drop entries whose file is missing (e.g. cache wiped by Android).
      final live = <GeneratedImage>[];
      for (final g in loaded) {
        if (await File(g.filePath).exists()) live.add(g);
      }
      if (live.length != loaded.length) {
        await Hive.box(_boxName).put(
          _key,
          live.map((g) => g.toMap()).toList(),
        );
      }
      state = state.copyWith(images: live);
    } catch (e) {
      _log('history load failed: $e');
    }
  }

  Future<void> _persist(List<GeneratedImage> next) async {
    try {
      await Hive.box(_boxName)
          .put(_key, next.map((g) => g.toMap()).toList());
    } catch (e) {
      _log('history persist failed: $e');
    }
  }

  // ── Generation ──────────────────────────────────────────────────────────

  void setPrompt(String value) {
    state = state.copyWith(draftPrompt: value);
  }

  void selectModel(HfImageModel model) {
    state = state.copyWith(selectedModel: model);
  }

  void cancel() {
    _cancelToken?.cancel('user-cancel');
    _cancelToken = null;
    if (state.isGenerating) {
      state = state.copyWith(isGenerating: false);
    }
  }

  Future<void> generate({String? promptOverride}) async {
    final prompt = (promptOverride ?? state.draftPrompt).trim();
    if (prompt.isEmpty) return;

    cancel();
    final token = CancelToken();
    _cancelToken = token;

    state = state.copyWith(
      isGenerating: true,
      clearError: true,
      needsKey: false,
      offline: false,
    );

    try {
      final key = await ApiKeys.huggingFace();
      if (key == null) {
        state = state.copyWith(
          isGenerating: false,
          needsKey: true,
          errorMessage: 'Add your HuggingFace token in Settings → API Keys.',
        );
        return;
      }

      final bytes = await _service.generate(
        prompt,
        model: state.selectedModel,
        cancelToken: token,
      );
      if (token.isCancelled) return;

      final saved = await _saveBytes(bytes, prompt: prompt);
      final next = <GeneratedImage>[saved, ...state.images]
          .take(_maxKept)
          .toList();
      await _persist(next);

      state = state.copyWith(
        images: next,
        isGenerating: false,
      );
    } on MissingApiKeyException catch (e) {
      state = state.copyWith(
        isGenerating: false,
        needsKey: true,
        errorMessage: e.toString(),
      );
    } on OfflineException catch (e) {
      state = state.copyWith(
        isGenerating: false,
        offline: true,
        errorMessage: e.toString(),
      );
    } on ImageGenException catch (e) {
      state = state.copyWith(
        isGenerating: false,
        errorMessage: e.statusCode == 503
            ? 'Model is loading on HuggingFace — try again in a few seconds.'
            : e.toString(),
      );
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        errorMessage: 'Generation failed: $e',
      );
    }
  }

  Future<GeneratedImage> _saveBytes(
    Uint8List bytes, {
    required String prompt,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/brutus_gallery');
    if (!await folder.exists()) await folder.create(recursive: true);
    final id = const Uuid().v4();
    final file = File('${folder.path}/$id.png');
    await file.writeAsBytes(bytes, flush: true);
    return GeneratedImage(
      id: id,
      prompt: prompt,
      negativePrompt: null,
      model: state.selectedModel,
      filePath: file.path,
      createdAt: DateTime.now(),
    );
  }

  Future<void> deleteImage(String id) async {
    final target = state.images.firstWhere(
      (g) => g.id == id,
      orElse: () => GeneratedImage(
        id: id,
        prompt: '',
        negativePrompt: null,
        model: HfImageModel.fluxSchnell,
        filePath: '',
        createdAt: DateTime.now(),
      ),
    );
    if (target.filePath.isNotEmpty) {
      try {
        await File(target.filePath).delete();
      } catch (_) {}
    }
    final next = state.images.where((g) => g.id != id).toList();
    await _persist(next);
    state = state.copyWith(images: next);
  }

  Future<void> clearAll() async {
    for (final g in state.images) {
      try {
        await File(g.filePath).delete();
      } catch (_) {}
    }
    await Hive.box(_boxName).delete(_key);
    state = state.copyWith(images: const []);
  }

  // ── Voice tool ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> runForTool(String prompt) async {
    final clean = prompt.trim();
    if (clean.isEmpty) {
      return {'error': 'generate_image needs a non-empty `prompt`.'};
    }
    state = state.copyWith(draftPrompt: clean);
    await generate(promptOverride: clean);
    if (state.errorMessage != null) {
      return {'error': state.errorMessage};
    }
    final saved = state.images.first;
    return {
      'success': true,
      'prompt': saved.prompt,
      'model': saved.model.label,
      'message':
          'Generated. Open Tools → Gallery to view it on the device.',
    };
  }

  @override
  void dispose() {
    _cancelToken?.cancel('dispose');
    super.dispose();
  }
}

final galleryProvider =
    StateNotifierProvider<GalleryNotifier, GalleryState>(
  (ref) {
    final n = GalleryNotifier();
    ref.onDispose(n.dispose);
    return n;
  },
);
