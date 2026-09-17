import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AuthService {
  AuthService(this.baseUrl);

  final String baseUrl;

  String get _base => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Future<String?> register(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/users/'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (response.statusCode != 200) {
        debugPrint('[AuthService] register failed: ${response.statusCode}');
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['userId'] ?? data['user_id'] ?? data['id'])?.toString();
    } catch (error) {
      debugPrint('[AuthService] register error: $error');
      return null;
    }
  }

  Future<String?> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/users/login'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['userId'] ?? data['user_id'] ?? data['id'])?.toString();
      }

      final data = jsonDecode(response.body);
      final detail = data is Map<String, dynamic>
          ? data['detail']?.toString() ?? '登入失敗'
          : '登入失敗';
      if (response.statusCode == 404) {
        throw Exception('EMAIL_NOT_EXISTS:$detail');
      }
      if (response.statusCode == 401) {
        throw Exception('WRONG_PASSWORD:$detail');
      }
      throw Exception('LOGIN_FAILED:$detail');
    } catch (error) {
      final text = error.toString();
      if (text.contains('EMAIL_NOT_EXISTS') ||
          text.contains('WRONG_PASSWORD') ||
          text.contains('LOGIN_FAILED')) {
        rethrow;
      }
      throw Exception('NETWORK_ERROR:網路連線失敗，請檢查網路設定');
    }
  }
}
