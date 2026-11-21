import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Data contracts for the optional "打赏作者" feature.
///
/// The backend endpoints are intentionally kept in one place so they can be
/// implemented without touching the panel UI:
///   GET  /v1/tip/catalog
///   GET  /v1/tip/donors
///   POST /v1/tip/orders
class TipTier {
  const TipTier({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.unitPrice,
    required this.rank,
    required this.perk,
    required this.quote,
    required this.icon,
    this.fullWidth = false,
    this.dreamCar = false,
  });

  String get assetPath => 'assets/user_center/tier_$id.jpg';

  final String id;
  final String title;
  final String subtitle;
  final double unitPrice;
  final String rank;
  final String perk;
  final String quote;
  final String icon;
  final bool fullWidth;
  final bool dreamCar;

  String get priceLabel {
    if (unitPrice >= 10000 && unitPrice % 10000 == 0) {
      return '¥${(unitPrice / 10000).toStringAsFixed(0)}w';
    }
    return '¥${_trimNumber(unitPrice)}';
  }

  static String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  static const List<TipTier> defaults = <TipTier>[
    TipTier(
      id: 'cola',
      title: '来瓶可乐',
      subtitle: '汽水火箭 · 提神升空',
      unitPrice: 3,
      rank: '汽水补给员',
      perk: '功德芳名录留名 + 佩戴「汽水补给员」封号',
      quote: '“一口冰阔落，代码少写十个 Bug。”',
      icon: '🥤',
    ),
    TipTier(
      id: 'drumstick',
      title: '来个鸡腿',
      subtitle: '圣光鸡腿 · 深夜加餐',
      unitPrice: 9,
      rank: '深夜加餐官',
      perk: '芳名录留名 + 佩戴「深夜加餐官」封号与题词',
      quote: '“高悬星轨的烤鸡腿，今晚加钟修体验！”',
      icon: '🍗',
    ),
    TipTier(
      id: 'langzi',
      title: '来包郎子',
      subtitle: '云端飞艇 · 调音口粮',
      unitPrice: 30,
      rank: '云端护法',
      perk: '芳名录红星标记 + 佩戴「云端护法」封号 + 建议优先看',
      quote: '“驾云而来的口粮，混音与发版两不误。”',
      icon: '☁️',
    ),
    TipTier(
      id: 'huazi',
      title: '来包华子',
      subtitle: '宫阙特供 · 排期插队',
      unitPrice: 60,
      rank: '宫阙红星干事',
      perk: '芳名录靠前席位 + 佩戴「宫阙红星干事」封号 + 需求插队评估',
      quote: '“华子已供上殿顶，您的需求即刻提至第一位！”',
      icon: '🚬',
    ),
    TipTier(
      id: 'benz_shard',
      title: '奔驰碎片也行',
      subtitle: '退而求其次 · 先凑车标与一颗螺母',
      unitPrice: 100,
      rank: '造车联合创始人',
      perk: '拼车进度条 +1 片 + 佩戴「造车联合创始人」封号 + 电子功德状',
      quote: '“知道上面那辆没人送，先攒个三叉星标和螺母，慢慢拼！”',
      icon: '🧩',
      fullWidth: true,
    ),
    TipTier(
      id: 'benz_full',
      title: '来辆奔驰',
      subtitle: '天上浮空幻影 · 万一真有大佬呢',
      unitPrice: 300000,
      rank: '教坊司终身名誉厂长',
      perk: '全站拼车瞬间 100% + 启动页终身鸣谢 + 1对1功能定制',
      quote: '“纯属白日做梦……但万一您真点了，厂长位置这就腾出来！”',
      icon: '🚗',
      fullWidth: true,
      dreamCar: true,
    ),
  ];
}

class TipProgress {
  const TipProgress({required this.raised, required this.goal});

  final double raised;
  final double goal;
}

class TipDonor {
  const TipDonor({
    required this.name,
    required this.gift,
    required this.amount,
    required this.rank,
    required this.wish,
  });

  final String name;
  final String gift;
  final String amount;
  final String rank;
  final String wish;

  factory TipDonor.fromJson(Map<String, Object?> json) => TipDonor(
    name: (json['name'] ?? '匿名乐工').toString(),
    gift: (json['gift'] ?? '').toString(),
    amount: (json['amount'] ?? '').toString(),
    rank: (json['rank'] ?? '').toString(),
    wish: (json['wish'] ?? '').toString(),
  );
}

class TipOrder {
  const TipOrder({
    required this.orderId,
    required this.amount,
    this.paymentUrl,
    this.qrCodeUrl,
    this.certificateId,
    this.status = 'pending',
    this.rank,
  });

  final String orderId;
  final double amount;
  final String? paymentUrl;
  final String? qrCodeUrl;
  final String? certificateId;
  final String status;
  final String? rank;

  factory TipOrder.fromJson(Map<String, Object?> json) => TipOrder(
    orderId: (json['order_id'] ?? '').toString(),
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    paymentUrl: _text(json['payment_url']),
    qrCodeUrl: _text(json['qr_code_url'] ?? json['qr_url']),
    certificateId: _text(json['certificate_id']),
    status: (json['status'] ?? 'pending').toString(),
    rank: _text(json['rank']),
  );

  static String? _text(Object? value) {
    final String text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }
}

class TipApiException implements Exception {
  const TipApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TipAuthorService {
  TipAuthorService({this.baseUrl = 'https://auth.jiaofangsi.top/wechat-auth'});

  final String baseUrl;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
  }) async {
    try {
      final HttpClientRequest request = await _client.openUrl(
        method,
        Uri.parse('$baseUrl$path'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) request.write(jsonEncode(body));
      final HttpClientResponse response = await request.close();
      final String text = await response.transform(utf8.decoder).join();
      final Object? decoded = text.trim().isEmpty ? null : jsonDecode(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = '打赏服务暂时不可用';
        if (decoded is Map<Object?, Object?>) {
          final Object? detail = decoded['detail'];
          if (detail is Map<Object?, Object?>) {
            message = (detail['message'] ?? message).toString();
          } else if (decoded['message'] != null) {
            message = decoded['message'].toString();
          }
        }
        throw TipApiException(message);
      }
      return decoded is Map<Object?, Object?>
          ? decoded.cast<String, Object?>()
          : <String, Object?>{};
    } on TipApiException {
      rethrow;
    } on SocketException {
      throw const TipApiException('网络连接失败，请稍后重试');
    } on TimeoutException {
      throw const TipApiException('网络请求超时，请稍后重试');
    } catch (_) {
      throw const TipApiException('打赏服务请求失败');
    }
  }

  Future<TipProgress> progress({String? token}) async {
    final Map<String, Object?> json = await _request(
      'GET',
      '/v1/tip/progress',
      token: token,
    );
    return TipProgress(
      raised: (json['raised'] as num?)?.toDouble() ?? 0,
      goal: (json['goal'] as num?)?.toDouble() ?? 300000,
    );
  }

  Future<List<TipDonor>> donors({String? token}) async {
    final Map<String, Object?> json = await _request(
      'GET',
      '/v1/tip/donors',
      token: token,
    );
    final List<Object?> raw =
        json['donors'] as List<Object?>? ?? const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> item) => TipDonor.fromJson(item.cast()))
        .toList(growable: false);
  }

  Future<TipOrder> createOrder({
    required String token,
    required String tierId,
    required int quantity,
    required String wish,
    required String payChannel,
  }) async {
    final Map<String, Object?> json = await _request(
      'POST',
      '/v1/tip/orders',
      token: token,
      body: <String, Object?>{
        'tier_id': tierId,
        'quantity': quantity,
        'wish': wish,
        'pay_channel': payChannel,
      },
    );
    return TipOrder.fromJson(json);
  }

  void close() => _client.close(force: true);
}

