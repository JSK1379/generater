import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ProfileService {
  ProfileService(this.baseUrl);

  final String baseUrl;

  String get _base => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_base/users/$userId'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return null;
      }
      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> ? data : null;
    } catch (error) {
      debugPrint('[ProfileService] profile error: $error');
      return null;
    }
  }

  /// Compatibility upload used by the legacy facade. The destination is kept
  /// as the exact URL supplied by the caller to preserve existing behavior.
  Future<String?> uploadAvatar(
    String userId,
    String base64Image, {
    String? endpoint,
  }) async {
    try {
      final Uint8List imageBytes = base64Decode(base64Image);
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(endpoint ?? baseUrl),
      )
        ..fields['user_id'] = userId
        ..files.add(
          http.MultipartFile.fromBytes(
            'avatar',
            imageBytes,
            filename: 'avatar.png',
          ),
        );

      final response = await request.send();
      if (response.statusCode != 200) {
        return null;
      }
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) {
        return null;
      }
      return (data['avatar_url'] ?? data['url'] ?? data['image_url'])
          ?.toString();
    } catch (error) {
      debugPrint('[ProfileService] avatar upload error: $error');
      return null;
    }
  }
}
