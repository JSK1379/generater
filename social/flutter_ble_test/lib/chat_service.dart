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
  Future<bool> connect(String baseUrl, String roomId, String userId) async {
    final wsUrl = '$baseUrl/ws/chat/$roomId/$userId';
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

  // 加入聊天室
  void joinRoom(String roomId, String roomName) {
    _webSocketService.sendMessage({
      'type': 'join_room',
      'roomId': roomId,
      'roomName': roomName,
      'user': _currentUser,
    });
  }

  // 創建聊天室
  void createRoom(String roomName, List<String> participants) {
    final roomId = _generateRoomId();
    _webSocketService.sendMessage({
      'type': 'create_room',
      'roomId': roomId,
      'roomName': roomName,
      'participants': participants,
      'user': _currentUser,
    });
  }

  // 發送文字訊息
  void sendTextMessage(String content) {
    if (_currentRoom == null || content.trim().isEmpty) return;
    
    final message = {
      'type': 'message',
      'id': _generateMessageId(),
      'sender': _currentUser,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
      'roomId': _currentRoom!.id,
      'messageType': 'text',
    };
    
    _webSocketService.sendMessage(message);
  }

  // 發送圖片訊息
  void sendImageMessage(String imageUrl) {
    if (_currentRoom == null) return;
    
    final message = {
      'type': 'message',
      'id': _generateMessageId(),
      'sender': _currentUser,
      'content': '',
      'imageUrl': imageUrl,
      'timestamp': DateTime.now().toIso8601String(),
      'roomId': _currentRoom!.id,
      'messageType': 'image',
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

  // 生成房間 ID
  String _generateRoomId() {
    final random = Random();
    return 'room_${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(1000)}';
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
