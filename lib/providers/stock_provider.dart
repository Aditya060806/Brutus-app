import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:brutus_app/data/tools/stock_api.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class StockState {
  final String ticker;
  final String companyName;
  final double currentPrice;
  final double changePercent;
  final bool isPositive;
  final List<FlSpot> chartData;
  final Map<String, String> stats;
  final bool isLoading;
  final String? error;

  const StockState({
    this.ticker = 'AAPL',
    this.companyName = 'Apple Inc.',
    this.currentPrice = 0,
    this.changePercent = 0,
    this.isPositive = true,
    this.chartData = const [],
    this.stats = const {},
    this.isLoading = false,
    this.error,
  });

  StockState copyWith({
    String? ticker, String? companyName, double? currentPrice,
    double? changePercent, bool? isPositive, List<FlSpot>? chartData,
    Map<String, String>? stats, bool? isLoading, String? error,
  }) => StockState(
    ticker: ticker ?? this.ticker,
    companyName: companyName ?? this.companyName,
    currentPrice: currentPrice ?? this.currentPrice,
    changePercent: changePercent ?? this.changePercent,
    isPositive: isPositive ?? this.isPositive,
    chartData: chartData ?? this.chartData,
    stats: stats ?? this.stats,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class StockNotifier extends StateNotifier<StockState> {
  StockNotifier() : super(const StockState());

  Future<void> fetchStock(String ticker) async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await StockApi.fetchStock(ticker.toUpperCase());

    if (result.containsKey('error')) {
      state = state.copyWith(isLoading: false, error: result['error'] as String);
      return;
    }

    // Build chart data from API result
    final rawChart = (result['chartData'] as List<dynamic>?) ?? [];
    final spots = rawChart.asMap().entries.map((e) {
      final price = (e.value as Map)['price'] as double? ?? 0;
      return FlSpot(e.key.toDouble(), price);
    }).toList();

    final price = (result['currentPrice'] as num?)?.toDouble() ?? 0;
    final change = (result['percentChange'] as num?)?.toDouble() ?? 0;

    state = state.copyWith(
      ticker: result['symbol'] as String? ?? ticker,
      currentPrice: price,
      changePercent: change,
      isPositive: result['isPositive'] as bool? ?? true,
      chartData: spots,
      stats: {
        'Open': '\$${(result['previousClose'] as num?)?.toStringAsFixed(2) ?? '-'}',
        'Change': '${change.toStringAsFixed(2)}%',
        'Currency': result['currency'] as String? ?? 'USD',
      },
      isLoading: false,
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final stockProvider = StateNotifierProvider<StockNotifier, StockState>(
  (ref) => StockNotifier(),
);
