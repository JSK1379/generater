import 'dart:async';
import 'package:flutter/material.dart';
import 'websocket_service.dart';
import 'chat_models.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class ChatService extends ChangeNotifier {
  final WebSocketService _webSocketService = WebSocketService();
  final List<ChatMessage> _messages = [];
  final List<ChatRoom> _chatRooms = [];
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

  // 處理接收到的訊息
  void _handleMessage(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'message':
        final message = ChatMessage.fromJson(data);
        _messages.add(message);
        notifyListeners();
        break;
      case 'room_joined':
        final room = ChatRoom.fromJson(data['room']);
        _currentRoom = room;
        if (!_chatRooms.any((r) => r.id == room.id)) {
          _chatRooms.add(room);
        }
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
        break;
      case 'user_left':
        // 處理用戶離開通知
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

  // 加入房間，伺服器回傳 joined_room
  Future<bool> joinRoom(String roomId) async {
    final completer = Completer<bool>();
    void handler(Map<String, dynamic> data) {
      if (data['type'] == 'joined_room' && data['roomId'] == roomId) {
        _webSocketService.removeMessageListener(handler);
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
  void sendTextMessage(String roomId, String sender, String content, {String? imageUrl}) {
    final message = {
      'type': 'message',
      'id': _generateMessageId(),
      'sender': sender,
      'roomId': roomId,
      'content': content,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'imageUrl': imageUrl,
    };
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

  // 生成訊息 ID
  String _generateMessageId() {
    final random = Random();
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(1000)}';
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

  @override
  void dispose() {
    _webSocketService.dispose();
    super.dispose();
  }
}
