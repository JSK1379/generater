import 'package:flutter/material.dart';
import 'ble_scan_body.dart';
import 'settings_page.dart';
import 'avatar_page.dart';
import 'chat_room_list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'settings_ble_helper.dart';
import '_test_tab.dart';
import 'chat_service_singleton.dart';
import 'chat_page.dart';
import 'dart:convert';

class MainTabPage extends StatefulWidget {
  const MainTabPage({super.key});
  @override
  State<MainTabPage> createState() => MainTabPageState();
}

class MainTabPageState extends State<MainTabPage> {
  int currentIndex = 0;
  bool _isAdvertising = false;
  final TextEditingController _nicknameController = TextEditingController();
  Uint8List? _avatarThumbnailBytes;

  @override
  void initState() {
    super.initState();
    _loadNicknameFromPrefs();
    // 添加全局連接請求監聽器
    ChatServiceSingleton.instance.addConnectRequestListener(_handleConnectRequest);
    // 添加全局聊天室加入監聽器
    ChatServiceSingleton.instance.webSocketService.addMessageListener(_onWsMessage);
  }

  @override
  void dispose() {
    // 移除全局連接請求監聽器
    ChatServiceSingleton.instance.removeConnectRequestListener(_handleConnectRequest);
    // 移除全局聊天室加入監聽器
    ChatServiceSingleton.instance.webSocketService.removeMessageListener(_onWsMessage);
    super.dispose();
  }

  Future<void> _loadNicknameFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final nickname = prefs.getString('nickname') ?? '';
    _nicknameController.text = nickname;
  }

  Future<void> _saveNicknameToPrefs(String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nickname', nickname);
  }

  void _setAvatarThumbnailBytes(Uint8List? bytes) {
    setState(() {
      _avatarThumbnailBytes = bytes;
    });
  }

  void updateChatHistoryDisplay() {
    setState(() {});
  }

  List<Widget> get _pages => [
    const BleScanBody(),
    AvatarPage(
      setAvatarThumbnailBytes: _setAvatarThumbnailBytes,
      avatarThumbnailBytes: _avatarThumbnailBytes,
    ),
    const ChatRoomListPage(), // 移除條件判斷，常態顯示
    // 新增測試分頁
    const TestTab(),
    SettingsPage(
      isAdvertising: _isAdvertising,
      onToggleAdvertise: (v) async {
        setState(() {
          _isAdvertising = v;
        });
        // 呼叫 BLE 廣播，使用包含 userId 的新方法
        final nickname = _nicknameController.text;
        
        // 獲取當前用戶 ID
        final chatService = ChatServiceSingleton.instance;
        final userId = await chatService.getCurrentUserId();
        
        // 使用新的 advertiseWithUserId 方法
        await SettingsBleHelper.advertiseWithUserId(
          nickname: nickname,
          userId: userId,
          imageId: '', // 可以後續擴展
          enable: v,
        );
        debugPrint('[MainTabPage] onToggleAdvertise: $v, nickname: $nickname, userId: $userId');
      },
      nicknameController: _nicknameController,
      setAvatarThumbnailBytes: _setAvatarThumbnailBytes,
      avatarThumbnailBytes: _avatarThumbnailBytes,
      onSaveNickname: _saveNicknameToPrefs,
    ),
  ];

  List<BottomNavigationBarItem> get _items => [
    const BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: '藍牙'),
    const BottomNavigationBarItem(icon: Icon(Icons.face), label: 'Avatar'),
    const BottomNavigationBarItem(icon: Icon(Icons.chat), label: '聊天室'), // 移除條件判斷，常態顯示
    const BottomNavigationBarItem(icon: Icon(Icons.science), label: '測試'),
    const BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設置'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: currentIndex,
        items: _items,
        onTap: (i) => setState(() => currentIndex = i),
      ),
    );
  }

  // 處理全局連接請求
  Future<void> _handleConnectRequest(String fromUserId, String toUserId) async {
    // 檢查請求是否發給當前用戶
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('user_id') ?? 'unknown_user';
    
    if (toUserId != currentUserId) {
      // 不是發給當前用戶的請求，忽略
      return;
    }
    
    if (!mounted) return;
    
    // 顯示全局連接請求對話框
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('收到連接請求'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('來自用戶: $fromUserId'),
            const SizedBox(height: 8),
            const Text('是否接受連接請求？'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('拒絕'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('接受'),
          ),
        ],
      ),
    );
    
    if (!mounted) return;
    
    // 用戶做出了選擇，發送 connect_response
    final chatService = ChatServiceSingleton.instance;
    final roomId = chatService.generateRoomId(currentUserId, fromUserId);
    
    // 發送接受/拒絕的回應給服務器
    chatService.sendConnectResponse(currentUserId, fromUserId, result == true, result == true ? roomId : null);
    
    if (result == true) {
      // 用戶接受連接，創建並進入聊天室
      
      // 儲存聊天室歷史
      await _saveChatRoomHistory(roomId, '與 $fromUserId 的聊天', fromUserId);
      
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            roomId: roomId,
            roomName: '與 $fromUserId 的聊天',
            currentUser: currentUserId,
            chatService: chatService,
          ),
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已拒絕連接請求')),
        );
      }
    }
  }
  
  // 儲存聊天室歷史
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
    }
  }

  void _onWsMessage(Map<String, dynamic> data) async {
    if (data['type'] == 'joined_room' && data['roomId'] != null) {
      final roomId = data['roomId'] as String;
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('user_id') ?? 'unknown_user';
      
      // 在獲取異步數據後立即檢查 mounted
      if (!mounted) return;
      
      // 自動跳轉聊天室 - 無async gap後使用context
      _navigateToChatPage(roomId, currentUserId);
      
      // 通知聊天室分頁刷新
      if (ChatRoomListPage.refresh != null) {
        ChatRoomListPage.refresh!();
      }
    }
  }
  
  // 拆分為同步方法，避免 async gap
  void _navigateToChatPage(String roomId, String currentUserId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          roomId: roomId,
          roomName: '聊天室 $roomId',
          currentUser: currentUserId,
          chatService: ChatServiceSingleton.instance,
        ),
      ),
    );
  }
}


