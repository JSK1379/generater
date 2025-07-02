import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_service.dart';

const String kTestWsServerUrl = 'wss://near-ride-backend-api.onrender.com/ws';
const String kTestTargetUserId = '0000';

class TestTab extends StatelessWidget {
  const TestTab({super.key});

  Future<void> _sendConnectRequest(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final myUserId = prefs.getString('user_id') ?? 'unknown_user';
    final chatService = ChatService();
    if (!chatService.isConnected) {
      await chatService.connect(kTestWsServerUrl, 'test_room', myUserId);
    }
    chatService.sendConnectRequest(myUserId, kTestTargetUserId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已發送連接要求給 0000')),
    );
  }

  Future<void> _createRoom(BuildContext context) async {
    final roomName = await _showInputDialog(context, '請輸入聊天室名稱');
    if (roomName == null || roomName.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final myUserId = prefs.getString('user_id') ?? 'unknown_user';
    final chatService = ChatService();
    if (!chatService.isConnected) {
      await chatService.connect(kTestWsServerUrl, 'test_room', myUserId);
    }
    // 只傳聊天室名稱，讓 server 產生 roomId，並與 0000 用戶建立聊天室
    final roomId = await chatService.createRoom(roomName);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已請求建立聊天室: $roomName (roomId: $roomId)')),
    );
  }

  static Future<String?> _showInputDialog(BuildContext context, String title) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('確定')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('測試工具')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: () => _sendConnectRequest(context),
              child: const Text('創建連接要求（對 0000）'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _createRoom(context),
              child: const Text('創建聊天室（與 0000）'),
            ),
          ],
        ),
      ),
    );
  }
}
