import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


class ImageApiService {
  // 圖片上傳到 server，回傳圖片ID
  Future<String> uploadImage(File imageFile) async {
    final uri = Uri.parse('https://near-ride-backend-api.onrender.com/');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    final response = await request.send();
    if (response.statusCode == 200) {
      final respStr = await response.stream.bytesToString();
      final data = jsonDecode(respStr);
      // 假設 server 回傳 { "image_id": "xxx" }
      final imageId = data['image_id'] ?? '';
      debugPrint('[ImageApiService] 圖片上傳成功，image_id: $imageId');
      return imageId;
    } else {
      debugPrint('[ImageApiService] 圖片上傳失敗: ${response.statusCode}');
      throw Exception('圖片上傳失敗: ${response.statusCode}');
    }
  }

  // 由圖片ID取得圖片URL（這裡用假網址）
  String getImageUrl(String imageId) {
    // 實際上應該根據 imageId 組合出正確的圖片網址
    return 'https://example.com/images/$imageId.jpg';
  }
}
