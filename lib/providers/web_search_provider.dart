import 'dart:async';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:brutus_app/core/constants/api_constants.dart';
import 'package:brutus_app/data/services/api_keys.dart';
import 'package:brutus_app/data/services/network_guard.dart';
import 'package:brutus_app/data/tools/tavily_client.dart';

/// Re-export so screens can import a single file.
export 'package:brutus_app/data/tools/tavily_client.dart'
    show TavilyResult, TavilySource, TavilyDepth, TavilyException;

class WebSearchState {
  final String query;
  final bool isLoading;
  final TavilyResult? result;
  final String? error;
  final bool needsKey;
  final bool offline;
  final List<String> recent;
  final bool includeRawContent;

  const WebSearchState({
    this.query = '',
    this.isLoading = false,
    this.result,
    this.error,
    this.needsKey = false,
    this.offline = false,
    this.recent = const [],
    this.includeRawContent = false,
  });

  WebSearchState copyWith({
    String? query,
    bool? isLoading,
    TavilyResult? result,
    String? error,
    bool? needsKey,
    bool? offline,
    List<String>? recent,
    bool? includeRawContent,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return WebSearchState(
      query: query ?? this.query,
      isLoading: isLoading ?? this.isLoading,
      result: clearResult ? null : (result ?? this.result),
      error: clearError ? null : (error ?? this.error),
      needsKey: needsKey ?? this.needsKey,
      offline: offline ?? this.offline,
      recent: recent ?? this.recent,
      includeRawContent: includeRawContent ?? this.includeRawContent,
    );
  }
}

class WebSearchNotifier extends StateNotifier<WebSearchState> {
  WebSearchNotifier({TavilyClient? client})
      : _client = client ?? TavilyClient(),
        super(const WebSearchState()) {
    _loadRecent();
  }

  final TavilyClient _client;
  CancelToken? _cancelToken;

  static const _prefsBoxName = ApiConstants.boxPreferences;
  static const _recentKey = 'web_search_recent';
  static const _maxRecent = 10;

  void _log(String msg) => dev.log('[WebSearch] $msg', name: 'BrutusAI');

  void _loadRecent() {
    try {
      final box = Hive.box(_prefsBoxName);
      final raw = (box.get(_recentKey) as List?)?.cast<String>() ?? const [];
      state = state.copyWith(recent: raw);
    } catch (e) {
      _log('recent load failed: $e');
    }
  }

  void _persistRecent(List<String> recent) {
    try {
      Hive.box(_prefsBoxName).put(_recentKey, recent);
    } catch (e) {
      _log('recent persist failed: $e');
    }
  }

  void setIncludeRaw(bool value) {
    state = state.copyWith(includeRawContent: value);
  }

  /// Cancel any in-flight search.
  void cancel() {
    _cancelToken?.cancel('user-cancel');
    _cancelToken = null;
    if (state.isLoading) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Run a search. Cancels any prior in-flight call automatically.
  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    cancel();
    final token = CancelToken();
    _cancelToken = token;

    state = state.copyWith(
      query: trimmed,
      isLoading: true,
      clearError: true,
      clearResult: true,
      needsKey: false,
      offline: false,
    );

    try {
      // Pre-check the key so we can surface a helpful "needs key" state
      // instead of the generic error chip.
      final key = await ApiKeys.tavily();
      if (key == null) {
        state = state.copyWith(
          isLoading: false,
          needsKey: true,
          error: 'Add your Tavily key in Settings → API Keys.',
        );
        return;
      }

      final result = await _client.search(
        trimmed,
        includeAnswer: true,
        includeRawContent: state.includeRawContent,
        maxResults: 5,
        cancelToken: token,
      );
      if (token.isCancelled) return;

      // Push to recent — newest first, dedupe, cap.
      final newRecent = <String>[
        trimmed,
        ...state.recent.where((q) => q != trimmed),
      ].take(_maxRecent).toList();
      _persistRecent(newRecent);

      state = state.copyWith(
        isLoading: false,
        result: result,
        recent: newRecent,
      );
    } on MissingApiKeyException catch (e) {
      state = state.copyWith(
        isLoading: false,
        needsKey: true,
        error: e.toString(),
      );
    } on OfflineException catch (e) {
      state = state.copyWith(
        isLoading: false,
        offline: true,
        error: e.toString(),
      );
    } on TavilyException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.statusCode == 429
            ? 'Rate limit reached — try again in a moment.'
            : e.toString(),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Search failed: $e',
      );
    }
  }

  /// Pull-to-refresh: re-run the last query.
  Future<void> refresh() async {
    final last = state.query.trim();
    if (last.isEmpty) return;
    await search(last);
  }

  void clearRecent() {
    _persistRecent(const []);
    state = state.copyWith(recent: const []);
  }

  @override
  void dispose() {
    _cancelToken?.cancel('dispose');
    super.dispose();
  }
}

final webSearchProvider =
    StateNotifierProvider<WebSearchNotifier, WebSearchState>(
  (ref) {
    final n = WebSearchNotifier();
    ref.onDispose(n.dispose);
    return n;
  },
);
