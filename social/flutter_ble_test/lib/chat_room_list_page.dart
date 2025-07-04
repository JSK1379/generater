import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'chat_service.dart';
import 'chat_page.dart';

class ChatRoomListPage extends StatefulWidget {
  const ChatRoomListPage({super.key});

  @override
  State<ChatRoomListPage> createState() => _ChatRoomListPageState();
}

class _ChatRoomListPageState extends State<ChatRoomListPage> {
  List<ChatRoomHistory> _chatHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('chat_history') ?? [];
    
    setState(() {
      _chatHistory = historyJson
          .map((jsonStr) => ChatRoomHistory.fromJson(jsonDecode(jsonStr)))
          .toList();
      _chatHistory.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      _isLoading = false;
    });
  }



  void _enterChatRoom(ChatRoomHistory history) async {
    final chatService = ChatService();
    final currentUserId = await chatService.getCurrentUserId();
    
    if (!mounted) return;
    
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
    
    // 如果從聊天頁回來，重新載入歷史
    if (result != null) {
      _loadChatHistory();
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
                // 呼叫伺服器刪除聊天室
                for (final roomId in selected) {
                  ChatService().deleteRoom(roomId);
                }
                // 用戶端隱藏聊天室
                setState(() {
                  _chatHistory.removeWhere((h) => selected.contains(h.roomId));
                });
                // 更新本地儲存
                final prefs = await SharedPreferences.getInstance();
                prefs.setStringList('chat_history', _chatHistory.map((h) => jsonEncode(h.toJson())).toList());
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
              child: Text(
                history.roomName.isNotEmpty ? history.roomName[0] : '?',
                style: TextStyle(
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              history.roomName,
              style: const TextStyle(fontWeight: FontWeight.w600),
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

class ChatRoomHistory {
  final String roomId;
  final String roomName;
  final String lastMessage;
  final DateTime lastMessageTime;
  final String otherUserId;

  ChatRoomHistory({
    required this.roomId,
    required this.roomName,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.otherUserId,
  });

  factory ChatRoomHistory.fromJson(Map<String, dynamic> json) {
    return ChatRoomHistory(
      roomId: json['roomId'] ?? '',
      roomName: json['roomName'] ?? '',
      lastMessage: json['lastMessage'] ?? '',
      lastMessageTime: DateTime.tryParse(json['lastMessageTime'] ?? '') ?? DateTime.now(),
      otherUserId: json['otherUserId'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'roomId': roomId,
      'roomName': roomName,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime.toIso8601String(),
      'otherUserId': otherUserId,
    };
  }
}
