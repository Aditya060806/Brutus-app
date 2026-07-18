import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:brutus_app/data/tools/weather_api.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class WeatherState {
  final String city;
  final String country;
  final double temperature;
  final String condition;
  final int humidity;
  final double windSpeed;
  final bool isDay;
  final bool isLoading;
  final String? error;

  const WeatherState({
    this.city = 'New Delhi',
    this.country = 'India',
    this.temperature = 0,
    this.condition = 'Clear',
    this.humidity = 0,
    this.windSpeed = 0,
    this.isDay = true,
    this.isLoading = false,
    this.error,
  });

  WeatherState copyWith({
    String? city, String? country, double? temperature,
    String? condition, int? humidity, double? windSpeed,
    bool? isDay, bool? isLoading, String? error,
  }) => WeatherState(
    city: city ?? this.city,
    country: country ?? this.country,
    temperature: temperature ?? this.temperature,
    condition: condition ?? this.condition,
    humidity: humidity ?? this.humidity,
    windSpeed: windSpeed ?? this.windSpeed,
    isDay: isDay ?? this.isDay,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class WeatherNotifier extends StateNotifier<WeatherState> {
  WeatherNotifier() : super(const WeatherState());

  Future<void> fetchWeather(String city) async {
    state = state.copyWith(isLoading: true, error: null);

    final result = await WeatherApi.fetchWeather(city);

    if (result.containsKey('error')) {
      state = state.copyWith(isLoading: false, error: result['error'] as String);
      return;
    }

    state = state.copyWith(
      city: result['city'] as String? ?? city,
      country: result['country'] as String? ?? '',
      temperature: (result['temperature'] as num?)?.toDouble() ?? 0,
      condition: result['condition'] as String? ?? 'Clear',
      humidity: (result['humidity'] as num?)?.toInt() ?? 0,
      windSpeed: (result['windSpeed'] as num?)?.toDouble() ?? 0,
      isDay: result['isDay'] as bool? ?? true,
      isLoading: false,
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final weatherProvider = StateNotifierProvider<WeatherNotifier, WeatherState>(
  (ref) => WeatherNotifier(),
);
