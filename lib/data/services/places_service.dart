import 'dart:developer' as dev;

import 'package:dio/dio.dart';

import 'package:brutus_app/data/services/network_guard.dart';

/// One geocoding hit. Coordinates returned by Nominatim's `/search`.
class PlaceHit {
  final String displayName;
  final double latitude;
  final double longitude;
  final String? type;

  const PlaceHit({
    required this.displayName,
    required this.latitude,
    required this.longitude,
    this.type,
  });
}

class PlacesException implements Exception {
  final int? statusCode;
  final String message;
  const PlacesException(this.statusCode, this.message);
  @override
  String toString() =>
      statusCode == null ? message : 'Places error $statusCode: $message';
}

/// Brutus Mobile — Free geocoding via OpenStreetMap Nominatim.
///
/// No API key required. We send a polite User-Agent string per Nominatim's
/// usage policy. Suitable for ≤1 query/sec — fine for a personal app.
class PlacesService {
  PlacesService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                // Nominatim requires a meaningful UA so they can contact us
                // if our usage gets out of hand.
                'User-Agent':
                    'BrutusApp/1.0 (mobile · personal AI assistant)',
                'Accept-Language': 'en',
              },
            ));

  final Dio _dio;

  void _log(String msg) => dev.log('[Places] $msg', name: 'BrutusAI');

  /// Forward-geocode a free-text query (e.g. "Eiffel Tower"). Returns at
  /// most [maxResults] hits, ranked by Nominatim's importance score.
  Future<List<PlaceHit>> search(
    String query, {
    int maxResults = 5,
    CancelToken? cancelToken,
  }) async {
    final clean = query.trim();
    if (clean.isEmpty) return const [];
    await NetworkGuard.ensureOnline();

    _log('search "$clean"');

    try {
      final res = await _dio.get<List<dynamic>>(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': clean,
          'format': 'json',
          'limit': '$maxResults',
          'addressdetails': '0',
        },
        cancelToken: cancelToken,
      );
      final list = res.data ?? const [];
      return list.map((raw) {
        final m = raw as Map;
        return PlaceHit(
          displayName: m['display_name']?.toString() ?? '',
          latitude: double.tryParse(m['lat']?.toString() ?? '') ?? 0.0,
          longitude: double.tryParse(m['lon']?.toString() ?? '') ?? 0.0,
          type: m['type']?.toString(),
        );
      }).toList();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return const [];
      }
      throw PlacesException(e.response?.statusCode, e.message ?? 'Network error');
    }
  }

  /// Reverse-geocode lat/lng to a display name.
  Future<String?> reverse(double lat, double lng,
      {CancelToken? cancelToken}) async {
    await NetworkGuard.ensureOnline();
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': '$lat',
          'lon': '$lng',
          'format': 'json',
          'zoom': '14',
        },
        cancelToken: cancelToken,
      );
      return res.data?['display_name']?.toString();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return null;
      _log('reverse failed: ${e.message}');
      return null;
    }
  }
}
