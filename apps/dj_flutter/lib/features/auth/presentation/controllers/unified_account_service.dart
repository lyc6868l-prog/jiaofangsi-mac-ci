import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/auth_models.dart';

class UnifiedApiException implements Exception {
  UnifiedApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class UnifiedChallenge {
  const UnifiedChallenge({
    required this.challengeId,
    required this.pollToken,
    required this.qrTicket,
    this.expiresAt,
  });

  final String challengeId;
  final String pollToken;
  final String qrTicket;
  final DateTime? expiresAt;

  String get qrImageUrl =>
      'https://mp.weixin.qq.com/cgi-bin/showqrcode?ticket=${Uri.encodeComponent(qrTicket)}';

  factory UnifiedChallenge.fromJson(Map<String, Object?> json) {
    return UnifiedChallenge(
      challengeId: (json['challenge_id'] ?? '').toString(),
      pollToken: (json['poll_token'] ?? '').toString(),
      qrTicket: (json['qr_ticket'] ?? '').toString(),
      expiresAt: _date(json['expires_at']),
    );
  }
}

class UnifiedSession {
  const UnifiedSession({
    required this.accessToken,
    required this.refreshToken,
    required this.accountId,
    required this.displayName,
    required this.avatarUrl,
    this.accessExpiresAt,
    this.refreshExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String accountId;
  final String displayName;
  final String avatarUrl;
  final DateTime? accessExpiresAt;
  final DateTime? refreshExpiresAt;

  factory UnifiedSession.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> user =
        (json['user'] as Map<Object?, Object?>? ?? const {})
            .cast<String, Object?>();
    return UnifiedSession(
      accessToken: (json['access_token'] ?? '').toString(),
      refreshToken: (json['refresh_token'] ?? '').toString(),
      accountId: (json['account_id'] ?? '').toString(),
      displayName: (user['nickname'] ?? json['account_id'] ?? '微信用户')
          .toString(),
      avatarUrl: (user['avatar_url'] ?? '').toString(),
      accessExpiresAt: _date(json['access_expires_at']),
      refreshExpiresAt: _date(json['refresh_expires_at']),
    );
  }
}

class UnifiedProfile {
  const UnifiedProfile({
    this.accountId,
    this.stageName,
    this.avatarType,
    this.avatarUrl,
    this.boundEmail,
  });

  final String? accountId;
  final String? stageName;
  final String? avatarType;
  final String? avatarUrl;
  final String? boundEmail;

  factory UnifiedProfile.fromJson(Map<String, Object?> json) {
    return UnifiedProfile(
      accountId: _text(json['account_id']),
      stageName: _text(json['stage_name']),
      avatarType: _text(json['avatar_type']),
      avatarUrl: _text(json['avatar_url']),
      boundEmail: _text(json['bound_email']),
    );
  }
}

DateTime? _date(Object? value) {
  final String? text = _text(value);
  return text == null ? null : DateTime.tryParse(text)?.toLocal();
}

String? _text(Object? value) {
  final String text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

class UnifiedAccountService {
  UnifiedAccountService({
    this.baseUrl = 'https://auth.jiaofangsi.top/wechat-auth',
  });

  final String baseUrl;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? bearer,
    Map<String, String>? headers,
  }) async {
    HttpClientRequest? request;
    try {
      request = await _client.openUrl(method, _uri(path));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (bearer != null && bearer.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      if (headers != null) {
        headers.forEach((String key, String value) {
          request!.headers.set(key, value);
        });
      }
      if (body != null || method == 'POST') {
        request.write(jsonEncode(body));
      }
      final HttpClientResponse response = await request.close();
      final String text = await response.transform(utf8.decoder).join();
      final Object? decoded = text.trim().isEmpty ? null : jsonDecode(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UnifiedApiException(
          _errorMessage(decoded, response.statusCode),
          statusCode: response.statusCode,
        );
      }
      if (decoded is Map<Object?, Object?>) {
        return decoded.cast<String, Object?>();
      }
      return <String, Object?>{};
    } on UnifiedApiException {
      rethrow;
    } on SocketException {
      throw UnifiedApiException('网络连接失败，请检查网络后重试。');
    } on TimeoutException {
      throw UnifiedApiException('网络请求超时，请稍后重试。');
    } catch (error) {
      throw UnifiedApiException('微信登录服务请求失败：$error');
    }
  }

  String _errorMessage(Object? decoded, int statusCode) {
    if (decoded is Map<Object?, Object?>) {
      final Object? detail = decoded['detail'];
      if (detail is Map<Object?, Object?>) {
        final String? message = _text(detail['message']);
        if (message != null) return message;
      }
      final String? detailText = _text(detail);
      if (detailText != null) return detailText;
      final String? message = _text(decoded['message']);
      if (message != null) return message;
      final Object? error = decoded['error'];
      if (error is Map<Object?, Object?>) {
        final String? errorText = _text(error['message']);
        if (errorText != null) return errorText;
      }
    }
    if (statusCode == 401) return '登录状态已失效，请重新扫码。';
    if (statusCode == 429) return '操作过于频繁，请稍后再试。';
    return '微信登录服务请求失败（HTTP $statusCode）。';
  }

  Future<UnifiedChallenge> createChallenge() async {
    final Map<String, Object?> json = await _request(
      'POST',
      '/v1/wechat/challenges',
      body: null,
    );
    final UnifiedChallenge challenge = UnifiedChallenge.fromJson(json);
    if (challenge.challengeId.isEmpty || challenge.qrTicket.isEmpty) {
      throw UnifiedApiException('二维码数据不完整，请刷新重试。');
    }
    return challenge;
  }

  Future<String> poll(UnifiedChallenge challenge) async {
    final Map<String, Object?> json = await _request(
      'POST',
      '/v1/wechat/challenges/${Uri.encodeComponent(challenge.challengeId)}/poll',
      headers: {'X-Poll-Token': challenge.pollToken},
    );
    return (json['status'] ?? '').toString();
  }

  Future<UnifiedSession> exchange(UnifiedChallenge challenge) async {
    final Map<String, Object?> json = await _request(
      'POST',
      '/v1/auth/exchange',
      body: {
        'challenge_id': challenge.challengeId,
        'poll_token': challenge.pollToken,
        'device_name': 'desktop',
      },
    );
    final UnifiedSession session = UnifiedSession.fromJson(json);
    if (session.accessToken.isEmpty) {
      throw UnifiedApiException('扫码登录未返回登录凭证。');
    }
    return session;
  }

  Future<UnifiedSession> bindWechat({
    required UnifiedChallenge challenge,
    required String legacyToken,
  }) async {
    final Map<String, Object?> json = await _request(
      'POST',
      '/v1/auth/bind',
      body: {
        'challenge_id': challenge.challengeId,
        'poll_token': challenge.pollToken,
        'jiaofangsi_access_token': legacyToken,
        'device_name': 'desktop',
      },
    );
    final UnifiedSession session = UnifiedSession.fromJson(json);
    if (session.accessToken.isEmpty) {
      throw UnifiedApiException('微信绑定未返回登录凭证。');
    }
    return session;
  }

  Future<UnifiedSession> refresh(UnifiedSession session) async {
    final Map<String, Object?> json = await _request(
      'POST',
      '/v1/auth/refresh',
      body: {'refresh_token': session.refreshToken, 'device_name': 'desktop'},
    );
    return UnifiedSession.fromJson(json);
  }

  Future<UnifiedProfile> profile(String token) async {
    final Map<String, Object?> json = await _request(
      'GET',
      '/v1/account/profile',
      bearer: token,
    );
    return UnifiedProfile.fromJson(json);
  }

  Future<List<EntitlementInfo>> entitlements(String token) async {
    final Map<String, Object?> json = await _request(
      'GET',
      '/v1/account/entitlements',
      bearer: token,
    );
    final List<Object?> items =
        json['entitlements'] as List<Object?>? ?? const <Object?>[];
    return items
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> item) {
          final Map<String, Object?> raw = item.cast<String, Object?>();
          DateTime? expireAt = _date(raw['expire_at']);
          int? daysLeft;
          if (expireAt != null) {
            daysLeft = expireAt.difference(DateTime.now()).inDays;
            if (daysLeft < 0) daysLeft = 0;
          }
          return EntitlementInfo(
            entitlementType: _text(raw['entitlement_type']),
            status: _text(raw['status']),
            expireAt: expireAt,
            daysLeft: daysLeft,
            isPermanent:
                (raw['permanent'] ?? raw['is_permanent'] ?? false) == true,
          );
        })
        .toList(growable: false);
  }

  /// Uploads a profile avatar. Backend endpoint expected:
  /// POST /v1/account/avatar (multipart/form-data: file)
  Future<String?> uploadAvatar({
    required String token,
    required Uint8List bytes,
    required String filename,
  }) async {
    final String boundary =
        '----JFS${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final List<int> body = <int>[];
    void addText(String text) => body.addAll(utf8.encode(text));
    addText('--$boundary\r\n');
    addText(
      'Content-Disposition: form-data; name="file"; filename="$filename"\r\n',
    );
    addText('Content-Type: application/octet-stream\r\n\r\n');
    body.addAll(bytes);
    addText('\r\n--$boundary--\r\n');
    try {
      final HttpClientRequest request = await _client.postUrl(
        _uri('/v1/account/avatar'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      request.add(body);
      final HttpClientResponse response = await request.close();
      final String text = await response.transform(utf8.decoder).join();
      final Object? decoded = text.trim().isEmpty ? null : jsonDecode(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UnifiedApiException(
          _errorMessage(decoded, response.statusCode),
          statusCode: response.statusCode,
        );
      }
      if (decoded is Map<Object?, Object?>) {
        final Map<String, Object?> json = decoded.cast<String, Object?>();
        return _text(json['avatar_url'] ?? json['url']);
      }
      return null;
    } on UnifiedApiException {
      rethrow;
    } on SocketException {
      throw UnifiedApiException('网络连接失败，请检查网络后重试。');
    } catch (error) {
      throw UnifiedApiException('头像上传失败：$error');
    }
  }

  Future<PurchaseOrderResult> purchase(String token, String product) async {
    final Map<String, Object?> json = await _request(
      'POST',
      '/v1/account/purchase',
      bearer: token,
      body: {'product': product},
    );
    final Object? data = json['data'];
    if (data is Map<Object?, Object?>) {
      return PurchaseOrderResult.fromJson(data.cast<String, Object?>());
    }
    return PurchaseOrderResult.fromJson(json);
  }

  void close() {
    _client.close(force: true);
  }
}
