import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:brutus_app/core/theme/app_colors.dart';
import 'package:brutus_app/core/widgets/shared_widgets.dart';
import 'package:brutus_app/providers/weather_provider.dart';

class WeatherScreen extends ConsumerStatefulWidget {
  const WeatherScreen({super.key});
  @override
  ConsumerState<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends ConsumerState<WeatherScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load default city on open
    Future.microtask(() => ref.read(weatherProvider.notifier).fetchWeather('New Delhi'));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  final _hourly = const [
    _HourlyItem('Now', Icons.wb_sunny, true),
    _HourlyItem('2PM', Icons.wb_sunny, false),
    _HourlyItem('4PM', Icons.cloud, false),
    _HourlyItem('6PM', Icons.cloud, false),
    _HourlyItem('8PM', Icons.nights_stay, false),
    _HourlyItem('10PM', Icons.nights_stay, false),
  ];

  @override
  Widget build(BuildContext context) {
    final weather = ref.watch(weatherProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Weather')),
      body: weather.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              child: Column(
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
                      decoration: const InputDecoration(
                        hintText: 'Search city...',
                        prefixIcon: Icon(Iconsax.search_normal_1, size: 18),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      ),
                      onSubmitted: (val) {
                        if (val.trim().isNotEmpty) {
                          ref.read(weatherProvider.notifier).fetchWeather(val.trim());
                        }
                      },
                    ),
                  ).animate().fadeIn(duration: 300.ms),

                  const SizedBox(height: 20),

                  if (weather.error != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(weather.error!, style: const TextStyle(color: AppColors.error)),
                    )
                  else ...[
                    // Main card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF9333EA)],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 30, offset: const Offset(0, 10))],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Iconsax.location, color: Colors.white.withValues(alpha: 0.9), size: 16),
                              const SizedBox(width: 6),
                              Text(
                                '${weather.city}, ${weather.country}',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${weather.temperature.round()}°',
                                    style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w200, height: 1),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    weather.condition,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 18, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                              Icon(
                                weather.isDay ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                                color: Colors.white.withValues(alpha: 0.4),
                                size: 72,
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              _WeatherDetail(icon: Iconsax.drop, label: 'Humidity', value: '${weather.humidity}%'),
                              const SizedBox(width: 24),
                              _WeatherDetail(icon: Iconsax.wind, label: 'Wind', value: '${weather.windSpeed.toStringAsFixed(1)} km/h'),
                              const SizedBox(width: 24),
                              const _WeatherDetail(icon: Iconsax.eye, label: 'Visibility', value: '10 km'),
                            ],
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 500.ms, delay: 100.ms).scale(begin: const Offset(0.95, 0.95), curve: Curves.easeOutBack),

                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Hourly Forecast'),
                    const SizedBox(height: 12),

                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _hourly.length,
                        itemBuilder: (context, index) {
                          final item = _hourly[index];
                          final temp = (weather.temperature + (index - 1) * 0.8).round();
                          return Container(
                            width: 72,
                            margin: EdgeInsets.only(right: index < _hourly.length - 1 ? 10 : 0),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: item.isNow ? AppColors.primary : AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: item.isNow ? null : Border.all(color: AppColors.border, width: 0.5),
                              boxShadow: item.isNow ? AppColors.primaryGlow : AppColors.cardShadow,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(item.time, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: item.isNow ? Colors.white70 : AppColors.textTertiary)),
                                Icon(item.icon, size: 22, color: item.isNow ? Colors.white : AppColors.textSecondary),
                                Text('$temp°', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: item.isNow ? Colors.white : AppColors.textPrimary)),
                              ],
                            ),
                          ).animate(delay: Duration(milliseconds: 100 * index)).fadeIn(duration: 300.ms).slideX(begin: 0.1);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _WeatherDetail extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _WeatherDetail({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 16, color: Colors.white60),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
      ],
    );
  }
}

class _HourlyItem {
  final String time;
  final IconData icon;
  final bool isNow;
  const _HourlyItem(this.time, this.icon, this.isNow);
}
