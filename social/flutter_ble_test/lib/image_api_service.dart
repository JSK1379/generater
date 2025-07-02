import 'dart:io';

class ImageApiService {
  // 模擬圖片上傳，回傳一個假圖片ID
  Future<String> uploadImage(File imageFile) async {
    await Future.delayed(const Duration(seconds: 1));
    // 假設每次都回傳一個固定ID
    return 'mock_image_id_123';
  }

  // 由圖片ID取得圖片URL（這裡用假網址）
  String getImageUrl(String imageId) {
    // 實際上應該根據 imageId 組合出正確的圖片網址
    return 'https://example.com/images/$imageId.jpg';
  }
}
