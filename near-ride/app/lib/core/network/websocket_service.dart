import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

typedef WebSocketMessageListener = void Function(Map<String, dynamic> message);
typedef WebSocketConnectionListener = void Function(bool connected);

class WebSocketService {
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;

  final List<WebSocketMessageListener> _messageListeners = [];
  final List<WebSocketConnectionListener> _connectionListeners = [];
  final Map<String, DateTime> _processedMessages = {};

  bool _isConnected = false;
  bool _manualDisconnect = false;
  bool _connecting = false;
  String? _currentUrl;
  int _reconnectAttempts = 0;

  static const int maxReconnectAttempts = 5;
  static const Duration connectionTimeout = Duration(seconds: 15);
  static const Duration duplicateWindow = Duration(seconds: 10);

  bool get isConnected => _isConnected;

  void addMessageListener(WebSocketMessageListener listener) {
    if (!_messageListeners.contains(listener)) {
      _messageListeners.add(listener);
    }
  }

  void removeMessageListener(WebSocketMessageListener listener) {
    _messageListeners.remove(listener);
  }

  void addConnectionListener(WebSocketConnectionListener listener) {
    if (!_connectionListeners.contains(listener)) {
      _connectionListeners.add(listener);
    }
  }

  void removeConnectionListener(WebSocketConnectionListener listener) {
    _connectionListeners.remove(listener);
  }

  Future<bool> connect(String url) async {
    if (_isConnected && _currentUrl == url && _socket != null) {
      return true;
    }
    if (_connecting) {
      return false;
    }

    _manualDisconnect = false;
    _connecting = true;
    _currentUrl = url;
    _cancelReconnect();

    try {
      if (_socket != null) {
        await _closeSocket();
      }

      debugPrint('[WebSocket] connecting: $url');
      final socket = await WebSocket.connect(
        url,
        headers: const {'User-Agent': 'Near-Ride-Flutter/1.0'},
      ).timeout(connectionTimeout);

      _socket = socket;
      _reconnectAttempts = 0;
      _setConnected(true);

      _subscription = socket.listen(
        _handleRawMessage,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('[WebSocket] error: $error');
          _handleDisconnection();
        },
        onDone: _handleDisconnection,
        cancelOnError: false,
      );

      debugPrint('[WebSocket] connected: $url');
      return true;
    } catch (error) {
      debugPrint('[WebSocket] connect failed: $error');
      _setConnected(false);
      _scheduleReconnect();
      return false;
    } finally {
      _connecting = false;
    }
  }

  void _handleRawMessage(dynamic rawData) {
    try {
      final decoded = jsonDecode(rawData.toString());
      if (decoded is! Map<String, dynamic>) {
        debugPrint('[WebSocket] ignored non-object payload');
        return;
      }

      if (_isDuplicateJoinedRoom(decoded)) {
        return;
      }

      for (final listener in List<WebSocketMessageListener>.from(_messageListeners)) {
        listener(decoded);
      }
    } catch (error) {
      debugPrint('[WebSocket] decode failed: $error');
    }
  }

  bool _isDuplicateJoinedRoom(Map<String, dynamic> message) {
    if (message['type'] != 'joined_room' || message['roomId'] == null) {
      return false;
    }

    final key = 'joined_room:${message['roomId']}';
    final now = DateTime.now();
    final previous = _processedMessages[key];
    _processedMessages[key] = now;

    if (_processedMessages.length > 100) {
      _cleanupProcessedMessages(now);
    }

    return previous != null && now.difference(previous) < duplicateWindow;
  }

  void _cleanupProcessedMessages(DateTime now) {
    _processedMessages.removeWhere(
      (_, timestamp) => now.difference(timestamp) > const Duration(minutes: 5),
    );
  }

  void _handleDisconnection() {
    _setConnected(false);
    _socket = null;
    _subscription = null;

    if (!_manualDisconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_manualDisconnect ||
        _currentUrl == null ||
        _reconnectAttempts >= maxReconnectAttempts ||
        _reconnectTimer != null) {
      return;
    }

    _reconnectAttempts += 1;
    final delay = Duration(seconds: _reconnectAttempts * 2);
    debugPrint(
      '[WebSocket] reconnect $_reconnectAttempts/$maxReconnectAttempts in ${delay.inSeconds}s',
    );

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_isConnected && !_manualDisconnect && _currentUrl != null) {
        connect(_currentUrl!);
      }
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _setConnected(bool value) {
    if (_isConnected == value) return;
    _isConnected = value;
    for (final listener
        in List<WebSocketConnectionListener>.from(_connectionListeners)) {
      listener(value);
    }
  }

  void sendMessage(Map<String, dynamic> message) {
    final socket = _socket;
    if (!_isConnected || socket == null) {
      debugPrint('[WebSocket] send skipped: disconnected');
      return;
    }

    try {
      socket.add(jsonEncode(message));
    } catch (error) {
      debugPrint('[WebSocket] send failed: $error');
    }
  }

  Future<void> _closeSocket() async {
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }

    final socket = _socket;
    _socket = null;
    if (socket != null) {
      await socket.close();
    }
  }

  void disconnect() {
    _manualDisconnect = true;
    _cancelReconnect();
    _setConnected(false);

    final subscription = _subscription;
    _subscription = null;
    subscription?.cancel();

    final socket = _socket;
    _socket = null;
    socket?.close();
  }

  void dispose() {
    disconnect();
    _messageListeners.clear();
    _connectionListeners.clear();
    _processedMessages.clear();
  }
}
