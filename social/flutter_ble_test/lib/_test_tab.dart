import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'chat_service_singleton.dart';
import 'chat_page.dart';
import 'user_api_service.dart';

const String kTestWsServerUrl = 'wss://near-ride-backend-api.onrender.com/ws';
const String kTestTargetUserId = '0000';


class TestTab extends StatefulWidget {
  const TestTab({super.key});

  @override
  State<TestTab> createState() => _TestTabState();
}

class _TestTabState extends State<TestTab> {
  /// 連接後自動發送連接要求並創建聊天室
  Future<void> _connectAndCreateRoom(BuildContext context) async {
    if (!context.mounted) return;
    await _sendConnectRequest(context);
    if (!context.mounted) return;
    await _createRoom(context);
  }
  String _wsLog = '';
  String _currentUserId = 'unknown_user';
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    ChatServiceSingleton.instance.webSocketService.addMessageListener(_onWsMessage);
    _loadCurrentUserId();
    _disposed = false;
  }

  Future<void> _loadCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'unknown_user';
    if (!mounted) return;
    if (mounted && !_disposed) {
      setState(() {
        _currentUserId = userId;
      });
    }
  }

  void _onWsMessage(Map<String, dynamic> data) {
    if (mounted && !_disposed) {
      setState(() {
        _wsLog = data.toString();
      });
    }
  }

  Future<void> _sendConnectRequest(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final myUserId = prefs.getString('user_id') ?? 'unknown_user';
    final chatService = ChatServiceSingleton.instance;
    if (!chatService.isConnected) {
      await chatService.connectAndRegister(kTestWsServerUrl, 'test_room', myUserId);
    } else {
      // 確保用戶已註冊
      chatService.ensureUserRegistered(myUserId);
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
    final chatService = ChatServiceSingleton.instance;
    if (!chatService.isConnected) {
      await chatService.connectAndRegister(kTestWsServerUrl, 'test_room', myUserId);
    } else {
      // 確保用戶已註冊
      chatService.ensureUserRegistered(myUserId);
    }
    final roomId = await chatService.createRoom(roomName);
    debugPrint('[TestTab] createRoom 回傳的 roomId: $roomId');
    String joinMsg = '';
    if (roomId != null) {
      debugPrint('[TestTab] roomId 不為 null，準備 joinRoom');
      
      // 保存聊天室歷史（使用目標用戶 ID）
      await _saveChatRoomHistory(roomId, roomName, kTestTargetUserId);
      
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
            chatService: chatService,
          ),
        ),
      );
      debugPrint('[TestTab] Navigator.push 已執行');
      
      // 在背景執行 joinRoom
      chatService.joinRoom(roomId).then((_) {
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

  Future<void> _changeUserId(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 顯示輸入對話框讓用戶輸入郵件和密碼
    if (!context.mounted) return;
    final result = await _showEmailPasswordDialog(context);
    if (result == null) return;
    
    final email = result['email']!;
    final password = result['password']!;

    try {
      // 通過 HTTP 註冊並獲取新的用戶 ID
      const baseUrl = 'https://near-ride-backend-api.onrender.com/';
      final userApiService = UserApiService(baseUrl);
      final newUserId = await userApiService.registerUserWithEmail(email, password);
      
      if (newUserId == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('註冊失敗，請檢查郵件地址和密碼')),
        );
        return;
      }

      // 保存新的用戶 ID
      await prefs.setString('user_id', newUserId);
      await prefs.setString('user_email', email);
      
      debugPrint('[TestTab] HTTP 註冊成功，獲得 userId: $newUserId');

      // 斷開舊連線（如果存在）
      final chatService = ChatServiceSingleton.instance;
      if (chatService.isConnected) {
        chatService.disconnect();
        debugPrint('[TestTab] 已斷開舊的 WebSocket 連線');
      }

      // 通過 WebSocket 註冊用戶（使用現有的 ChatService 實例）
      try {
        await chatService.connectAndRegister(kTestWsServerUrl, '', newUserId);
        debugPrint('[TestTab] WebSocket 用戶註冊成功: $newUserId');
      } catch (e) {
        debugPrint('[TestTab] WebSocket 用戶註冊失敗: $e');
        // WebSocket 註冊失敗不阻止繼續操作
      }

      // 更新顯示
      if (mounted && !_disposed) {
        setState(() {
          _currentUserId = newUserId;
        });
      }
  @override
  void dispose() {
    _disposed = true;
    ChatServiceSingleton.instance.webSocketService.removeMessageListener(_onWsMessage);
    super.dispose();
  }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('註冊成功！新的用戶 ID: $newUserId\nWebSocket 註冊已完成')),
      );
    } catch (e) {
      debugPrint('[TestTab] HTTP 註冊失敗: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('註冊出錯，請檢查網路連線')),
      );
    }
  }

  Future<void> _saveChatRoomHistory(String roomId, String roomName, String otherUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('chat_history') ?? [];
    
    // 檢查是否已存在
    final exists = historyJson.any((jsonStr) {
      final data = jsonDecode(jsonStr);
      return data['roomId'] == roomId;
    });
    
    if (!exists) {
      final newHistory = {
        'roomId': roomId,
        'roomName': roomName,
        'lastMessage': '',
        'lastMessageTime': DateTime.now().toIso8601String(),
        'otherUserId': otherUserId,
      };
      historyJson.add(jsonEncode(newHistory));
      await prefs.setStringList('chat_history', historyJson);
      debugPrint('[TestTab] 已保存聊天室歷史: $roomName ($roomId)');
    }
  }

  static Future<Map<String, String>?> _showEmailPasswordDialog(BuildContext context) async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('註冊新用戶'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '郵件地址',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密碼',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final email = emailController.text.trim();
              final password = passwordController.text.trim();
              if (email.isNotEmpty && password.isNotEmpty) {
                Navigator.pop(context, {'email': email, 'password': password});
              }
            },
            child: const Text('註冊'),
          ),
        ],
      ),
    );
  }

  static Future<String?> _showInputDialog(BuildContext context, String title, [String? initialValue]) async {
    final controller = TextEditingController(text: initialValue ?? '');
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
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Text(
                '當前用戶 ID: $_currentUserId',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
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
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _createRoom(context),
              child: const Text('創建聊天室（與 0000）'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _connectAndCreateRoom(context),
              child: const Text('連接並創建聊天室'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _changeUserId(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('註冊新用戶'),
            ),
          ],
        ),
      ),
    );
  }
}
