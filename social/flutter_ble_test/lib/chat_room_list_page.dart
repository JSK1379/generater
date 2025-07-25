import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'chat_service_singleton.dart';
import 'chat_page.dart';
import 'chat_models.dart'; // 添加引入
import 'chat_room_open_manager.dart'; // 添加全局管理器引入

class ChatRoomListPage extends StatefulWidget {
  const ChatRoomListPage({super.key});

  static void Function()? refresh;

  @override
  State<ChatRoomListPage> createState() => _ChatRoomListPageState();
}

class _ChatRoomListPageState extends State<ChatRoomListPage> {
  List<ChatRoomHistory> _chatHistory = [];
  bool _isLoading = true;
  String _currentUserId = '';
  
  // 使用全局管理器
  final ChatRoomOpenManager _openManager = ChatRoomOpenManager();

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    _loadCurrentUserId();
    ChatRoomListPage.refresh = _loadChatHistory;
  }

  @override
  void dispose() {
    if (ChatRoomListPage.refresh == _loadChatHistory) {
      ChatRoomListPage.refresh = null;
    }
    super.dispose();
  }

  Future<void> _loadCurrentUserId() async {
    final chatService = ChatServiceSingleton.instance;
    final userId = await chatService.getCurrentUserId();
    if (mounted) {
      setState(() {
        _currentUserId = userId;
      });
    }
  }

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 獲取所有聊天室 ID
    final roomIds = prefs.getStringList('room_ids') ?? [];
    final List<ChatRoomHistory> allHistory = [];
    
    // 針對每個聊天室 ID 分別讀取其歷史記錄
    for (final roomId in roomIds) {
      // 首先嘗試從 chat_room_info 獲取信息
      final roomInfoJson = prefs.getString('chat_room_info_$roomId');
      if (roomInfoJson != null) {
        try {
          final roomInfo = ChatRoomHistory.fromJson(jsonDecode(roomInfoJson));
          allHistory.add(roomInfo);
          continue; // 如果成功獲取到聊天室信息，就不需要再讀取歷史記錄了
        } catch (e) {
          debugPrint('解析聊天室信息失敗: $e');
          // 如果解析失敗，繼續嘗試讀取歷史記錄
        }
      }
      
      // 如果沒有聊天室信息，再嘗試從歷史記錄中獲取
      final roomHistoryJson = prefs.getStringList('chat_history_$roomId') ?? [];
      if (roomHistoryJson.isNotEmpty) {
        try {
          // 讀取該聊天室的最新一條記錄作為聊天室列表顯示
          final lastMessage = ChatRoomHistory.fromJson(jsonDecode(roomHistoryJson.last));
          allHistory.add(lastMessage);
        } catch (e) {
          debugPrint('解析聊天室歷史記錄失敗: $e');
        }
      }
    }
    
    setState(() {
      _chatHistory = allHistory;
      _chatHistory.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      _isLoading = false;
    });
  }



  // 確保只能進入未開啟的聊天室
  void _enterChatRoom(ChatRoomHistory history) async {
    // 使用全局管理器防止重複點擊開啟同一聊天室
    if (!_openManager.markRoomAsOpening(history.roomId)) {
      debugPrint('[ChatRoomListPage] 聊天室 ${history.roomId} 正在開啟中，忽略重複點擊');
      return;
    }
    
    final chatService = ChatServiceSingleton.instance;
    final currentUserId = await chatService.getCurrentUserId();
    
    // 先獲取聊天記錄
    debugPrint('[ChatRoomListPage] 先使用 HTTP 獲取聊天室 ${history.roomId} 的歷史記錄');
    await chatService.fetchChatHistoryHttp(history.roomId);
    
    if (!mounted) {
      // 如果不再掛載，從開啟集合中移除
      _openManager.markRoomAsClosed(history.roomId);
      return;
    }
    
    // 然後加入聊天室
    final joinSuccess = await chatService.joinRoom(history.roomId);
    
    if (!mounted) {
      // 如果不再掛載，從開啟集合中移除
      _openManager.markRoomAsClosed(history.roomId);
      return;
    }
    
    if (!joinSuccess) {
      // 加入失敗，從開啟集合中移除
      _openManager.markRoomAsClosed(history.roomId);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加入聊天室失敗')),
      );
      return;
    }
    
    // 現在已經獲取了歷史記錄並加入了聊天室，導航到聊天頁面
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            roomId: history.roomId,
            roomName: history.roomName,
            currentUser: currentUserId,
            chatService: chatService,
          ),
        ),
      );
      
      // 聊天室已關閉，從全局管理器中移除
      _openManager.markRoomAsClosed(history.roomId);
      
      // 如果從聊天頁回來，重新載入歷史
      if (result != null && mounted) {
        _loadChatHistory();
      }
    } catch (e) {
      // 發生錯誤，從全局管理器中移除
      _openManager.markRoomAsClosed(history.roomId);
      debugPrint('[ChatRoomListPage] 開啟聊天室出錯: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('開啟聊天室時發生錯誤: ${e.toString().substring(0, math.min(50, e.toString().length))}')),
        );
      }
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    if (messageDate == today) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_chatHistory.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('聊天室')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                '尚未有聊天記錄',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                '透過 BLE 掃描連接其他用戶開始聊天',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天室'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: '編輯聊天室',
            onPressed: () async {
              // 彈出多選對話框
              final selected = await showDialog<List<String>>(
                context: context,
                builder: (context) {
                  final selectedRoomIds = <String>{};
                  return AlertDialog(
                    title: const Text('隱藏聊天室'),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: StatefulBuilder(
                        builder: (context, setState) {
                          return ListView(
                            shrinkWrap: true,
                            children: _chatHistory.map((history) {
                              return CheckboxListTile(
                                value: selectedRoomIds.contains(history.roomId),
                                title: Text(history.roomName),
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      selectedRoomIds.add(history.roomId);
                                    } else {
                                      selectedRoomIds.remove(history.roomId);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: const Text('取消'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, selectedRoomIds.toList()),
                        child: const Text('隱藏'),
                      ),
                    ],
                  );
                },
              );
              if (selected != null && selected.isNotEmpty) {
                // 只在本地隱藏聊天室，不呼叫伺服器
                final prefs = await SharedPreferences.getInstance();
                
                // 獲取當前的聊天室 ID 列表
                final roomIds = prefs.getStringList('room_ids') ?? [];
                
                // 移除被選中隱藏的聊天室 ID
                final updatedRoomIds = roomIds.where((id) => !selected.contains(id)).toList();
                
                // 更新聊天室 ID 列表
                prefs.setStringList('room_ids', updatedRoomIds);
                
                // 從畫面移除選中的聊天室
                setState(() {
                  _chatHistory.removeWhere((h) => selected.contains(h.roomId));
                });
              }
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _chatHistory.length,
        itemBuilder: (context, index) {
          final history = _chatHistory[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: FutureBuilder<String>(
                future: ChatServiceSingleton.instance.getUserNickname(history.otherUserId),
                builder: (context, snapshot) {
                  final nickname = snapshot.data ?? history.otherUserId;
                  return Text(
                    nickname.isNotEmpty ? nickname[0] : '?',
                    style: TextStyle(
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            ),
            title: FutureBuilder<String>(
              future: ChatServiceSingleton.instance.getChatRoomDisplayName(history.roomId, _currentUserId),
              builder: (context, snapshot) {
                return Text(
                  snapshot.data ?? history.roomName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                );
              },
            ),
            subtitle: Text(
              history.lastMessage.isNotEmpty 
                  ? history.lastMessage 
                  : '點擊進入聊天室',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            trailing: Text(
              _formatTime(history.lastMessageTime),
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
            onTap: () => _enterChatRoom(history),
          );
        },
      ),
    );
  }
}
