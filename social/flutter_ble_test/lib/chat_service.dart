import 'dart:async';
import 'package:flutter/material.dart';
import 'websocket_service.dart';
import 'chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'user_api_service.dart';

class ChatService extends ChangeNotifier {
  final WebSocketService _webSocketService = WebSocketService();
  // 創建 UserApiService 實例，使用相同的 baseUrl
  final UserApiService _userApiService = UserApiService('https://near-ride-backend-api.onrender.com');
  WebSocketService get webSocketService => _webSocketService;
  final List<ChatMessage> _messages = [];
  final List<ChatRoom> _chatRooms = [];
  final Set<String> _joinedRooms = <String>{}; // 已加入的房間列表
  final Set<String> _processedMessages = <String>{}; // 已處理的訊息 ID 列表
  ChatRoom? _currentRoom;
  bool _isConnected = false;
  String _currentUser = '';
  
  // 連接請求回調監聽器
  final List<void Function(String from, String to, bool accept)> _connectResponseListeners = [];
  // 全局連接請求監聽器
  final List<void Function(String from, String to)> _connectRequestListeners = [];

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
    if (_currentUser != username) {
      _currentUser = username;
      // 使用 Future.microtask 確保通知不會在構建過程中觸發
      Future.microtask(() => notifyListeners());
    }
  }
  
  // 設定當前聊天室
  void setCurrentRoom(String roomId) {
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
        
        debugPrint('ChatService: 收到訊息 - $data');
        
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
        _messages.add(message);
        _processedMessages.add(messageId); // 記錄已處理的訊息
        debugPrint('ChatService: 新增聊天訊息 - ${message.content}');
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
          
          debugPrint('[ChatService] 成功加入房間: $roomId');
          
          // 添加到已加入房間集合
          _joinedRooms.add(roomId);
          
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
  final Map<String, Completer<bool>> _joinRoomCompleters = {};
  
  Future<bool> joinRoom(String roomId) async {
    // 防呆：檢查是否已加入此房間
    if (_joinedRooms.contains(roomId)) {
      debugPrint('[ChatService] 房間 $roomId 已加入，跳過重複 join');
      // 即使已經加入，仍然請求一次聊天歷史記錄
      fetchChatHistory(roomId);
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
    
    // 設置超時，以防伺服器沒有回應
    Future.delayed(const Duration(seconds: 5), () {
      if (_joinRoomCompleters.containsKey(roomId) && !completer.isCompleted) {
        debugPrint('[ChatService] 加入房間 $roomId 超時');
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
    return completer.future;
  }

  // 使用 HTTP 獲取聊天歷史記錄
  Future<void> fetchChatHistoryHttp(String roomId) async {
    debugPrint('[ChatService] 使用 HTTP 請求聊天室 $roomId 的歷史記錄');
    
    try {
      // 使用 UserApiService 獲取聊天記錄
      final chatHistory = await _userApiService.getChatHistory(roomId);
      
      // 檢查聊天記錄是否有效
      if (chatHistory != null && chatHistory.isNotEmpty) {
        debugPrint('[ChatService] HTTP 收到聊天室 $roomId 的歷史記錄，共 ${chatHistory.length} 條訊息');
        
        // 清空當前房間的訊息列表
        if (_currentRoom?.id == roomId) {
          _messages.clear();
        }
        
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
            
            _messages.add(message);
            _processedMessages.add(messageId);
            debugPrint('[ChatService] 添加歷史訊息: ${message.content}');
          }
        }
        
        // 通知 UI 更新
        notifyListeners();
        
        // 將消息保存到本地儲存空間
        _saveMessagesToLocalStorage(roomId);
      } else if (chatHistory != null && chatHistory.isEmpty) {
        debugPrint('[ChatService] 聊天室 $roomId 的歷史記錄為空');
        // 清空當前房間的訊息列表
        if (_currentRoom?.id == roomId) {
          _messages.clear();
        }
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
    
    // 篩選出屬於該房間的消息
    for (final message in _messages) {
      historyJson.add(jsonEncode(message.toJson()));
    }
    
    await prefs.setStringList('chat_history_$roomId', historyJson);
    debugPrint('[ChatService] 已保存聊天室 $roomId 的歷史記錄到本地，共 ${historyJson.length} 條訊息');
    
    // 如果有訊息，更新最後一條訊息
    if (_messages.isNotEmpty && _currentRoom != null) {
      final lastMessage = _messages.last;
      
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
      
      // 清空當前房間的訊息列表
      if (_currentRoom?.id == roomId) {
        _messages.clear();
        debugPrint('[ChatService] 已清空當前房間 $_currentRoom 的訊息列表');
      } else {
        debugPrint('[ChatService] 當前房間 $_currentRoom 與請求房間 $roomId 不匹配，不清空訊息');
      }
      
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
            
            _messages.add(message);
            _processedMessages.add(messageId);
            loadedCount++;
            debugPrint('[ChatService] 成功加載訊息: ${message.content}');
          } else {
            debugPrint('[ChatService] 跳過重複訊息: $messageId');
          }
        } catch (e) {
          debugPrint('[ChatService] 解析本地訊息錯誤: $e，原始數據: $messageJson');
        }
      }
      
      // 通知 UI 更新
      notifyListeners();
      
      debugPrint('[ChatService] 從本地儲存加載完成，實際加載 $loadedCount 條訊息，總共 ${_messages.length} 條訊息');
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
    
    // 儲存訊息到本地儲存空間
    await _saveMessageToLocalStorage(roomId, ChatMessage(
      id: messageId,
      type: 'text',
      content: content,
      sender: userId,
      timestamp: timestamp,
      imageUrl: imageUrl,
    ));
    
    debugPrint('ChatService: 發送聊天訊息到伺服器 - $message');
    _webSocketService.sendMessage(message);
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
    if (_isConnected) {
      _webSocketService.sendMessage({
        'type': 'register_user',
        'userId': userId,
      });
      debugPrint('[ChatService] 確保用戶已註冊: $userId');
    }
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
    
    // 清理 WebSocket 連接
    _webSocketService.dispose();
    super.dispose();
  }
}
