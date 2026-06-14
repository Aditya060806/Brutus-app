import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:brutus_app/core/constants/api_constants.dart';

/// Weather API tool — direct port of weather-api.ts
/// Uses Open-Meteo (free, no API key required)
class WeatherApi {
  static Future<Map<String, dynamic>> fetchWeather(String city) async {
    try {
      // Geocode city
      final geoRes = await http.get(Uri.parse(
        '${ApiConstants.weatherGeoUrl}?name=${Uri.encodeComponent(city)}&count=1&language=en&format=json',
      ));
      final geoData = jsonDecode(geoRes.body);

      if (geoData['results'] == null || (geoData['results'] as List).isEmpty) {
        throw Exception('Could not find location: $city');
      }

      final location = geoData['results'][0];

      // Fetch weather
      final weatherRes = await http.get(Uri.parse(
        '${ApiConstants.weatherUrl}?latitude=${location['latitude']}&longitude=${location['longitude']}'
        '&current=temperature_2m,relative_humidity_2m,is_day,precipitation,weather_code,wind_speed_10m&timezone=auto',
      ));
      final weatherData = jsonDecode(weatherRes.body);
      final current = weatherData['current'];

      // Map weather code to condition
      final code = current['weather_code'] as int;
      String condition = 'Clear';
      if (code >= 1 && code <= 3) condition = 'Cloudy';
      if (code == 45 || code == 48) condition = 'Haze';
      if (code >= 51 && code <= 67) condition = 'Rain';
      if (code >= 71 && code <= 77) condition = 'Snow';
      if (code >= 95 && code <= 99) condition = 'Thunderstorm';

      return {
        'city': location['name'],
        'country': location['country'],
        'temperature': current['temperature_2m'],
        'humidity': current['relative_humidity_2m'],
        'windSpeed': current['wind_speed_10m'],
        'isDay': current['is_day'] == 1,
        'condition': condition,
      };
    } catch (e) {
      return {'error': 'Failed to get weather: $e'};
    }
  }
}
