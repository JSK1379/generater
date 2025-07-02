import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'dart:convert';

class UserApiService {
  final String wsUrl;
  WebSocketChannel? _channel;

  UserApiService(this.wsUrl);

  Future<void> uploadUserId(String userId) async {
    if (_channel == null) {
      try {
        _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      } catch (e) {
        return; // 無法連線時直接返回
      }
    }
    final msg = jsonEncode({
      'type': 'register_user',
      'user_id': userId,
    });
    try {
      _channel!.sink.add(msg);
    } catch (e) {
      // 連線失敗不處理
    }
    // 不等待回應，單向上傳
  }

  Future<void> uploadAvatar(String userId, String base64Image) async {
    if (_channel == null) {
      try {
        _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      } catch (e) {
        return; // 無法連線時直接返回
      }
    }
    final msg = jsonEncode({
      'type': 'update_avatar',
      'user_id': userId,
      'avatar': base64Image,
    });
    try {
      _channel!.sink.add(msg);
    } catch (e) {
      // 連線失敗不處理
    }
    // 不等待回應，單向上傳
  }

  void dispose() {
    _channel?.sink.close(status.goingAway);
    _channel = null;
  }
}
