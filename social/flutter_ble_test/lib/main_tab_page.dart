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
import 'chat_models.dart';
import 'chat_room_open_manager.dart'; // 導入全局管理器

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
  
  // 使用全局管理器管理聊天室開啟狀態
  final ChatRoomOpenManager _openManager = ChatRoomOpenManager();

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
    
    // 發送接受/拒絕的回應給服務器 (roomId 由伺服器產生)
    chatService.sendConnectResponse(currentUserId, fromUserId, result == true);
    
    if (result == true) {
      // 用戶接受連接，不再自動創建聊天室，由 joined_room 事件處理
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已接受連接請求，等待伺服器建立聊天室...')),
        );
      }
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
    
    // 嘗試獲取對方暱稱
    String otherNickname = '';
    try {
      // 從連接對象獲取暱稱
      final connectionHistoryJson = prefs.getStringList('connection_history') ?? [];
      for (final jsonStr in connectionHistoryJson) {
        final data = jsonDecode(jsonStr);
        if (data['userId'] == otherUserId && data['nickname'] != null) {
          otherNickname = data['nickname'];
          break;
        }
      }
      
      // 如果連接歷史中沒有找到，使用默認值
      if (otherNickname.isEmpty) {
        otherNickname = otherUserId;
      }
    } catch (e) {
      debugPrint('獲取對方暱稱時出錯: $e');
      otherNickname = otherUserId;
    }
    
    // 創建聊天室歷史記錄對象
    final roomInfo = ChatRoomHistory(
      roomId: roomId,
      roomName: '與\'$otherNickname\'的聊天室',
      lastMessage: '',
      lastMessageTime: DateTime.now(),
      otherUserId: otherUserId,
      otherNickname: otherNickname,
    );
    
    // 儲存聊天室歷史記錄
    await prefs.setString('chat_room_info_$roomId', jsonEncode(roomInfo.toJson()));
    debugPrint('[MainTabPage] 已儲存聊天室資訊: ${roomInfo.toJson()}');
    
    // 更新 room_ids 列表，這個列表是 chat_room_list_page.dart 用來顯示聊天室的
    var roomIds = prefs.getStringList('room_ids') ?? [];
    if (!roomIds.contains(roomId)) {
      roomIds.add(roomId);
      await prefs.setStringList('room_ids', roomIds);
      debugPrint('[MainTabPage] 已將房間 $roomId 添加到 room_ids 列表');
    }
  }

  void _onWsMessage(Map<String, dynamic> data) async {
    // 處理 joined_room 事件
    if (data['type'] == 'joined_room' && data['roomId'] != null) {
      final roomId = data['roomId'] as String;
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('user_id') ?? 'unknown_user';
      
      // 取得聊天室名稱和對方 ID
      final roomName = data['roomName'] ?? '聊天室 $roomId';
      final otherUserId = data['otherUserId'] ?? (data['from'] ?? '未知用戶');
      
      // 儲存聊天室歷史
      await _saveChatRoomHistory(roomId, roomName, otherUserId);
      
      // 在獲取異步數據後立即檢查 mounted
      if (!mounted) return;
      
      // 自動跳轉聊天室 - 無async gap後使用context
      _navigateToChatPage(roomId, currentUserId);
      
      // 通知聊天室分頁刷新
      if (ChatRoomListPage.refresh != null) {
        ChatRoomListPage.refresh!();
      }
    }
    
    // 處理 connect_response 事件
    if (data['type'] == 'connect_response' && data['accept'] == true && data['roomId'] != null) {
      final roomId = data['roomId'] as String;
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('user_id') ?? 'unknown_user';
      
      // 取得對方用戶 ID
      final fromUser = data['from'] as String;
      final toUser = data['to'] as String;
      final otherUserId = (fromUser == currentUserId) ? toUser : fromUser;
      
      // 處理可能的錯誤
      if (data['error'] != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('連接錯誤: ${data['error']}')),
          );
        }
        return;
      }
      
      // 處理聊天歷史記錄
      // 注意：ChatService 已經在 _handleMessage 方法中處理了 chat_history
      // 我們這裡不需要再次處理，只需要獲取 roomId 並儲存聊天室歷史
      
      // 儲存聊天室歷史
      await _saveChatRoomHistory(roomId, '與 $otherUserId 的聊天', otherUserId);
      
      // 先獲取聊天記錄
      final chatService = ChatServiceSingleton.instance;
      debugPrint('[MainTabPage] 先獲取聊天室 $roomId 的歷史記錄');
      await chatService.fetchChatHistory(roomId);
      
      // 檢查是否仍然 mounted
      if (!mounted) return;
      
      // 然後加入聊天室
      final joinSuccess = await chatService.joinRoom(roomId);
      
      // 檢查是否仍然 mounted
      if (!mounted) return;
      
      if (joinSuccess) {
        // 更新 UI 以顯示新的聊天室
        // 通知聊天室分頁刷新
        if (ChatRoomListPage.refresh != null) {
          ChatRoomListPage.refresh!();
        }
        
        // 只有在成功加入房間後才導航到聊天頁面
        // 自動跳轉聊天室 - 無async gap後使用context
        _navigateToChatPage(roomId, currentUserId);
      } else {
        // 加入房間失敗時顯示錯誤訊息
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加入聊天室失敗')),
        );
      }
    }
  }
  
  // 拆分為同步方法，避免 async gap
  void _navigateToChatPage(String roomId, String currentUserId) {
    // 使用全局管理器防止重複開啟
    if (!_openManager.markRoomAsOpening(roomId)) {
      debugPrint('[MainTabPage] 聊天室 $roomId 正在開啟中，忽略重複導航');
      return;
    }
    
    // 從歷史紀錄中取得聊天室名稱
    SharedPreferences.getInstance().then((prefs) {
      // 先檢查是否還掛載
      if (!mounted) {
        _openManager.markRoomAsClosed(roomId);
        return;
      }
      
      final chatService = ChatServiceSingleton.instance;
      
      // 使用 ChatService 的方法取得聊天室顯示名稱
      chatService.getChatRoomDisplayName(roomId, currentUserId).then((roomName) {
        // 檢查 widget 是否仍然掛載
        if (!mounted) {
          _openManager.markRoomAsClosed(roomId);
          return;
        }
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              roomId: roomId,
              roomName: roomName,
              currentUser: currentUserId,
              chatService: chatService,
            ),
          ),
        ).then((_) {
          // 導航結束後，從集合中移除
          _openManager.markRoomAsClosed(roomId);
        });
      }).catchError((error) {
        // 發生錯誤，從集合中移除
        _openManager.markRoomAsClosed(roomId);
        debugPrint('[MainTabPage] 獲取聊天室名稱出錯: $error');
      });
    }).catchError((error) {
      // 發生錯誤，從集合中移除
      _openManager.markRoomAsClosed(roomId);
      debugPrint('[MainTabPage] 獲取SharedPreferences出錯: $error');
    });
  }
}


