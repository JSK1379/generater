import 'dart:async';
// import 'dart:io'; // 臨時註釋：圖片上傳功能暫時禁用
import 'package:flutter/material.dart';
import 'package:near_ride/core/network/websocket_service.dart';
import 'package:near_ride/features/chat/models/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:near_ride/features/friends/services/friend_service.dart';
import 'package:near_ride/features/profile/services/profile_service.dart';
// import 'image_api_service.dart'; // 臨時註釋：圖片上傳功能暫時禁用
import 'package:near_ride/core/config/api_config.dart';
import 'package:near_ride/features/ai/services/ai_service.dart'; // 安全版本的 Gemini Service

class ChatService extends ChangeNotifier {
  final WebSocketService _webSocketService = WebSocketService();
  // 創建 UserApiService 實例，使用統一的API配置
  final FriendService _friendService = FriendService(ApiConfig.baseUrl);
  final ProfileService _profileService = ProfileService(ApiConfig.baseUrl);
  // 創建 GeminiService 實例，用於前端 AI 功能
  final SecureGeminiService _geminiService = SecureGeminiService();
  // 創建 ImageApiService 實例，用於圖片上傳
  // final ImageApiService _imageApiService = ImageApiService(); // 臨時註釋：圖片上傳功能暫時禁用
  WebSocketService get webSocketService => _webSocketService;
  // 按房間 ID 分離的訊息存儲
  final Map<String, List<ChatMessage>> _roomMessages = <String, List<ChatMessage>>{};
  final List<ChatRoom> _chatRooms = [];
  final Set<String> _joinedRooms = <String>{}; // 已加入的房間列表
  final Set<String> _processedMessages = <String>{}; // 已處理的訊息 ID 列表
  final Set<String> _fetchedHistoryRooms = <String>{}; // 已獲取歷史記錄的房間列表
  final Set<String> _registeredUsers = <String>{}; // 已註冊的用戶列表
  ChatRoom? _currentRoom;
  bool _isConnected = false;
  String _currentUser = '';
  
  // 連線狀態 Stream
  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();
  
  // 連接請求回調監聽器
  final List<void Function(String from, String to, bool accept)> _connectResponseListeners = [];
  // 全局連接請求監聽器
  final List<void Function(String from, String to)> _connectRequestListeners = [];

  List<ChatMessage> get messages {
    if (_currentRoom == null) {
      return [];
    }
    final roomMessages = _roomMessages[_currentRoom!.id] ?? [];
    return List.unmodifiable(roomMessages);
  }
  List<ChatRoom> get chatRooms => List.unmodifiable(_chatRooms);
  ChatRoom? get currentRoom => _currentRoom;
  bool get isConnected => _isConnected;
  String get currentUser => _currentUser;
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  // 獲取或創建房間的訊息列表
  List<ChatMessage> _getOrCreateRoomMessages(String roomId) {
    if (!_roomMessages.containsKey(roomId)) {
      _roomMessages[roomId] = <ChatMessage>[];
    }
    return _roomMessages[roomId]!;
  }
  
  // 獲取指定房間的訊息列表（公開方法）
  List<ChatMessage> getMessagesForRoom(String roomId) {
    return _roomMessages[roomId] ?? [];
  }

  // 清空指定房間的訊息
  void _clearRoomMessages(String roomId) {
    _roomMessages[roomId] = <ChatMessage>[];
  }

  ChatService() {
    _webSocketService.addMessageListener(_handleMessage);
    _webSocketService.addConnectionListener(_handleConnectionChange);
    
    // 發送初始連線狀態
    _connectionStateController.add(_isConnected);
  }

  // 設定當前用戶
  void setCurrentUser(String username) {
    if (_currentUser != username) {
      _currentUser = username;
      
      // 如果已經連線，自動註冊新的當前用戶
      if (_isConnected && username.isNotEmpty) {
        debugPrint('[ChatService] 設置當前用戶並自動註冊: $username');
        Future.microtask(() => ensureUserRegistered(username));
      }
      
      // 使用 Future.microtask 確保通知不會在構建過程中觸發
      Future.microtask(() => notifyListeners());
    }
  }
  
  // 設定當前聊天室
  void setCurrentRoom(String roomId) {
    // 確保房間對象存在
    _ensureRoomExists(roomId);
    
    // 尋找房間對象
    final rooms = _chatRooms.where((room) => room.id == roomId).toList();
    if (rooms.isNotEmpty) {
      _currentRoom = rooms.first;
      debugPrint('[ChatService] 設置當前房間: $roomId');
      notifyListeners();
    } else {
      debugPrint('[ChatService] 無法設置當前房間，找不到房間: $roomId');
    }
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
      case 'chat_history':
        // 注意：我們已經不再通過 WebSocket 獲取聊天歷史記錄，改用 HTTP 請求
        // 這個處理邏輯保留只是為了向下兼容
        final roomId = data['roomId'];
        if (roomId != null && roomId is String) {
          debugPrint('[ChatService] 收到 chat_history 消息: $roomId，但不再處理，改用 HTTP 請求');
        }
        break;
      case 'connect_request':
        // 處理連接請求
        final fromUser = data['from'];
        final toUser = data['to'];
        debugPrint('[ChatService] 收到 connect_request: from=$fromUser, to=$toUser');
        // 通知所有全局連接請求監聽器
        for (var listener in _connectRequestListeners) {
          listener(fromUser, toUser);
        }
        notifyListeners();
        break;
      case 'message':
        // 處理聊天訊息，添加防重複機制
        final messageId = data['id'] ?? 'msg_${DateTime.now().millisecondsSinceEpoch}';
        final sender = data['sender'] ?? '';
        final content = data['content'] ?? '';
        final roomId = data['roomId'] ?? _currentRoom?.id; // 優先使用訊息中的房間 ID，否則使用當前房間
        
        debugPrint('ChatService: 收到訊息 - $data');
        
        // 如果沒有房間 ID，跳過處理
        if (roomId == null) {
          debugPrint('ChatService: 訊息沒有房間 ID，跳過處理');
          break;
        }
        
        // 防重複：檢查是否已處理過此訊息
        if (_processedMessages.contains(messageId)) {
          debugPrint('ChatService: 訊息 $messageId 已處理過，跳過重複處理，為什麼會重複發送訊息跟加入房間');
          break;
        }
        
        final message = ChatMessage(
          id: messageId,
          type: 'text',
          content: content,
          sender: sender,
          timestamp: DateTime.tryParse(data['timestamp'] ?? '') ?? DateTime.now(),
          imageUrl: data['imageUrl'],
        );
        
        // 添加到對應房間的訊息列表
        final roomMessages = _getOrCreateRoomMessages(roomId);
        roomMessages.add(message);
        _processedMessages.add(messageId); // 記錄已處理的訊息
        
        debugPrint('ChatService: 新增聊天訊息到房間 $roomId - ${message.content}');
        debugPrint('ChatService: 房間 $roomId 現在有 ${roomMessages.length} 條訊息');
        debugPrint('ChatService: 當前房間: ${_currentRoom?.id}');
        debugPrint('ChatService: 房間匹配: ${_currentRoom?.id == roomId}');
        
        notifyListeners();
        break;
      case 'joined_room':
        // 處理從伺服器收到的已加入房間消息
        final roomId = data['roomId'];
        if (roomId != null) {
          // 檢查是否有等待的 completer
          final hasCompleter = _joinRoomCompleters.containsKey(roomId);
          if (!hasCompleter) {
            // 如果沒有 completer，表示這可能是一個重複的 joined_room 消息
            // 或者是從其他地方（如主頁）加入房間的響應
            debugPrint('[ChatService] 收到 joined_room，但沒有等待的 completer: $roomId');
          }
          
          debugPrint('[ChatService] ✅ 成功加入房間: $roomId');
          
          // 添加到已加入房間集合
          _joinedRooms.add(roomId);
          
          // 🔄 確保房間存在且設置為當前房間
          _ensureRoomExists(roomId);
          
          // 創建房間對象並添加到列表中
          if (!_chatRooms.any((r) => r.id == roomId)) {
            // 從 roomId 中提取參與者信息
            final participants = <String>[];
            if (roomId.startsWith('friend_')) {
              final parts = roomId.split('_');
              if (parts.length >= 3) {
                participants.add(parts[1]);
                participants.add(parts[2]);
              }
            }
            
            // 嘗試獲取房間名稱
            String roomName = data['roomName'] ?? '聊天室 $roomId';
            
            // 嘗試獲取對方用戶 ID
            String otherUserId = '';
            if (data['otherUserId'] != null) {
              otherUserId = data['otherUserId'];
              // 如果有對方用戶 ID 但沒有房間名稱，設置默認房間名稱
              if (roomName == '聊天室 $roomId') {
                roomName = '與 $otherUserId 的聊天';
              }
              // 確保對方用戶 ID 在參與者列表中
              if (!participants.contains(otherUserId)) {
                participants.add(otherUserId);
              }
            }
            
            // 獲取當前用戶 ID
            getCurrentUserId().then((currentUserId) {
              // 確保當前用戶 ID 在參與者列表中
              if (!participants.contains(currentUserId) && currentUserId != 'unknown_user') {
                participants.add(currentUserId);
              }
              
              // 儲存房間信息到 SharedPreferences
              SharedPreferences.getInstance().then((prefs) {
                // 更新房間 ID 列表
                var roomIds = prefs.getStringList('room_ids') ?? [];
                if (!roomIds.contains(roomId)) {
                  roomIds.add(roomId);
                  prefs.setStringList('room_ids', roomIds);
                  debugPrint('[ChatService] 已將房間 $roomId 添加到 room_ids 列表');
                }
                
                // 儲存聊天室資訊
                if (otherUserId.isNotEmpty) {
                  final history = ChatRoomHistory(
                    roomId: roomId,
                    roomName: roomName,
                    lastMessage: '',
                    lastMessageTime: DateTime.now(),
                    otherUserId: otherUserId,
                  );
                  prefs.setString('chat_room_info_$roomId', jsonEncode(history.toJson()));
                  debugPrint('[ChatService] 已儲存聊天室資訊: ${history.toJson()}');
                }
              });
            });
            
            final room = ChatRoom(
              id: roomId,
              name: roomName,
              participants: participants,
              createdAt: DateTime.now(),
            );
            _chatRooms.add(room);
            debugPrint('[ChatService] 已添加房間到 _chatRooms: ${room.toJson()}');
          }
          
          notifyListeners();
        }
        break;
      case 'room_joined':
        final room = ChatRoom.fromJson(data['room']);
        _currentRoom = room;
        if (!_chatRooms.any((r) => r.id == room.id)) {
          _chatRooms.add(room);
        }
        // 房間已在 joinRoom 方法中被標記為已加入，這裡不需要再次添加
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
        final error = data['error'];
        
        debugPrint('[ChatService] 收到 connect_response: from=$fromUser, to=$toUser, accept=$accept, roomId=$roomId');
        
        // 檢查是否有錯誤訊息
        if (error != null) {
          debugPrint('[ChatService] connect_response 錯誤: $error');
          // 通知所有監聽器，但不做其他處理
          for (var listener in _connectResponseListeners) {
            listener(fromUser, toUser, false);
          }
          notifyListeners();
          break;
        }
        
        // 若接受連接且服務器返回了 roomId，則處理房間加入
        if (accept == true && roomId != null && roomId is String) {
          // 添加到已加入房間集合
          _joinedRooms.add(roomId);
          
          // 添加房間到聊天室列表
          if (!_chatRooms.any((r) => r.id == roomId)) {
            // 從 roomId 中提取參與者信息
            final participants = <String>[];
            if (roomId.startsWith('friend_')) {
              final parts = roomId.split('_');
              if (parts.length >= 3) {
                participants.add(parts[1]);
                participants.add(parts[2]);
              }
            } else {
              // 確保對方用戶和當前用戶都在參與者列表中
              participants.add(fromUser);
              participants.add(toUser);
            }
            
            // 儲存房間信息到 SharedPreferences
            getCurrentUserId().then((currentUserId) {
              // 對方用戶 ID
              final otherUserId = (fromUser == currentUserId) ? toUser : fromUser;
              
              SharedPreferences.getInstance().then((prefs) {
                // 更新房間 ID 列表
                var roomIds = prefs.getStringList('room_ids') ?? [];
                if (!roomIds.contains(roomId)) {
                  roomIds.add(roomId);
                  prefs.setStringList('room_ids', roomIds);
                  debugPrint('[ChatService] connect_response: 已將房間 $roomId 添加到 room_ids 列表');
                }
                
                // 儲存聊天室資訊
                final history = ChatRoomHistory(
                  roomId: roomId,
                  roomName: '與 $otherUserId 的聊天',
                  lastMessage: '',
                  lastMessageTime: DateTime.now(),
                  otherUserId: otherUserId,
                );
                prefs.setString('chat_room_info_$roomId', jsonEncode(history.toJson()));
                debugPrint('[ChatService] connect_response: 已儲存聊天室資訊: ${history.toJson()}');
              });
            });
            
            final room = ChatRoom(
              id: roomId,
              name: '與$fromUser的聊天',
              participants: participants,
              createdAt: DateTime.now(),
            );
            _chatRooms.add(room);
            debugPrint('[ChatService] connect_response: 已添加房間到 _chatRooms: $roomId');
          }
          
          // 注意：不在這裡自動加入聊天室，而是讓 MainTabPage 處理
          // 記錄 roomId 供後續處理
          debugPrint('[ChatService] connect_response 收到 roomId: $roomId');
        }
        
        // 通知所有監聽器
        for (var listener in _connectResponseListeners) {
          listener(fromUser, toUser, accept);
        }
        notifyListeners();
        break;
      case 'room_created':
        // 處理聊天室創建回應
        final roomId = data['roomId'];
        debugPrint('[ChatService] 收到 room_created: roomId=$roomId');
        notifyListeners();
        break;
      case 'user_registered':
        // 處理用戶註冊成功回應
        final success = data['success'];
        final userId = data['userId'];
        final message = data['message'];
        
        debugPrint('[ChatService] 收到 user_registered: success=$success, userId=$userId, message=$message');
        
        // 如果沒有明確的 success 字段，但有 userId，視為註冊成功
        final isSuccess = (success == true) || (success == null && userId != null);
        
        if (isSuccess && userId != null) {
          debugPrint('[ChatService] 用戶註冊成功: $userId');
          _registeredUsers.add(userId.toString()); // 標記為已註冊
        } else {
          debugPrint('[ChatService] 用戶註冊失敗: $message');
          // 註冊失敗時從已註冊列表中移除（如果存在）
          if (userId != null) {
            _registeredUsers.remove(userId.toString());
          }
        }
        notifyListeners();
        break;
    }
  }

  // 處理連線狀態變化
  void _handleConnectionChange(bool connected) {
    _isConnected = connected;
    _connectionStateController.add(connected); // 通知 Stream
    if (!connected) {
      // 連線斷開時清空當前房間和已註冊用戶列表
      _currentRoom = null;
      _registeredUsers.clear(); // 清空已註冊用戶，重連時需要重新註冊
      debugPrint('[ChatService] 連線斷開，已清空註冊狀態');
    } else {
      // 連線成功時自動重新註冊當前用戶
      if (_currentUser.isNotEmpty) {
        debugPrint('[ChatService] 連線成功，自動重新註冊用戶: $_currentUser');
        // 使用 Future.microtask 確保註冊在連線完全建立後執行
        Future.microtask(() => ensureUserRegistered(_currentUser));
      }
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
    
    // 設置超時，以防伺服器沒有回應 (15秒)
    Future.delayed(const Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        debugPrint('[ChatService] 創建房間 $name 超時 (15秒)');
        _webSocketService.removeMessageListener(handler);
        completer.complete(null);
      }
    });
    
    return completer.future;
  }

  // 加入房間，伺服器回傳 joined_room（添加防呆機制）
  final Map<String, Completer<bool>> _joinRoomCompleters = {};
  
  Future<bool> joinRoom(String roomId) async {
    // 防呆：檢查是否已加入此房間
    if (_joinedRooms.contains(roomId)) {
      debugPrint('[ChatService] 房間 $roomId 已加入，跳過重複 join');
      // 已經加入的房間不需要再次獲取歷史記錄，因為我們在進入聊天室之前已經獲取了
      return true;
    }
    
    // 防呆：檢查是否正在加入此房間
    if (_joinRoomCompleters.containsKey(roomId)) {
      debugPrint('[ChatService] 房間 $roomId 正在加入中，等待完成');
      return _joinRoomCompleters[roomId]!.future;
    }
    
    debugPrint('[ChatService] 正在加入房間: $roomId');
    final completer = Completer<bool>();
    _joinRoomCompleters[roomId] = completer;
    
    // 預先將房間標記為已加入，避免同時發起多個加入請求
    _joinedRooms.add(roomId);
    
    void handler(Map<String, dynamic> data) {
      if (data['type'] == 'joined_room' && data['roomId'] == roomId) {
        _webSocketService.removeMessageListener(handler);
        debugPrint('[ChatService] 收到 joined_room 回應: $roomId');
        
        // 完成 completer 並從 map 中移除
        if (_joinRoomCompleters.containsKey(roomId)) {
          _joinRoomCompleters[roomId]!.complete(true);
          _joinRoomCompleters.remove(roomId);
          
          // 不再自動獲取聊天歷史記錄，因為我們已經在進入聊天室之前先獲取了
        }
      }
    }
    
    _webSocketService.addMessageListener(handler);
    _webSocketService.sendMessage({
      'type': 'join_room',
      'roomId': roomId,
    });
    
    // 設置超時，以防伺服器沒有回應 (增加到15秒給服務器更多時間)
    Future.delayed(const Duration(seconds: 15), () {
      if (_joinRoomCompleters.containsKey(roomId) && !completer.isCompleted) {
        debugPrint('[ChatService] 加入房間 $roomId 超時 (15秒)');
        _joinRoomCompleters.remove(roomId);
        completer.complete(false);
      }
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
    
    // 設置超時，以防伺服器沒有回應 (10秒，離開房間通常比較快)
    Future.delayed(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        debugPrint('[ChatService] 離開房間 $roomId 超時 (10秒)');
        _webSocketService.removeMessageListener(handler);
        completer.complete(false);
      }
    });
    
    return completer.future;
  }

  // 確保房間對象存在
  void _ensureRoomExists(String roomId) {
    // 檢查是否已經存在該房間
    final existingRoom = _chatRooms.where((room) => room.id == roomId).toList();
    if (existingRoom.isEmpty) {
      // 如果房間不存在，創建一個新的房間對象
      final newRoom = ChatRoom(
        id: roomId,
        name: roomId, // 可以根據需要設置更好的名稱
        participants: [], // 暫時為空，後續可以填充
        createdAt: DateTime.now(),
      );
      _chatRooms.add(newRoom);
      debugPrint('[ChatService] 創建新房間對象: $roomId');
    }
    
    // 🔄 設置為當前房間（如果當前沒有房間或需要切換）
    final room = _chatRooms.firstWhere((r) => r.id == roomId);
    if (_currentRoom == null || _currentRoom!.id != roomId) {
      _currentRoom = room;
      debugPrint('[ChatService] 設置當前房間: $roomId');
      notifyListeners();
    }
  }

  // 使用 HTTP 獲取聊天歷史記錄
  Future<void> fetchChatHistoryHttp(String roomId) async {
    debugPrint('[ChatService] 使用 HTTP 請求聊天室 $roomId 的歷史記錄');
    
    // 檢查是否已經獲取過歷史記錄，如果是則跳過
    if (_fetchedHistoryRooms.contains(roomId)) {
      debugPrint('[ChatService] 聊天室 $roomId 的歷史記錄已經獲取過，跳過重複獲取');
      return;
    }
    
    // 確保房間對象存在
    _ensureRoomExists(roomId);
    
    try {
      // 使用 UserApiService 獲取聊天記錄
      final chatHistory = await _friendService.getChatHistory(roomId);
      
      // 檢查聊天記錄是否有效
      if (chatHistory != null && chatHistory.isNotEmpty) {
        debugPrint('[ChatService] HTTP 收到聊天室 $roomId 的歷史記錄，共 ${chatHistory.length} 條訊息');
        
        // 清空該房間的訊息列表
        _clearRoomMessages(roomId);
        final roomMessages = _getOrCreateRoomMessages(roomId);
        
        // 處理聊天歷史記錄
        for (final messageData in chatHistory) {
          final messageId = messageData['id']?.toString() ?? '';
          
          // 防重複：檢查是否已處理過此訊息
          if (!_processedMessages.contains(messageId)) {
            final message = ChatMessage(
              id: messageId,
              type: messageData['type'] ?? 'text',
              content: messageData['content'] ?? '',
              sender: messageData['sender'] ?? '',
              timestamp: DateTime.tryParse(messageData['timestamp'] ?? '') ?? DateTime.now(),
              imageUrl: messageData['image_url'],
            );
            
            roomMessages.add(message);
            _processedMessages.add(messageId);
            debugPrint('[ChatService] 添加歷史訊息到房間 $roomId: ${message.content}');
          }
        }
        
        // 標記該房間歷史記錄已獲取
        _fetchedHistoryRooms.add(roomId);
        
        // 通知 UI 更新
        notifyListeners();
        
        // 將消息保存到本地儲存空間
        _saveMessagesToLocalStorage(roomId);
      } else if (chatHistory != null && chatHistory.isEmpty) {
        debugPrint('[ChatService] 聊天室 $roomId 的歷史記錄為空');
        // 清空該房間的訊息列表
        _clearRoomMessages(roomId);
        
        // 標記該房間歷史記錄已獲取（即使為空）
        _fetchedHistoryRooms.add(roomId);
        
        // 通知 UI 更新
        notifyListeners();
      } else {
        debugPrint('[ChatService] 歷史記錄獲取失敗或為 null，嘗試從本地儲存加載');
        await _loadMessagesFromLocalStorage(roomId);
      }
    } catch (e) {
      debugPrint('[ChatService] HTTP 獲取聊天記錄錯誤: $e，嘗試從本地儲存加載');
      await _loadMessagesFromLocalStorage(roomId);
    }
  }

  // 獲取聊天歷史記錄
  Future<void> fetchChatHistory(String roomId) async {
    // 直接調用 HTTP 方法，移除 WebSocket 實現
    return fetchChatHistoryHttp(roomId);
  }
  
  // 將聊天訊息保存到本地儲存空間
  Future<void> _saveMessagesToLocalStorage(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> historyJson = [];
    
    // 獲取該房間的所有消息
    final roomMessages = _roomMessages[roomId] ?? [];
    for (final message in roomMessages) {
      historyJson.add(jsonEncode(message.toJson()));
    }
    
    await prefs.setStringList('chat_history_$roomId', historyJson);
    debugPrint('[ChatService] 已保存聊天室 $roomId 的歷史記錄到本地，共 ${historyJson.length} 條訊息');
    
    // 如果有訊息，更新最後一條訊息
    if (roomMessages.isNotEmpty) {
      final lastMessage = roomMessages.last;
      
      // 更新聊天室資訊
      await _updateChatRoomInfo(roomId, lastMessage);
    }
  }

  // 從本地儲存加載聊天記錄
  Future<void> _loadMessagesFromLocalStorage(String roomId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final roomHistoryJson = prefs.getStringList('chat_history_$roomId') ?? [];
      
      debugPrint('[ChatService] 從本地儲存加載聊天室 $roomId 的歷史記錄，共 ${roomHistoryJson.length} 條訊息');
      
      // 顯示本地儲存的所有 key，幫助調試
      final allKeys = prefs.getKeys().where((key) => key.startsWith('chat_history_'));
      debugPrint('[ChatService] 本地儲存的聊天記錄 keys: ${allKeys.toList()}');
      
      // 清空該房間的訊息列表
      _clearRoomMessages(roomId);
      final roomMessages = _getOrCreateRoomMessages(roomId);
      debugPrint('[ChatService] 已清空房間 $roomId 的訊息列表');
      
      // 加載本地訊息
      int loadedCount = 0;
      for (final messageJson in roomHistoryJson) {
        try {
          final messageData = jsonDecode(messageJson);
          final messageId = messageData['id']?.toString() ?? '';
          
          debugPrint('[ChatService] 嘗試加載訊息: id=$messageId, content=${messageData['content']}');
          
          // 防重複：檢查是否已處理過此訊息
          if (!_processedMessages.contains(messageId)) {
            final message = ChatMessage(
              id: messageId,
              type: messageData['type'] ?? 'text',
              content: messageData['content'] ?? '',
              sender: messageData['sender'] ?? '',
              timestamp: DateTime.tryParse(messageData['timestamp'] ?? '') ?? DateTime.now(),
              imageUrl: messageData['imageUrl'],
            );
            
            roomMessages.add(message);
            _processedMessages.add(messageId);
            loadedCount++;
            debugPrint('[ChatService] 成功加載訊息到房間 $roomId: ${message.content}');
          } else {
            debugPrint('[ChatService] 跳過重複訊息: $messageId');
          }
        } catch (e) {
          debugPrint('[ChatService] 解析本地訊息錯誤: $e，原始數據: $messageJson');
        }
      }
      
      // 通知 UI 更新
      notifyListeners();
      
      debugPrint('[ChatService] 從本地儲存加載完成，實際加載 $loadedCount 條訊息，總共 ${roomMessages.length} 條訊息');
    } catch (e) {
      debugPrint('[ChatService] 從本地儲存加載聊天記錄錯誤: $e');
    }
  }

  // 傳送聊天訊息
  void sendTextMessage(String roomId, String sender, String content, {String? imageUrl}) async {
    // 獲取當前用戶 ID
    final userId = await getCurrentUserId();
    
    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
    final timestamp = DateTime.now().toUtc();
    
    final message = {
      'type': 'message',
      'id': messageId, // id 欄位作為訊息的唯一識別碼
      'sender': userId, // sender 使用用戶 ID (string)
      'roomId': roomId,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'imageUrl': imageUrl, // 如果沒有圖片會是 null
    };
    
    final messageObj = ChatMessage(
      id: messageId,
      type: 'text',
      content: content,
      sender: userId,
      timestamp: timestamp,
      imageUrl: imageUrl,
    );
    
    // 立即添加到當前房間的訊息列表（樂觀更新）
    final roomMessages = _getOrCreateRoomMessages(roomId);
    roomMessages.add(messageObj);
    _processedMessages.add(messageId); // 記錄已處理的訊息，避免重複
    
    // 儲存訊息到本地儲存空間
    await _saveMessageToLocalStorage(roomId, messageObj);
    
    // 立即更新UI
    notifyListeners();
    
    debugPrint('ChatService: 發送聊天訊息到伺服器 - $message');
    debugPrint('ChatService: 已立即添加訊息到房間 $roomId，內容: $content');
    _webSocketService.sendMessage(message);
  }
  
  // ===== AI 聊天功能 =====
  
  /// 發送 AI 訊息
  /// 當用戶觸發 AI 功能時調用此方法
  Future<void> sendAIMessage(String roomId, String userMessage) async {
    try {
      debugPrint('[ChatService] 🤖 開始處理 AI 訊息: $userMessage');
      
      // 檢查 API Key 是否已配置
      if (!_geminiService.isApiKeyConfigured) {
        await _sendAIResponse(roomId, '❌ 請先在 Gemini Service 中設定您的 API Key');
        return;
      }
      
      // 獲取聊天歷史作為上下文
      final context = await _buildContextFromHistory(roomId);
      
      // 🔄 使用前端 Gemini Service 而不是後端 API
      final aiResponse = await _geminiService.sendMessage(
        userMessage,
        context: context,
        roomId: roomId,
      );
      
      // 處理 AI 回應
      if (aiResponse.isNotEmpty) {
        // 直接發送 AI 回應
        await _sendAIResponse(roomId, aiResponse);
      } else {
        // 如果回應為空，顯示錯誤訊息
        await _sendAIResponse(roomId, '❌ AI 服務暫時無法使用，請稍後再試。');
      }
      
    } catch (e) {
      debugPrint('❌ [ChatService] AI 訊息發送失敗: $e');
      await _sendAIResponse(roomId, '❌ AI 服務發生錯誤：$e');
    }
  }
  
  /// 構建聊天歷史上下文
  Future<String> _buildContextFromHistory(String roomId) async {
    final messages = _getOrCreateRoomMessages(roomId);
    final currentUser = await getCurrentUserId();
    
    // 從房間ID提取對方用戶ID (格式: room_user1_user2)
    String otherUserId = '';
    final roomParts = roomId.split('_');
    if (roomParts.length >= 3) {
      final user1 = roomParts[1];
      final user2 = roomParts[2];
      otherUserId = (user1 == currentUser) ? user2 : user1;
    }
    
    // 從房間 ID 中提取用戶 ID
    final userIds = _extractUserIdsFromRoomId(roomId);
    
    // 獲取雙方用戶資料
    String userContexts = '';
    if (userIds.isNotEmpty) {
      try {
        final userProfiles = await Future.wait([
          for (final userId in userIds) _profileService.getUserProfile(userId)
        ]);
        
        final userContextList = <String>[];
        for (int i = 0; i < userIds.length && i < userProfiles.length; i++) {
          final userId = userIds[i];
          final profile = userProfiles[i];
          if (profile != null) {
            // 使用"你"和"他"標識用戶
            String userLabel;
            if (userId == currentUser) {
              userLabel = '你';
            } else if (userId == otherUserId) {
              userLabel = '他';
            } else {
              userLabel = '對方';
            }
            userContextList.add(_buildUserProfileContext(userLabel, profile));
          }
        }
        
        if (userContextList.isNotEmpty) {
          userContexts = '聊天室參與者資料：\n${userContextList.join('\n\n')}\n\n';
        }
      } catch (e) {
        debugPrint('[ChatService] 獲取用戶資料失敗: $e');
        // 繼續處理，即使沒有用戶資料
      }
    }
    
    // 只取最近 5 條非 AI 訊息作為上下文
    final recentMessages = messages
        .where((msg) => !msg.sender.startsWith('ai_'))
        .take(5)
        .map((msg) {
          // 將用戶ID轉換為"你"和"他"
          String senderLabel;
          if (msg.sender == currentUser) {
            senderLabel = '你';
          } else if (msg.sender == otherUserId) {
            senderLabel = '他';
          } else {
            senderLabel = '對方'; // 備用，如果ID不匹配
          }
          return '$senderLabel: ${msg.content}';
        })
        .join('\n');
    
    final messageContext = recentMessages.isNotEmpty 
        ? '最近的對話內容：\n$recentMessages'
        : '這是一個新的聊天室對話。';
    
    return '$userContexts$messageContext';
  }
  
  // 從房間 ID 中提取用戶 ID
  List<String> _extractUserIdsFromRoomId(String roomId) {
    if (roomId.startsWith('room_')) {
      final parts = roomId.substring(5).split('_'); // 移除 'room_' 前綴
      if (parts.length >= 2) {
        return [parts[0], parts[1]];
      }
    }
    return [];
  }
  
  // 構建用戶資料上下文
  String _buildUserProfileContext(String userLabel, Map<String, dynamic> profile) {
    final nickname = profile['nickname'] ?? '';
    final gender = _getGenderText(profile['gender']);
    final age = profile['age'] != null ? '${profile['age']}歲' : '年齡未知';
    
    String context = '$userLabel：\n- 性別：$gender\n- 年齡：$age';
    
    // 如果有暱稱且不同於標籤，則顯示暱稱
    if (nickname.isNotEmpty && nickname != userLabel) {
      context = '$userLabel（暱稱：$nickname）：\n- 性別：$gender\n- 年齡：$age';
    }
    
    // 添加興趣愛好
    if (profile['hobbies'] != null && (profile['hobbies'] as List).isNotEmpty) {
      final hobbies = (profile['hobbies'] as List)
          .map((hobby) => hobby['name'] ?? '未知')
          .join('、');
      context += '\n- 興趣愛好：$hobbies';
    }
    
    // 添加自定義興趣描述
    if (profile['custom_hobby_description'] != null &&
        profile['custom_hobby_description'].toString().isNotEmpty) {
      context += '\n- 其他興趣：${profile['custom_hobby_description']}';
    }
    
    return context;
  }
  
  // 獲取性別文字
  String _getGenderText(String? gender) {
    switch (gender) {
      case 'male':
        return '男性';
      case 'female':
        return '女性';
      case 'other':
        return '其他';
      default:
        return '未設定';
    }
  }
  
  /// 發送 AI 回應訊息
  Future<void> _sendAIResponse(String roomId, String response) async {
    final messageId = 'ai_${DateTime.now().millisecondsSinceEpoch}';
    final timestamp = DateTime.now().toUtc();
    
    final aiMessage = ChatMessage(
      id: messageId,
      type: 'text',
      content: response,
      sender: 'ai_assistant',
      timestamp: timestamp,
      imageUrl: null,
    );
    
    // 添加到本地訊息列表
    final roomMessages = _getOrCreateRoomMessages(roomId);
    roomMessages.add(aiMessage);
    
    // 儲存到本地儲存
    await _saveMessageToLocalStorage(roomId, aiMessage);
    
    // 通知 UI 更新
    notifyListeners();
    
    debugPrint('[ChatService] 🤖 AI 回應已發送: ${response.substring(0, response.length > 50 ? 50 : response.length)}...');
  }
  
  /// 生成回覆建議
  Future<String> generateReplySuggestion(String roomId, String conversationContext, String currentUser) async {
    try {
      debugPrint('[ChatService] 🤖 開始生成回覆建議');
      
      // 檢查 API Key 是否已配置
      if (!_geminiService.isApiKeyConfigured) {
        throw Exception('請先在 Gemini Service 中設定您的 API Key');
      }
      
      // 從房間ID提取雙方用戶ID (格式: room_user1_user2)
      String otherUserId = '';
      final roomParts = roomId.split('_');
      if (roomParts.length >= 3) {
        final user1 = roomParts[1];
        final user2 = roomParts[2];
        otherUserId = (user1 == currentUser) ? user2 : user1;
      }
      
      // 分析對話中的角色和最新訊息
      final messages = getMessagesForRoom(roomId);
      
      // 如果沒有對話內容或者明確要求生成問候語
      if (messages.isEmpty || conversationContext.contains('問候語')) {
        // 獲取雙方用戶資料來生成個性化問候語
        Map<String, dynamic>? currentUserProfile;
        Map<String, dynamic>? otherUserProfile;
        
        try {
          final futures = await Future.wait([
            _profileService.getUserProfile(currentUser),
            otherUserId.isNotEmpty ? _profileService.getUserProfile(otherUserId) : Future.value(null),
          ]);
          currentUserProfile = futures[0];
          otherUserProfile = futures[1];
        } catch (e) {
          debugPrint('[ChatService] 獲取用戶資料失敗: $e');
        }
        
        // 生成基於雙方用戶資料的友善問候語
        String greetingPrompt = '''
你是一個智能助手，請為用戶 "$currentUser" 生成一條友善的問候語來開始新的對話。

## 用戶資料：
${_buildUserInfoForPrompt(currentUserProfile, '當前用戶 ($currentUser)')}

${_buildUserInfoForPrompt(otherUserProfile, '對方用戶 ($otherUserId)')}

## 要求：
1. 語氣要親切自然
2. 基於雙方的資料（興趣愛好、年齡等），讓問候語更加個性化
3. 如果雙方有共同興趣，可以適當提及
4. 適合用於開始聊天
5. 使用繁體中文
6. 簡潔明了
7. 直接輸出問候語內容，不要包含任何前綴、說明或格式標記

請生成個性化問候語：
''';
        
        final greeting = await _geminiService.sendMessage(greetingPrompt);
        debugPrint('[ChatService] ✅ 成功生成問候語: $greeting');
        return greeting.trim();
      }
      
      // 並行獲取雙方用戶資料
      Map<String, dynamic>? currentUserProfile;
      Map<String, dynamic>? otherUserProfile;
      
      try {
        final futures = await Future.wait([
          _profileService.getUserProfile(currentUser),
          otherUserId.isNotEmpty ? _profileService.getUserProfile(otherUserId) : Future.value(null),
        ]);
        currentUserProfile = futures[0];
        otherUserProfile = futures[1];
      } catch (e) {
        debugPrint('[ChatService] 獲取用戶資料時發生錯誤: $e');
      }
      
      // 取得最近的非 AI 訊息，找出對話對象
      final recentNonAIMessages = messages
          .where((msg) => !msg.sender.startsWith('ai_'))
          .take(10)
          .toList();
      
      // 找出對話中的其他參與者
      final otherParticipants = recentNonAIMessages
          .map((msg) => msg.sender)
          .where((sender) => sender != currentUser)
          .toSet()
          .toList();
      
      // 構建更詳細的對話上下文
      String detailedContext = '';
      for (final msg in recentNonAIMessages.reversed.take(8)) {
        if (msg.sender == currentUser) {
          detailedContext += '我: ${msg.content}\n';
        } else {
          detailedContext += '${msg.sender}: ${msg.content}\n';
        }
      }
      
      // 構建包含雙方用戶資料的回覆建議提示詞
      final prompt = '''
你是一個智能助手，請幫助用戶 "$currentUser" 生成合適的回覆建議。

## 用戶資料：
${_buildUserInfoForPrompt(currentUserProfile, '當前用戶 ($currentUser)')}

${_buildUserInfoForPrompt(otherUserProfile, '對方用戶 ($otherUserId)')}

## 對話背景：
- 我是: $currentUser
- 對話參與者: ${otherParticipants.join(', ')}
- 這是一個聊天室對話

## 最近的對話內容（按時間順序）：
$detailedContext

## 任務要求：
1. 請站在 "$currentUser" 的角度，生成一個合適的回覆
2. 基於雙方的資料（年齡、興趣、性別等），讓回覆更加個性化和有針對性
3. 如果對方有特定興趣，可以適當引用或提及相關話題
4. 回覆應該自然、友善，符合對話語境和雙方的背景
5. 考慮對話的情緒和主題
6. 回覆長度適中，不要太長或太短
7. 直接輸出回覆內容，不要包含任何前綴、說明或格式標記

請生成個性化的回覆建議：
''';
      
      // 使用 Gemini 生成回覆建議
      final suggestion = await _geminiService.sendMessage(prompt);
      
      debugPrint('[ChatService] ✅ 成功生成個性化回覆建議: ${suggestion.substring(0, suggestion.length > 50 ? 50 : suggestion.length)}...');
      return suggestion.trim();
      
    } catch (e) {
      debugPrint('❌ [ChatService] 生成回覆建議失敗: $e');
      throw Exception('生成回覆建議失敗: $e');
    }
  }
  
  /// 構建用戶資料的 prompt 字符串
  String _buildUserInfoForPrompt(Map<String, dynamic>? userProfile, String label) {
    if (userProfile == null) {
      return '$label: 資料獲取中或無可用資料';
    }
    
    final nickname = userProfile['nickname'] ?? '未知';
    final age = userProfile['age']?.toString() ?? '未知';
    final gender = _getGenderText(userProfile['gender']);
    
    String info = '$label: $nickname (年齡: $age, 性別: $gender)';
    
    // 添加興趣愛好
    if (userProfile['hobbies'] != null && (userProfile['hobbies'] as List).isNotEmpty) {
      final hobbies = (userProfile['hobbies'] as List)
          .map((hobby) => hobby['name'] ?? '未知')
          .join(', ');
      info += '\n興趣愛好: $hobbies';
    }
    
    // 添加自定義興趣描述
    if (userProfile['custom_hobby_description'] != null &&
        userProfile['custom_hobby_description'].toString().isNotEmpty) {
      info += '\n其他興趣: ${userProfile['custom_hobby_description']}';
    }
    
    return info;
  }
  
  /// 檢查訊息是否應該觸發 AI
  bool shouldTriggerAI(String message) {
    // AI 不再自動在聊天室中發送訊息，只提供生成和分析功能
    return false;
  }
  
  /// 設定 AI 個性
  void setAIPersonality(String personality) {
    _geminiService.setPersonality(personality);
    debugPrint('[ChatService] 🎭 AI 個性已切換至: $personality');
  }
  
  /// 獲取可用的 AI 個性
  List<String> getAvailableAIPersonalities() {
    return _geminiService.getAvailablePersonalities();
  }
  
  /// 獲取當前 AI 個性
  String getCurrentAIPersonality() {
    return _geminiService.currentPersonality;
  }
  
  /// 生成聊天總結
  Future<String> generateChatSummary(String roomId) async {
    final messages = _getOrCreateRoomMessages(roomId);
    final currentUser = await getCurrentUserId();
    
    // 從房間ID提取對方用戶ID (格式: room_user1_user2)
    String otherUserId = '';
    final roomParts = roomId.split('_');
    if (roomParts.length >= 3) {
      final user1 = roomParts[1];
      final user2 = roomParts[2];
      otherUserId = (user1 == currentUser) ? user2 : user1;
    }
    
    final messageTexts = messages
        .where((msg) => !msg.sender.startsWith('ai_'))
        .map((msg) {
          // 將用戶ID轉換為"你"和"他"
          String senderLabel;
          if (msg.sender == currentUser) {
            senderLabel = '你';
          } else if (msg.sender == otherUserId) {
            senderLabel = '他';
          } else {
            senderLabel = '對方'; // 備用，如果ID不匹配
          }
          return '$senderLabel: ${msg.content}';
        })
        .toList();
    
    if (messageTexts.isEmpty) {
      return '暫無對話內容可總結';
    }
    
    try {
      // 使用前端 Gemini Service
      final summary = await _geminiService.summarizeConversation(messageTexts);
      return summary;
    } catch (e) {
      debugPrint('[ChatService] 生成聊天總結失敗: $e');
      return '生成聊天總結時發生錯誤：$e';
    }
  }
  
  /// 生成情緒分析
  Future<String> generateEmotionAnalysis(String roomId, String conversationContext, String currentUser) async {
    try {
      debugPrint('[ChatService] 🤖 開始生成情緒分析');
      
      // 檢查 API Key 是否已配置
      if (!_geminiService.isApiKeyConfigured) {
        throw Exception('請先在 Gemini Service 中設定您的 API Key');
      }
      
      // 構建情緒分析的提示詞
      final prompt = '''
請對以下對話內容進行情緒分析，重點關注"你"和"他"的情緒狀態：

對話內容：
$conversationContext

請提供詳細的情緒分析，包括：
1. 整體對話氛圍（積極/消極/中性）
2. 主要參與者的情緒狀態
3. 情緒變化趨勢
4. 需要注意的情緒信號
5. 建議的溝通方式

請用繁體中文回應，分析要具體且有建設性：
''';
      
      // 使用 Gemini 生成情緒分析
      final analysis = await _geminiService.sendMessage(prompt);
      
      debugPrint('[ChatService] ✅ 成功生成情緒分析: ${analysis.substring(0, analysis.length > 50 ? 50 : analysis.length)}...');
      return analysis.trim();
      
    } catch (e) {
      debugPrint('❌ [ChatService] 生成情緒分析失敗: $e');
      throw Exception('生成情緒分析失敗: $e');
    }
  }
  
  /// 分析訊息情緒
  Future<String> analyzeMessageEmotion(String message) async {
    try {
      // 使用前端 Gemini Service
      final emotion = await _geminiService.analyzeEmotion(message);
      return emotion;
    } catch (e) {
      debugPrint('[ChatService] 分析情緒失敗: $e');
      return '分析情緒時發生錯誤：$e';
    }
  }
  
  /// 獲取智能回覆建議
  Future<List<String>> getSuggestedReplies(String lastMessage) async {
    try {
      // 使用前端 Gemini Service
      return await _geminiService.getSuggestedReplies(lastMessage);
    } catch (e) {
      debugPrint('[ChatService] 獲取回覆建議失敗: $e');
      return ['好的', '了解', '謝謝'];
    }
  }
  
  /// 檢查 AI 服務是否可用
  bool get isAIServiceAvailable => _geminiService.isApiKeyConfigured;
  
  // ===== AI 功能結束 =====
  
  /// 發送圖片消息
  /// 使用 HTTP 上傳圖片，然後通過 WebSocket 發送包含圖片 URL 的消息
  Future<bool> sendImageMessage(String roomId, String sender, String imagePath) async {
    try {
      debugPrint('ChatService: 開始上傳圖片 - $imagePath');
      
      // 🚧 臨時禁用圖片上傳功能
      // 原因：後端服務器尚未實現 /images/upload 端點
      debugPrint('ChatService: 圖片上傳功能暫時不可用 - 後端服務器尚未實現圖片上傳端點');
      return false;
      
      /* 
      // 原始圖片上傳邏輯（暫時註釋）
      // 1. 使用 HTTP 上傳圖片
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        debugPrint('ChatService: 圖片文件不存在 - $imagePath');
        return false;
      }
      
      // 2. 調用 ImageApiService 上傳圖片
      final imageId = await _imageApiService.uploadImage(imageFile);
      if (imageId.isEmpty) {
        debugPrint('ChatService: 圖片上傳失敗，返回空的 imageId');
        return false;
      }
      
      // 3. 生成圖片 URL
      final imageUrl = _imageApiService.getImageUrl(imageId);
      debugPrint('ChatService: 圖片上傳成功，imageId: $imageId, imageUrl: $imageUrl');
      
      // 4. 通過 WebSocket 發送包含圖片 URL 的消息
      sendTextMessage(roomId, sender, '', imageUrl: imageUrl);
      
      return true;
      */
    } catch (e) {
      debugPrint('ChatService: 發送圖片消息失敗 - $e');
      return false;
    }
  }
  
  // 儲存聊天室訊息到本地
  Future<void> _saveMessageToLocalStorage(String roomId, ChatMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 獲取該聊天室的歷史記錄
    final roomHistoryJson = prefs.getStringList('chat_history_$roomId') ?? [];
    
    // 將新訊息添加到歷史記錄
    roomHistoryJson.add(jsonEncode(message.toJson()));
    
    // 儲存更新後的歷史記錄
    await prefs.setStringList('chat_history_$roomId', roomHistoryJson);
    
    // 更新房間列表
    var roomIds = prefs.getStringList('room_ids') ?? [];
    if (!roomIds.contains(roomId)) {
      roomIds.add(roomId);
      await prefs.setStringList('room_ids', roomIds);
    }
    
    // 同時保存聊天室信息
    await _updateChatRoomInfo(roomId, message);
  }
  
  // 更新聊天室信息（包括最後一條消息）
  Future<void> _updateChatRoomInfo(String roomId, ChatMessage message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = await getCurrentUserId();
      
      // 嘗試取得聊天室信息
      final currentRooms = _chatRooms.where((room) => room.id == roomId).toList();
      if (currentRooms.isEmpty) return;
      
      final roomInfo = currentRooms.first;
      
      // 確定對方用戶ID
      final otherUserId = roomInfo.participants
          .firstWhere((p) => p != currentUserId, orElse: () => '');
      
      // 創建或更新聊天室歷史記錄
      final history = ChatRoomHistory(
        roomId: roomId,
        roomName: roomInfo.name,
        lastMessage: message.content,
        lastMessageTime: message.timestamp,
        otherUserId: otherUserId,
      );
      
      // 儲存聊天室歷史記錄
      await prefs.setString('chat_room_info_$roomId', jsonEncode(history.toJson()));
    } catch (e) {
      debugPrint('更新聊天室信息失敗: $e');
    }
  }

  // 離開當前聊天室
  void leaveCurrentRoom() {
    if (_currentRoom != null) {
      _webSocketService.sendMessage({
        'type': 'leave_room',
        'roomId': _currentRoom!.id,
        'user': _currentUser,
      });
      
      // 清空當前房間的訊息
      final currentRoomId = _currentRoom!.id;
      _currentRoom = null;
      _clearRoomMessages(currentRoomId);
      notifyListeners();
    }
  }

  // 斷開連線
  void disconnect() {
    _webSocketService.disconnect();
    _currentRoom = null;
    // 斷線時不需要清空所有房間的訊息，保留本地數據
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
  
  // 發送連接回應
  void sendConnectResponse(String fromUserId, String toUserId, bool accept) {
    final message = {
      'type': 'connect_response',
      'from': fromUserId,
      'to': toUserId,
      'accept': accept,
    };
    
    _webSocketService.sendMessage(message);
    debugPrint('[ChatService] Sent connect_response: from=$fromUserId to=$toUserId accept=$accept');
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

  // 取得當前用戶 ID
  Future<String> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? 'unknown_user';
  }

  // 確保用戶已註冊（在發送其他請求前調用）
  void ensureUserRegistered(String userId) {
    if (!_isConnected) {
      debugPrint('[ChatService] 無法註冊用戶，WebSocket 未連接: $userId');
      return;
    }
    
    // 檢查是否已經註冊過
    if (_registeredUsers.contains(userId)) {
      debugPrint('[ChatService] 用戶已註冊過，跳過重複註冊: $userId');
      return;
    }
    
    debugPrint('[ChatService] 開始用戶註冊: $userId');
    _webSocketService.sendMessage({
      'type': 'register_user',
      'userId': userId,
    });
    debugPrint('[ChatService] 已發送用戶註冊請求: $userId');
  }

  // 根據用戶 ID 獲取暱稱
  Future<String> getUserNickname(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 如果是當前用戶，返回保存的暱稱
    if (userId == _currentUser) {
      return prefs.getString('nickname') ?? userId;
    }
    
    // 從聊天室歷史中查找對方暱稱
    final historyJson = prefs.getStringList('chat_history') ?? [];
    for (final jsonStr in historyJson) {
      try {
        final data = Map<String, dynamic>.from(jsonDecode(jsonStr));
        if (data['otherUserId'] == userId && data.containsKey('otherNickname')) {
          return data['otherNickname'] ?? userId;
        }
      } catch (e) {
        debugPrint('獲取暱稱時出錯: $e');
      }
    }
    
    // 如果找不到暱稱，返回用戶 ID
    return userId;
  }

  // 根據房間 ID 獲取聊天室名稱（"與'對方暱稱'的聊天室"）
  Future<String> getChatRoomDisplayName(String roomId, String currentUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('chat_history') ?? [];
    
    for (final jsonStr in historyJson) {
      try {
        final data = Map<String, dynamic>.from(jsonDecode(jsonStr));
        if (data['roomId'] == roomId) {
          final otherUserId = data['otherUserId'] ?? '';
          final otherNickname = data['otherNickname'] ?? await getUserNickname(otherUserId);
          return '與\'$otherNickname\'的聊天室';
        }
      } catch (e) {
        debugPrint('獲取聊天室名稱時出錯: $e');
      }
    }
    
    return '聊天室 $roomId';
  }

  // 生成房間 ID
  String generateRoomId(String user1, String user2) {
    final sortedUsers = [user1, user2]..sort();
    return 'room_${sortedUsers[0]}_${sortedUsers[1]}';
  }

  // 添加連接回應監聽器
  void addConnectResponseListener(void Function(String from, String to, bool accept) listener) {
    _connectResponseListeners.add(listener);
  }
  
  // 移除連接回應監聽器
  void removeConnectResponseListener(void Function(String from, String to, bool accept) listener) {
    _connectResponseListeners.remove(listener);
  }

  // 添加連接請求監聽器
  void addConnectRequestListener(void Function(String from, String to) listener) {
    _connectRequestListeners.add(listener);
  }
  
  // 移除連接請求監聽器
  void removeConnectRequestListener(void Function(String from, String to) listener) {
    _connectRequestListeners.remove(listener);
  }

  // 觸發連接請求
  void triggerConnectRequest(String fromUser, String toUser) {
    // 通知所有全局連接請求監聽器
    for (var listener in _connectRequestListeners) {
      listener(fromUser, toUser);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    // 移除所有監聽器
    _webSocketService.removeMessageListener(_handleMessage);
    _webSocketService.removeConnectionListener(_handleConnectionChange);
    
    // 清理所有等待中的 completer
    for (final completer in _joinRoomCompleters.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    _joinRoomCompleters.clear();
    
    // 關閉 StreamController
    _connectionStateController.close();
    
    // 清理 WebSocket 連接
    _webSocketService.dispose();
    super.dispose();
  }
}
