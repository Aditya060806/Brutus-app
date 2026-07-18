import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:brutus_app/core/constants/api_constants.dart';

/// Stock API tool — direct port of stock-api.ts
/// Uses Yahoo Finance for real-time stock data
class StockApi {
  static Future<Map<String, dynamic>> fetchStock(String ticker) async {
    try {
      final url = '${ApiConstants.yahooFinanceUrl}/$ticker?range=1d&interval=5m';
      final response = await http.get(Uri.parse(url));
      final data = jsonDecode(response.body);

      if (data['chart']['result'] == null) {
        throw Exception('Invalid ticker: $ticker');
      }

      final result = data['chart']['result'][0];
      final meta = result['meta'];
      final timestamps = result['timestamp'] as List? ?? [];
      final closes = result['indicators']['quote'][0]['close'] as List? ?? [];

      final chartData = <Map<String, dynamic>>[];
      for (int i = 0; i < timestamps.length; i++) {
        if (closes[i] != null) {
          final time = DateTime.fromMillisecondsSinceEpoch(
            (timestamps[i] as num).toInt() * 1000,
          );
          chartData.add({
            'time': '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
            'price': (closes[i] as num).toDouble(),
          });
        }
      }

      final currentPrice = (meta['regularMarketPrice'] as num).toDouble();
      final previousClose = (meta['chartPreviousClose'] as num?)?.toDouble() ?? currentPrice;
      final change = currentPrice - previousClose;
      final percentChange = (change / previousClose) * 100;

      return {
        'symbol': meta['symbol'],
        'currency': meta['currency'],
        'currentPrice': currentPrice,
        'previousClose': previousClose,
        'change': change,
        'percentChange': percentChange,
        'isPositive': change >= 0,
        'chartData': chartData,
      };
    } catch (e) {
      return {'error': 'Failed to fetch stock data for $ticker: $e'};
    }
  }

  static Future<Map<String, dynamic>> compareStocks(String ticker1, String ticker2) async {
    final data1 = await fetchStock(ticker1);
    final data2 = await fetchStock(ticker2);

    if (data1.containsKey('error') || data2.containsKey('error')) {
      return {'error': 'Failed to compare stocks'};
    }

    return {
      'stock1': data1,
      'stock2': data2,
      'isComparison': true,
    };
  }
}
