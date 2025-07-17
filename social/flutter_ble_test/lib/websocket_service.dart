import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class WebSocketService {
  WebSocket? _socket;
  final List<Function(Map<String, dynamic>)> _messageListeners = [];
  final List<Function(bool)> _connectionListeners = [];
  bool _isConnected = false;
  String? _currentUrl;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  
  // 新增：用於防止重複處理相同的 'joined_room' 消息
  final Map<String, DateTime> _processedMessages = {};

  bool get isConnected => _isConnected;

  // 註冊訊息監聽器
  void addMessageListener(Function(Map<String, dynamic>) listener) {
    _messageListeners.add(listener);
  }

  // 註冊連線狀態監聽器
  void addConnectionListener(Function(bool) listener) {
    _connectionListeners.add(listener);
  }

  // 移除監聽器
  void removeMessageListener(Function(Map<String, dynamic>) listener) {
    _messageListeners.remove(listener);
  }

  void removeConnectionListener(Function(bool) listener) {
    _connectionListeners.remove(listener);
  }

  // 連接 WebSocket
  Future<bool> connect(String url) async {
    try {
      _currentUrl = url;
      _socket = await WebSocket.connect(url);
      _isConnected = true;
      _reconnectAttempts = 0;
      
      // 通知連線狀態監聽器
      for (final listener in List<Function(bool)>.from(_connectionListeners)) {
        listener(true);
      }

  // 清理過期的已處理消息記錄
  void cleanupProcessedMessages() {
    final now = DateTime.now();
    _processedMessages.removeWhere((_, timestamp) {
      return now.difference(timestamp).inMinutes > 5; // 保留最近5分鐘的記錄
    });
  }  // 添加監聽器
      _socket!.listen(
        (data) {
          try {
            debugPrint('[WebSocket] 收到原始資料: $data');
            final message = jsonDecode(data) as Map<String, dynamic>;
            
            // 檢查是否是 joined_room 消息，如果是，需要特殊處理防止重複
            final type = message['type'];
            final roomId = message['roomId'];
            
            if (type == 'joined_room' && roomId != null) {
              final messageId = '$type:$roomId';
              // 檢查最近是否處理過相同的消息（5秒內）
              final now = DateTime.now();
              final lastProcessed = _processedMessages[messageId];
              
              if (lastProcessed != null && now.difference(lastProcessed).inSeconds < 5) {
                debugPrint('[WebSocket] 跳過重複的 joined_room 消息: $roomId');
                return;
              }
              
              // 記錄此消息已被處理
              _processedMessages[messageId] = now;
              
              // 每分鐘清理一次過期的消息記錄
              if (_processedMessages.length > 100 || 
                  (_processedMessages.isNotEmpty && now.second == 0)) {
                cleanupProcessedMessages();
              }
            }
            
            // 通知所有監聽器
            for (final listener in List<Function(Map<String, dynamic>)>.from(_messageListeners)) {
              listener(message);
            }
          } catch (e) {
            debugPrint('解析訊息失敗: $e');
          }
        },
        onError: (error) {
          debugPrint('WebSocket 錯誤: $error');
          _handleDisconnection();
        },
        onDone: () {
          debugPrint('WebSocket 連線已關閉');
          _handleDisconnection();
        },
      );

      debugPrint('WebSocket 連線成功: $url');
      return true;
    } catch (e) {
      debugPrint('WebSocket 連線失敗: $e');
      _isConnected = false;
      for (final listener in _connectionListeners) {
        listener(false);
      }
      return false;
    }
  }

  // 處理斷線
  void _handleDisconnection() {
    _isConnected = false;
    for (final listener in List<Function(bool)>.from(_connectionListeners)) {
      listener(false);
    }
    
    // 嘗試重連
    if (_reconnectAttempts < maxReconnectAttempts && _currentUrl != null) {
      _reconnectAttempts++;
      debugPrint('嘗試重連 ($_reconnectAttempts/$maxReconnectAttempts)...');
      Future.delayed(Duration(seconds: _reconnectAttempts * 2), () {
        if (!_isConnected) {
          connect(_currentUrl!);
        }
      });
    }
  }

  // 發送訊息
  void sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _socket != null) {
      try {
        final jsonMessage = jsonEncode(message);
        debugPrint('[WebSocket] 發送訊息: $jsonMessage');
        _socket!.add(jsonMessage);
      } catch (e) {
        debugPrint('發送訊息失敗: $e');
      }
    } else {
      debugPrint('WebSocket 未連線，無法發送訊息');
    }
  }

  // 斷開連線
  void disconnect() {
    _socket?.close();
    _isConnected = false;
    _currentUrl = null;
    _reconnectAttempts = 0;
    for (final listener in List<Function(bool)>.from(_connectionListeners)) {
      listener(false);
    }
  }

  // 清理資源
  void dispose() {
    disconnect();
    _messageListeners.clear();
    _connectionListeners.clear();
  }
}
