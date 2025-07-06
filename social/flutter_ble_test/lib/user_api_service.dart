import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class UserApiService {
  final String baseUrl;
  UserApiService(this.baseUrl);

  Future<void> uploadUserId(String userId) async {
    // 若有需要可改為 HTTP POST 上傳 userId
    // 目前僅 log 行為
    debugPrint('[UserApiService] uploadUserId: $userId');
  }

  Future<void> uploadAvatar(String userId, String base64Image) async {
    // 將 base64 字串轉為 Uint8List
    Uint8List imageBytes = base64Decode(base64Image);
    final uri = Uri.parse(baseUrl); // 直接用 baseUrl，不拼接 upload_avatar
    final request = http.MultipartRequest('POST', uri)
      ..fields['user_id'] = userId
      ..files.add(http.MultipartFile.fromBytes('avatar', imageBytes, filename: 'avatar.png'));
    final response = await request.send();
    if (response.statusCode == 200) {
      debugPrint('[UserApiService] 頭像上傳成功 (user_id: $userId)');
    } else {
      debugPrint('[UserApiService] 頭像上傳失敗: ${response.statusCode}');
    }
  }

  void dispose() {}
}
