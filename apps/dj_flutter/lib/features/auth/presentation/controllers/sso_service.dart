import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SsoException implements Exception {
  const SsoException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SsoService {
  SsoService({
    this.baseUrl = 'https://auth.jiaofangsi.top/wechat-auth/v1/sso',
  });

  final String baseUrl;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  Future<String> issueCode({
    required String accessToken,
    String? refreshToken,
    String? userId,
    String? loginName,
  }) async {
    final Map<String, Object?> body = <String, Object?>{
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'user_id': userId,
      'login_name': loginName,
    };
    try {
      final HttpClientRequest request = await _client.postUrl(
        Uri.parse('$baseUrl/issue'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      request.write(jsonEncode(body));
      final HttpClientResponse response = await request.close();
      final String text = await response.transform(utf8.decoder).join();
      final Object? decoded = text.trim().isEmpty ? null : jsonDecode(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SsoException('一键登录服务暂时不可用');
      }
      if (decoded is! Map<Object?, Object?>) {
        throw const SsoException('一键登录服务返回数据异常');
      }
      final String? code = (decoded['code'] ?? '').toString().trim();
      if (code == null || code.isEmpty) {
        throw const SsoException('一键登录服务未返回登录码');
      }
      return code;
    } on SsoException {
      rethrow;
    } on SocketException {
      throw const SsoException('网络连接失败，请稍后重试');
    } on TimeoutException {
      throw const SsoException('网络请求超时，请稍后重试');
    } catch (_) {
      throw const SsoException('一键登录服务请求失败');
    }
  }

  void close() {
    _client.close(force: true);
  }
}
