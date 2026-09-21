import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:near_ride/core/config/api_config.dart';

/// Uploads chat images through the Near Ride backend.
class ImageApiService {
  Future<String> uploadImage(File imageFile) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConfig.imageUpload),
      )..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        throw Exception('圖片上傳失敗: ${response.statusCode}');
      }

      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) {
        throw Exception('伺服器回應格式錯誤');
      }

      final imageId = data['image_id'] ?? data['id'] ?? data['file_id'];
      if (imageId == null || imageId.toString().isEmpty) {
        throw Exception('伺服器回應中沒有圖片 ID');
      }

      if (kDebugMode) {
        debugPrint('[ImageApiService] uploaded image: $imageId');
      }
      return imageId.toString();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[ImageApiService] upload failed: $error');
      }
      rethrow;
    }
  }

  String getImageUrl(String imageId) => ApiConfig.imageUrl(imageId);
}
