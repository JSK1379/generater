import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_config.dart';


class ImageApiService {
  // 圖片上傳到 server，回傳圖片ID
  Future<String> uploadImage(File imageFile) async {
    try {
      final uri = Uri.parse(ApiConfig.imageUpload);
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));
      
      final response = await request.send();
      
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        debugPrint('[ImageApiService] 圖片上傳成功，回應: $respStr');
        
        try {
          final data = jsonDecode(respStr);
          // 支援多種可能的回應格式，參考頭像上傳的成功經驗
          final imageId = data['image_id'] ?? data['id'] ?? data['file_id'] ?? '';
          
          if (imageId.isNotEmpty) {
            debugPrint('[ImageApiService] 獲得圖片 ID: $imageId');
            return imageId;
          } else {
            debugPrint('[ImageApiService] 伺服器回應中沒有圖片 ID: $data');
            throw Exception('伺服器回應中沒有圖片 ID');
          }
        } catch (e) {
          debugPrint('[ImageApiService] 解析回應 JSON 失敗: $e，原始回應: $respStr');
          throw Exception('解析回應失敗: $e');
        }
      } else {
        debugPrint('[ImageApiService] 圖片上傳失敗: ${response.statusCode}');
        throw Exception('圖片上傳失敗: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[ImageApiService] 圖片上傳錯誤: $e');
      rethrow;
    }
  }

  // 由圖片ID取得圖片URL
  String getImageUrl(String imageId) {
    return ApiConfig.imageUrl(imageId);
  }
}
