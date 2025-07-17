import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class UserApiService {
  final String baseUrl;
  UserApiService(this.baseUrl);

  Future<String?> registerUserWithEmail(String email, String password) async {
    try {
      // 確保 URL 正確拼接，處理有無尾隨斜線的情況
      final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      final uri = Uri.parse('${cleanBaseUrl}users/');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userIdRaw = data['userId'] ?? data['user_id'] ?? data['id'];
        final userId = userIdRaw?.toString(); // 確保轉換為 String
        debugPrint('[UserApiService] HTTP 用戶註冊成功: email=$email, userId=$userId');
        return userId;
      } else {
        debugPrint('[UserApiService] HTTP 用戶註冊失敗: ${response.statusCode}, ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[UserApiService] HTTP 用戶註冊錯誤: $e');
      return null;
    }
  }

  Future<bool> registerUser(String userId) async {
    try {
      final uri = Uri.parse(baseUrl);
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId}),
      );
      
      if (response.statusCode == 200) {
        debugPrint('[UserApiService] HTTP 用戶註冊成功: $userId');
        return true;
      } else {
        debugPrint('[UserApiService] HTTP 用戶註冊失敗: ${response.statusCode}, ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[UserApiService] HTTP 用戶註冊錯誤: $e');
      return false;
    }
  }

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
  
  // 添加好友
  Future<String?> addFriend(String userId, String friendId) async {
    try {
      // 確保 URL 正確拼接
      final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      final uri = Uri.parse('${cleanBaseUrl}friends/add_friend');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'friend_id': friendId,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final roomId = data['room_id'];
        debugPrint('[UserApiService] 添加好友成功: userId=$userId, friendId=$friendId, roomId=$roomId');
        return roomId;
      } else {
        debugPrint('[UserApiService] 添加好友失敗: ${response.statusCode}, ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[UserApiService] 添加好友錯誤: $e');
      return null;
    }
  }
  
  // 獲取好友列表
  Future<List<Map<String, dynamic>>?> getFriends(String userId) async {
    try {
      // 確保 URL 正確拼接
      final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      final uri = Uri.parse('${cleanBaseUrl}friends/friends/$userId');
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final friends = List<Map<String, dynamic>>.from(data['friends']);
        debugPrint('[UserApiService] 獲取好友列表成功: userId=$userId, count=${friends.length}');
        return friends;
      } else {
        debugPrint('[UserApiService] 獲取好友列表失敗: ${response.statusCode}, ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[UserApiService] 獲取好友列表錯誤: $e');
      return null;
    }
  }
  
  // 獲取聊天記錄
  Future<List<Map<String, dynamic>>?> getChatHistory(String roomId, {int limit = 50}) async {
    const int maxRetries = 3;
    const Duration timeoutDuration = Duration(seconds: 10);
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('[UserApiService] 嘗試獲取聊天記錄 (第 $attempt 次): roomId=$roomId');
        
        // 確保 URL 正確拼接
        final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
        final uri = Uri.parse('${cleanBaseUrl}friends/chat_history/$roomId?limit=$limit');
        
        final response = await http.get(uri).timeout(timeoutDuration);
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          // 檢查回應格式 - 可能是直接的陣列或包含 chat_history 欄位的物件
          List<dynamic>? chatHistoryData;
          
          if (data is List) {
            // 直接返回陣列格式
            chatHistoryData = data;
            debugPrint('[UserApiService] 收到直接陣列格式的聊天記錄');
          } else if (data is Map<String, dynamic> && data['chat_history'] != null) {
            // 包裝在 chat_history 欄位中的格式
            chatHistoryData = data['chat_history'];
            debugPrint('[UserApiService] 收到包裝格式的聊天記錄');
          }
          
          // 檢查聊天記錄是否存在且為列表
          if (chatHistoryData != null) {
            final chatHistory = List<Map<String, dynamic>>.from(chatHistoryData);
            debugPrint('[UserApiService] 獲取聊天記錄成功: roomId=$roomId, count=${chatHistory.length}');
            return chatHistory;
          } else {
            debugPrint('[UserApiService] 聊天記錄為空或格式不正確: $data');
            return [];
          }
        } else {
          debugPrint('[UserApiService] 獲取聊天記錄失敗: ${response.statusCode}, ${response.body}');
          if (attempt == maxRetries) {
            return null;
          }
        }
      } catch (e) {
        debugPrint('[UserApiService] 獲取聊天記錄錯誤 (第 $attempt 次): $e');
        if (attempt == maxRetries) {
          return null;
        }
        
        // 等待一段時間後重試
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    
    return null;
  }

  void dispose() {}
}
