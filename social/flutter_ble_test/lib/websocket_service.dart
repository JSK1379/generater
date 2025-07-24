import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';

class WebSocketService {
  WebSocket? _socket;
  final List<Function(Map<String, dynamic>)> _messageListeners = [];
  final List<Function(bool)> _connectionListeners = [];
  bool _isConnected = false;
  String? _currentUrl;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  Timer? _heartbeatTimer;
  
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
      debugPrint('[WebSocket] 開始連接: $url');
      _currentUrl = url;
      
      // 創建 WebSocket 連接，增加超時處理
      _socket = await WebSocket.connect(
        url,
        headers: {
          'User-Agent': 'Flutter-App/1.0',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[WebSocket] 連接超時');
          throw Exception('WebSocket connection timeout');
        },
      );
      
      _isConnected = true;
      _reconnectAttempts = 0;
      
      // 通知連線狀態監聽器
      for (final listener in List<Function(bool)>.from(_connectionListeners)) {
        listener(true);
      }

      // 添加監聽器
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
            debugPrint('[WebSocket] 解析訊息錯誤: $e');
          }
        },
        onError: (error) {
          debugPrint('[WebSocket] 連線錯誤: $error');
          debugPrint('[WebSocket] 錯誤類型: ${error.runtimeType}');
          _handleDisconnection();
        },
        onDone: () {
          debugPrint('[WebSocket] 連線關閉 - 伺服器主動關閉連線');
          _handleDisconnection();
        },
      );

      debugPrint('[WebSocket] 連線成功: $url');
      
      // 啟動心跳機制（每30秒發送一次心跳）
      _startHeartbeat();
      
      return true;
    } catch (e) {
      debugPrint('[WebSocket] 連線失敗: $e');
      _handleDisconnection();
      return false;
    }
  }

  // 清理過期的已處理消息記錄
  void cleanupProcessedMessages() {
    final now = DateTime.now();
    _processedMessages.removeWhere((_, timestamp) {
      return now.difference(timestamp).inMinutes > 5; // 保留最近5分鐘的記錄
    });
  }

  // 處理斷線
  void _handleDisconnection() {
    debugPrint('[WebSocket] 處理斷線 - 當前連線狀態: $_isConnected');
    _isConnected = false;
    _stopHeartbeat(); // 停止心跳
    
    for (final listener in List<Function(bool)>.from(_connectionListeners)) {
      listener(false);
    }
    
    // 嘗試重連
    if (_reconnectAttempts < maxReconnectAttempts && _currentUrl != null) {
      _reconnectAttempts++;
      debugPrint('[WebSocket] 嘗試重連 ($_reconnectAttempts/$maxReconnectAttempts)...');
      Future.delayed(Duration(seconds: _reconnectAttempts * 2), () {
        if (!_isConnected) {
          debugPrint('[WebSocket] 執行重連...');
          connect(_currentUrl!);
        }
      });
    } else {
      debugPrint('[WebSocket] 已達到最大重連次數或沒有 URL，停止重連');
    }
  }

  // 啟動心跳機制
  void _startHeartbeat() {
    _stopHeartbeat(); // 先停止之前的心跳
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected && _socket != null) {
        try {
          debugPrint('[WebSocket] 發送心跳');
          _socket!.add(jsonEncode({'type': 'ping'}));
        } catch (e) {
          debugPrint('[WebSocket] 心跳發送失敗: $e');
          _handleDisconnection();
        }
      } else {
        _stopHeartbeat();
      }
    });
  }

  // 停止心跳機制
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // 發送訊息
  void sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _socket != null) {
      try {
        final jsonMessage = jsonEncode(message);
        debugPrint('[WebSocket] 發送訊息: $jsonMessage');
        _socket!.add(jsonMessage);
      } catch (e) {
        debugPrint('[WebSocket] 發送訊息失敗: $e');
      }
    } else {
      debugPrint('[WebSocket] 無法發送訊息，連線未建立');
    }
  }

  // 斷開連線
  void disconnect() {
    _stopHeartbeat(); // 停止心跳
    if (_socket != null) {
      _socket!.close();
      _socket = null;
    }
    _isConnected = false;
    for (final listener in List<Function(bool)>.from(_connectionListeners)) {
      listener(false);
    }
  }

  // 清理資源
  void dispose() {
    _stopHeartbeat(); // 停止心跳
    disconnect();
    _messageListeners.clear();
    _connectionListeners.clear();
    _processedMessages.clear();
  }
}
