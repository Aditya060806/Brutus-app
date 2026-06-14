import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:brutus_app/core/constants/api_constants.dart';

/// Brutus Mobile — HTTP client with token refresh interceptor
/// Mirrors the Electron AxiosInstance.ts logic
class DioClient {
  static DioClient? _instance;
  late final Dio dio;
  final _storage = const FlutterSecureStorage();
  bool _isRefreshing = false;

  DioClient._() {
    dio = Dio(BaseOptions(
      baseUrl: ApiConstants.backendBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    // Request interceptor — attach access token
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: ApiConstants.accessToken);
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 && !_isRefreshing) {
          _isRefreshing = true;
          try {
            final refreshToken = await _storage.read(key: ApiConstants.refreshToken);
            if (refreshToken == null || refreshToken.isEmpty) {
              _isRefreshing = false;
              return handler.reject(error);
            }

            final refreshDio = Dio(BaseOptions(baseUrl: ApiConstants.backendBaseUrl));
            final res = await refreshDio.post(
              ApiConstants.authRefresh,
              data: {'refreshToken': refreshToken},
            );

            final newAccessToken = res.data['accessToken'] as String?;
            final newRefreshToken = res.data['refreshToken'] as String?;

            if (newAccessToken != null && newAccessToken.isNotEmpty) {
              await _storage.write(key: ApiConstants.accessToken, value: newAccessToken);
              if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
                await _storage.write(key: ApiConstants.refreshToken, value: newRefreshToken);
              }

              // Retry original request
              final opts = error.requestOptions;
              opts.headers['Authorization'] = 'Bearer $newAccessToken';
              final response = await dio.fetch(opts);
              _isRefreshing = false;
              return handler.resolve(response);
            }
          } catch (_) {
            // Clear tokens on refresh failure
            await _storage.delete(key: ApiConstants.accessToken);
            await _storage.delete(key: ApiConstants.refreshToken);
          }
          _isRefreshing = false;
        }
        handler.next(error);
      },
    ));
  }

  static DioClient get instance {
    _instance ??= DioClient._();
    return _instance!;
  }
}
