import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_service.dart';
import 'chat_page.dart';

const String kTestWsServerUrl = 'wss://near-ride-backend-api.onrender.com/ws';
const String kTestTargetUserId = '0000';


class TestTab extends StatefulWidget {
  const TestTab({super.key});

  @override
  State<TestTab> createState() => _TestTabState();
}

class _TestTabState extends State<TestTab> {
  String _wsLog = '';
  late final ChatService _chatService;

  @override
  void initState() {
    super.initState();
    _chatService = ChatService();
    _chatService.webSocketService.addMessageListener(_onWsMessage);
  }

  void _onWsMessage(Map<String, dynamic> data) {
    setState(() {
      _wsLog = data.toString();
    });
  }

  Future<void> _sendConnectRequest(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final myUserId = prefs.getString('user_id') ?? 'unknown_user';
    if (!_chatService.isConnected) {
      await _chatService.connect(kTestWsServerUrl, 'test_room', myUserId);
    }
    _chatService.sendConnectRequest(myUserId, kTestTargetUserId);
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
    if (!_chatService.isConnected) {
      await _chatService.connect(kTestWsServerUrl, 'test_room', myUserId);
    }
    final roomId = await _chatService.createRoom(roomName);
    debugPrint('[TestTab] createRoom 回傳的 roomId: $roomId');
    String joinMsg = '';
    if (roomId != null) {
      debugPrint('[TestTab] roomId 不為 null，準備 joinRoom');
      // 先導航到聊天室頁面，然後在背景執行 joinRoom
      debugPrint('[TestTab] 準備導航到 ChatPage');
      if (!context.mounted) return;
      debugPrint('[TestTab] context.mounted 通過，開始導航');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            roomId: roomId,
            roomName: roomName,
            currentUser: myUserId,
            chatService: _chatService,
          ),
        ),
      );
      debugPrint('[TestTab] Navigator.push 已執行');
      
      // 在背景執行 joinRoom
      _chatService.joinRoom(roomId).then((_) {
        debugPrint('[TestTab] joinRoom 完成');
      });
      joinMsg = '\n已自動發送 join_room: {"type": "join_room", "roomId": "$roomId"}';
      debugPrint('已請求建立聊天室: $roomName (roomId: $roomId)$joinMsg');
    } else {
      debugPrint('[TestTab] 建立聊天室失敗，roomId 為 null');
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已請求建立聊天室: $roomName (roomId: $roomId)$joinMsg')),
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
            const Text('伺服器回傳：', style: TextStyle(fontWeight: FontWeight.bold)),
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_wsLog, maxLines: 6, overflow: TextOverflow.ellipsis),
            ),
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
