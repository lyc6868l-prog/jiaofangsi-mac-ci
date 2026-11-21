import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PasswordResetService {
  PasswordResetService({this.baseUrl = 'https://auth.jiaofangsi.top'});

  final String baseUrl;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  Future<void> sendCode(String loginName) async {
    await _post('/auth/send-reset-code', <String, Object?>{
      'login_name': loginName,
    });
  }

  Future<void> resetPassword({
    required String loginName,
    required String code,
    required String newPassword,
  }) async {
    await _post('/auth/reset-password', <String, Object?>{
      'login_name': loginName,
      'code': code,
      'new_password': newPassword,
    });
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      final HttpClientRequest request = await _client.postUrl(
        Uri.parse('$baseUrl$path'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final HttpClientResponse response = await request.close();
      final String text = await response.transform(utf8.decoder).join();
      final Object? decoded = text.trim().isEmpty ? null : jsonDecode(text);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = '操作失败，请稍后重试';
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
        throw PasswordResetException(message);
      }
      return decoded is Map<Object?, Object?>
          ? decoded.cast<String, Object?>()
          : <String, Object?>{};
    } on PasswordResetException {
      rethrow;
    } on SocketException {
      throw const PasswordResetException('网络连接失败，请检查网络后重试');
    } on TimeoutException {
      throw const PasswordResetException('网络请求超时，请稍后重试');
    } catch (_) {
      throw const PasswordResetException('操作失败，请稍后重试');
    }
  }

  void close() => _client.close(force: true);
}

class PasswordResetException implements Exception {
  const PasswordResetException(this.message);

  final String message;

  @override
  String toString() => message;
}
