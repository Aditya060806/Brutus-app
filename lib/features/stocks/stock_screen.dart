import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/shared_widgets.dart';
import 'package:brutus_app/providers/stock_provider.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});
  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  final _searchController = TextEditingController();
  int _selectedRange = 0;
  final _ranges = ['1D', '1W', '1M', '3M', '1Y'];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(stockProvider.notifier).fetchStock('AAPL'));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stock = ref.watch(stockProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Stocks')),
      body: stock.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: TextField(
                      controller: _searchController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        hintText: 'Search ticker (e.g. AAPL)...',
                        prefixIcon: Icon(Iconsax.search_normal_1, size: 18),
                        border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      ),
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) {
                          ref.read(stockProvider.notifier).fetchStock(val.trim());
                        }
                      },
                    ),
                  ).animate().fadeIn(duration: 300.ms),

                  const SizedBox(height: 20),

                  if (stock.error != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.errorLight, borderRadius: BorderRadius.circular(14)),
                      child: Text(stock.error!, style: const TextStyle(color: AppColors.error)),
                    )
                  else ...[
                    // Stock card
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(stock.ticker, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                  Text(stock.companyName, style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('\$${stock.currentPrice.toStringAsFixed(2)}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (stock.isPositive ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${stock.isPositive ? '+' : ''}${stock.changePercent.toStringAsFixed(2)}%',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: stock.isPositive ? AppColors.success : AppColors.error),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Chart
                          if (stock.chartData.isNotEmpty)
                            SizedBox(
                              height: 180,
                              child: LineChart(LineChartData(
                                gridData: const FlGridData(show: false),
                                titlesData: const FlTitlesData(show: false),
                                borderData: FlBorderData(show: false),
                                lineTouchData: LineTouchData(
                                  touchTooltipData: LineTouchTooltipData(
                                    getTooltipColor: (_) => AppColors.textPrimary,
                                    getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                                      '\$${s.y.toStringAsFixed(2)}',
                                      const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                                    )).toList(),
                                  ),
                                ),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: stock.chartData,
                                    isCurved: true,
                                    curveSmoothness: 0.3,
                                    color: stock.isPositive ? AppColors.success : AppColors.error,
                                    barWidth: 2.5,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                        colors: [
                                          (stock.isPositive ? AppColors.success : AppColors.error).withValues(alpha: 0.15),
                                          (stock.isPositive ? AppColors.success : AppColors.error).withValues(alpha: 0.0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )),
                            )
                          else
                            Container(
                              height: 100,
                              alignment: Alignment.center,
                              child: const Text('No chart data available', style: TextStyle(color: AppColors.textTertiary)),
                            ),

                          const SizedBox(height: 16),
                          // Range selector
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: _ranges.asMap().entries.map((e) {
                              final isActive = e.key == _selectedRange;
                              return GestureDetector(
                                onTap: () => setState(() => _selectedRange = e.key),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isActive ? AppColors.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(e.value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isActive ? Colors.white : AppColors.textTertiary)),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 500.ms, delay: 100.ms).slideY(begin: 0.03),

                    const SizedBox(height: 20),
                    const SectionHeader(title: 'Key Statistics'),
                    const SizedBox(height: 12),
                    Row(children: stock.stats.entries.map((e) =>
                      Expanded(child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GlassCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.key, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                              const SizedBox(height: 4),
                              Text(e.value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            ],
                          ),
                        ),
                      )),
                    ).toList()).animate().fadeIn(duration: 400.ms, delay: 300.ms),
                  ],
                ],
              ),
            ),
    );
  }
}
