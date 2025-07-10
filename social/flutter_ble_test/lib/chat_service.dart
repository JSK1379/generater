import 'dart:async';
import 'package:flutter/material.dart';
import 'websocket_service.dart';
import 'chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatService extends ChangeNotifier {
  final WebSocketService _webSocketService = WebSocketService();
  WebSocketService get webSocketService => _webSocketService;
  final List<ChatMessage> _messages = [];
  final List<ChatRoom> _chatRooms = [];
  final Set<String> _joinedRooms = <String>{}; // 已加入的房間列表
  final Set<String> _processedMessages = <String>{}; // 已處理的訊息 ID 列表
  ChatRoom? _currentRoom;
  bool _isConnected = false;
  String _currentUser = '';

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<ChatRoom> get chatRooms => List.unmodifiable(_chatRooms);
  ChatRoom? get currentRoom => _currentRoom;
  bool get isConnected => _isConnected;
  String get currentUser => _currentUser;

  ChatService() {
    _webSocketService.addMessageListener(_handleMessage);
    _webSocketService.addConnectionListener(_handleConnectionChange);
  }

  // 設定當前用戶
  void setCurrentUser(String username) {
    _currentUser = username;
    notifyListeners();
  }

  // 連接聊天室
  Future<bool> connect(String wsUrl, String roomId, String userId) async {
    // 直接使用傳入的 wsUrl，不再拼接任何內容
    return await _webSocketService.connect(wsUrl);
  }

  // 連接 WebSocket 並註冊用戶
  Future<bool> connectAndRegister(String url, String roomId, String userId) async {
    final success = await connect(url, roomId, userId);
    if (success) {
      // 連線成功後立即註冊用戶
      ensureUserRegistered(userId);
    }
    return success;
  }

  // 處理接收到的訊息
  void _handleMessage(Map<String, dynamic> data) {
    debugPrint('ChatService: 收到訊息 - $data');
    
    // 使用 type 來判斷訊息類型
    final messageType = data['type'];
    
    switch (messageType) {
      case 'message':
        // 處理聊天訊息，添加防重複機制
        final messageId = data['id'] ?? 'msg_${DateTime.now().millisecondsSinceEpoch}';
        
        // 防重複：檢查是否已處理過此訊息
        if (_processedMessages.contains(messageId)) {
          debugPrint('ChatService: 訊息 $messageId 已處理過，跳過重複處理');
          break;
        }
        
        final message = ChatMessage(
          id: messageId,
          type: 'text',
          content: data['content'] ?? '', // 使用 content 欄位
          sender: data['sender'] ?? '',
          timestamp: DateTime.tryParse(data['timestamp'] ?? '') ?? DateTime.now(),
          imageUrl: data['imageUrl'],
        );
        _messages.add(message);
        _processedMessages.add(messageId); // 記錄已處理的訊息
        debugPrint('ChatService: 新增聊天訊息 - ${message.content}');
        notifyListeners();
        break;
      case 'room_joined':
        final room = ChatRoom.fromJson(data['room']);
        _currentRoom = room;
        if (!_chatRooms.any((r) => r.id == room.id)) {
          _chatRooms.add(room);
        }
        _joinedRooms.add(room.id); // 將房間 ID 加入已加入房間列表
        notifyListeners();
        break;
      case 'room_list':
        _chatRooms.clear();
        for (final roomData in data['rooms']) {
          _chatRooms.add(ChatRoom.fromJson(roomData));
        }
        notifyListeners();
        break;
      case 'user_joined':
        // 處理用戶加入通知
        debugPrint('ChatService: 用戶加入 - ${data['user']}');
        break;
      case 'user_left':
        // 處理用戶離開通知
        debugPrint('ChatService: 用戶離開 - ${data['user']}');
        break;
      case 'connect_response':
        // 處理連接回應
        final fromUser = data['from'];
        final toUser = data['to'];
        final accept = data['accept'];
        final roomId = data['roomId'];
        debugPrint('[ChatService] 收到 connect_response: from=$fromUser, to=$toUser, accept=$accept, roomId=$roomId');
        if (accept == true && roomId != null && roomId is String && !_joinedRooms.contains(roomId)) {
          // 自動加入聊天室
          joinRoom(roomId);
          debugPrint('[ChatService] 自動 join_room: $roomId');
        }
        notifyListeners();
        break;
      case 'room_created':
        // 處理聊天室創建回應
        final roomId = data['roomId'];
        debugPrint('[ChatService] 收到 room_created: roomId=$roomId');
        notifyListeners();
        break;
    }
  }

  // 處理連線狀態變化
  void _handleConnectionChange(bool connected) {
    _isConnected = connected;
    if (!connected) {
      // 連線斷開時清空當前房間
      _currentRoom = null;
    }
    notifyListeners();
  }

  // 建立房間，伺服器回傳 roomId
  Future<String?> createRoom(String name) async {
    final completer = Completer<String?>();
    void handler(Map<String, dynamic> data) {
      if (data['type'] == 'room_created') {
        _webSocketService.removeMessageListener(handler);
        completer.complete(data['roomId'] as String?);
      }
    }
    _webSocketService.addMessageListener(handler);
    _webSocketService.sendMessage({
      'type': 'create_room',
      'name': name,
    });
    return completer.future;
  }

  // 加入房間，伺服器回傳 joined_room（添加防呆機制）
  Future<bool> joinRoom(String roomId) async {
    // 防呆：檢查是否已加入此房間
    if (_joinedRooms.contains(roomId)) {
      debugPrint('[ChatService] 房間 $roomId 已加入，跳過重複 join');
      return true;
    }

    debugPrint('[ChatService] 正在加入房間: $roomId');
    final completer = Completer<bool>();
    void handler(Map<String, dynamic> data) {
      if (data['type'] == 'joined_room' && data['roomId'] == roomId) {
        _webSocketService.removeMessageListener(handler);
        _joinedRooms.add(roomId); // 記錄已加入的房間
        debugPrint('[ChatService] 成功加入房間: $roomId');
        completer.complete(true);
      }
    }
    _webSocketService.addMessageListener(handler);
    _webSocketService.sendMessage({
      'type': 'join_room',
      'roomId': roomId,
    });
    return completer.future;
  }

  // 離開房間，伺服器回傳 left_room
  Future<bool> leaveRoom(String roomId) async {
    final completer = Completer<bool>();
    void handler(Map<String, dynamic> data) {
      if (data['type'] == 'left_room' && data['roomId'] == roomId) {
        _webSocketService.removeMessageListener(handler);
        completer.complete(true);
      }
    }
    _webSocketService.addMessageListener(handler);
    _webSocketService.sendMessage({
      'type': 'leave_room',
      'roomId': roomId,
    });
    return completer.future;
  }

  // 傳送聊天訊息
  void sendTextMessage(String roomId, String sender, String content, {String? imageUrl}) async {
    // 獲取當前用戶 ID
    final userId = await getCurrentUserId();
    
    final message = {
      'type': 'message',
      'id': 'msg_${DateTime.now().millisecondsSinceEpoch}', // id 欄位作為訊息的唯一識別碼
      'sender': userId, // sender 使用用戶 ID (string)
      'roomId': roomId,
      'content': content,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'imageUrl': imageUrl, // 如果沒有圖片會是 null
    };
    
    debugPrint('ChatService: 發送聊天訊息到伺服器 - $message');
    _webSocketService.sendMessage(message);
  }

  // 離開當前聊天室
  void leaveCurrentRoom() {
    if (_currentRoom != null) {
      _webSocketService.sendMessage({
        'type': 'leave_room',
        'roomId': _currentRoom!.id,
        'user': _currentUser,
      });
      _currentRoom = null;
      _messages.clear();
      notifyListeners();
    }
  }

  // 斷開連線
  void disconnect() {
    _webSocketService.disconnect();
    _currentRoom = null;
    _messages.clear();
    _chatRooms.clear();
    notifyListeners();
  }

  // 發送連接請求
  void sendConnectRequest(String fromUserId, String toUserId) {
    _webSocketService.sendMessage({
      'type': 'connect_request',
      'from': fromUserId,
      'to': toUserId,
    });
    debugPrint('[ChatService] Sent connect_request from: $fromUserId to: $toUserId');
  }

  // 刪除聊天室
  void deleteRoom(String roomId) {
    _webSocketService.sendMessage({
      'type': 'delete_room',
      'roomId': roomId,
      'user': _currentUser,
    });
    debugPrint('[ChatService] Sent delete_room for: $roomId');
  }

  // 生成房間 ID（根據兩個用戶 ID）
  String generateRoomId(String userId1, String userId2) {
    final sortedUsers = [userId1, userId2]..sort();
    return 'room_${sortedUsers[0]}_${sortedUsers[1]}';
  }

  // 取得當前用戶 ID
  Future<String> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? 'unknown_user';
  }

  // 確保用戶已註冊（在發送其他請求前調用）
  void ensureUserRegistered(String userId) {
    if (_isConnected) {
      _webSocketService.sendMessage({
        'type': 'register_user',
        'userId': userId,
      });
      debugPrint('[ChatService] 確保用戶已註冊: $userId');
    }
  }

  @override
  void dispose() {
    _webSocketService.dispose();
    super.dispose();
  }
}
