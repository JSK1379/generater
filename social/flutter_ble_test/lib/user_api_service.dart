import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'dart:convert';

class UserApiService {
  final String wsUrl;
  WebSocketChannel? _channel;

  UserApiService(this.wsUrl);

  Future<void> uploadUserId(String userId) async {
    _channel ??= WebSocketChannel.connect(Uri.parse(wsUrl));
    final msg = jsonEncode({
      'type': 'register_user',
      'user_id': userId,
    });
    _channel!.sink.add(msg);
    // 不等待回應，單向上傳
  }

  Future<void> uploadAvatar(String userId, String base64Image) async {
    _channel ??= WebSocketChannel.connect(Uri.parse(wsUrl));
    final msg = jsonEncode({
      'type': 'update_avatar',
      'user_id': userId,
      'avatar': base64Image,
    });
    _channel!.sink.add(msg);
    // 不等待回應，單向上傳
  }

  void dispose() {
    _channel?.sink.close(status.goingAway);
    _channel = null;
  }
}
