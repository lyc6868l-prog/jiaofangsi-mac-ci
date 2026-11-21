import 'dart:async';
import 'dart:convert';
import 'dart:io';

class TipPaymentOrder {
  const TipPaymentOrder({
    required this.orderId,
    required this.amount,
    required this.paymentUrl,
    this.title = '',
  });

  final String orderId;
  final double amount;
  final String paymentUrl;
  final String title;

  factory TipPaymentOrder.fromJson(Map<String, Object?> json) {
    final Object? data = json['data'];
    final Map<String, Object?> source = data is Map<Object?, Object?>
        ? data.cast<String, Object?>()
        : json;
    return TipPaymentOrder(
      orderId: (source['order_id'] ?? '').toString(),
      amount: (source['amount'] as num?)?.toDouble() ?? 0,
      paymentUrl: (source['payment_url'] ?? '').toString(),
      title: (source['plan_title'] ?? '').toString(),
    );
  }
}

class TipPaymentException implements Exception {
  const TipPaymentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TipPaymentService {
  TipPaymentService({this.baseUrl = 'https://auth.jiaofangsi.top'});

  final String baseUrl;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  Future<TipPaymentOrder> createOrder({
    required String token,
    required String authMode,
    required String tierId,
    required int quantity,
  }) async {
    final bool unified = authMode == 'unified';
    final Uri uri = Uri.parse(
      unified
          ? '$baseUrl/wechat-auth/v1/tip/orders'
          : '$baseUrl/order/create/tip',
    );
    try {
      final HttpClientRequest request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.write(
        jsonEncode(<String, Object?>{'tier_id': tierId, 'quantity': quantity}),
      );
      final HttpClientResponse response = await request.close();
      final String text = await response.transform(utf8.decoder).join();
      final Object? decoded = text.trim().isEmpty ? null : jsonDecode(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = '创建支付订单失败，请稍后重试';
        if (decoded is Map<Object?, Object?>) {
          final Object? detail = decoded['detail'];
          if (detail is Map<Object?, Object?>) {
            message = (detail['message'] ?? message).toString();
          } else if (detail != null) {
            message = detail.toString();
          } else if (decoded['message'] != null) {
            message = decoded['message'].toString();
          }
        }
        throw TipPaymentException(message);
      }
      if (decoded is! Map<Object?, Object?>) {
        throw const TipPaymentException('支付服务返回数据异常');
      }
      final TipPaymentOrder order = TipPaymentOrder.fromJson(
        decoded.cast<String, Object?>(),
      );
      if (order.paymentUrl.isEmpty) {
        throw const TipPaymentException('未获取到支付链接');
      }
      return order;
    } on TipPaymentException {
      rethrow;
    } on SocketException {
      throw const TipPaymentException('网络连接失败，请检查网络后重试');
    } on TimeoutException {
      throw const TipPaymentException('支付请求超时，请稍后重试');
    } catch (_) {
      throw const TipPaymentException('支付服务暂时不可用');
    }
  }

  Future<List<Map<String, Object?>>> leaderboard({
    required String token,
    required String authMode,
  }) async {
    final bool unified = authMode == 'unified';
    final Uri uri = Uri.parse(
      unified
          ? '$baseUrl/wechat-auth/v1/tip/leaderboard'
          : '$baseUrl/tip/leaderboard',
    );
    try {
      final HttpClientRequest request = await _client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final HttpClientResponse response = await request.close();
      final String text = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return <Map<String, Object?>>[];
      }
      final Object? decoded = text.trim().isEmpty ? null : jsonDecode(text);
      if (decoded is! Map<Object?, Object?>) {
        return <Map<String, Object?>>[];
      }
      final Object? raw = decoded['leaderboard'];
      if (raw is! List<Object?>) return <Map<String, Object?>>[];
      return raw
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> item) => item.cast<String, Object?>())
          .toList(growable: false);
    } catch (_) {
      return <Map<String, Object?>>[];
    }
  }

  void close() => _client.close(force: true);
}
