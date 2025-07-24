import 'package:flutter/material.dart';
import 'chat_service.dart';
import 'chat_models.dart';
import 'chat_room_open_manager.dart'; // 導入全局管理器

class ChatPage extends StatefulWidget {
  final String roomId;
  final String roomName;
  final String currentUser;
  final ChatService chatService;
  
  const ChatPage({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.currentUser,
    required this.chatService,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // 使用全局管理器
  final ChatRoomOpenManager _openManager = ChatRoomOpenManager();
  
  // 自動捲動相關變數
  bool _isUserAtBottom = true; // 追蹤用戶是否在底部
  int _previousMessageCount = 0; // 追蹤之前的訊息數量
  bool _showScrollToBottomButton = false; // 是否顯示回到底部按鈕
  bool _isScrolling = false; // 防止重複滾動
  List<ChatMessage> _cachedMessages = []; // 緩存訊息列表

  @override
  void initState() {
    super.initState();
    
    // 設置滾動監聽器
    _scrollController.addListener(_onScroll);
    
    // 設置當前用戶
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.chatService.setCurrentUser(widget.currentUser);
        
        // 確保房間對象存在，然後設置當前房間
        debugPrint('[ChatPage] 嘗試設置當前房間: ${widget.roomId}');
        widget.chatService.setCurrentRoom(widget.roomId);
        
        // 如果還沒連線，先連線到 WebSocket 伺服器
        if (!widget.chatService.isConnected) {
          _connectToWebSocket();
        }
        
        // 監聽訊息變化，智能自動捲動
        widget.chatService.addListener(_onMessagesChanged);
        
        // 初始化訊息數量
        _previousMessageCount = widget.chatService.messages.length;
        _cachedMessages = List.from(widget.chatService.messages);
        
        // 如果有訊息，初始捲動到底部
        if (widget.chatService.messages.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _scrollToBottom();
            }
          });
        }
      }
    });
  }

  Future<void> _connectToWebSocket() async {
    final success = await widget.chatService.connect(
      'wss://near-ride-backend-api.onrender.com/ws',
      widget.roomId,
      widget.currentUser,
    );
    
    if (!mounted) return;
    
    if (success) {
      // 連線成功，不需要在這裡調用 joinRoom
      // ChatService 會在處理 connect_response 時自動加入房間
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法連接到聊天伺服器')),
      );
    }
  }

  // 監聽滾動位置變化
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    
    // 判斷用戶是否在底部（允許 50 像素的誤差）
    final isAtBottom = (maxScroll - currentScroll) <= 50;
    
      // 只有當狀態真正改變時才調用 setState
    if (isAtBottom != _isUserAtBottom) {
      setState(() {
        _isUserAtBottom = isAtBottom;
        _showScrollToBottomButton = !isAtBottom && _cachedMessages.isNotEmpty;
      });
    }
  }
  
  // 智能自動捲動：只在用戶在底部且有新訊息時才自動捲動
  void _onMessagesChanged() {
    if (!mounted || !_scrollController.hasClients) return;
    
    final currentMessages = widget.chatService.messages;
    final currentMessageCount = currentMessages.length;
    
    // 檢查是否有新訊息，並且訊息數量確實有變化
    if (currentMessageCount > _previousMessageCount && currentMessageCount > 0) {
      debugPrint('[ChatPage] 訊息數量變化: $_previousMessageCount -> $currentMessageCount');
      
      // 更新緩存的訊息列表
      setState(() {
        _cachedMessages = List.from(currentMessages);
      });
      
      // 只有當用戶在底部時才自動捲動
      if (_isUserAtBottom) {
        // 使用 WidgetsBinding 確保在下一幀執行，避免在構建過程中調用
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollToBottom();
          }
        });
      }
      
      // 更新訊息數量
      _previousMessageCount = currentMessageCount;
    }
  }

  void _scrollToBottom() {
    // 防止重複滾動
    if (_isScrolling || !mounted || !_scrollController.hasClients) return;
    
    _isScrolling = true;
    
    try {
      final maxExtent = _scrollController.position.maxScrollExtent;
      // 如果已經在底部，不需要滾動
      if ((_scrollController.position.pixels - maxExtent).abs() <= 1) {
        _isScrolling = false;
        return;
      }
      
      _scrollController.animateTo(
        maxExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      ).then((_) {
        _isScrolling = false;
      }).catchError((e) {
        debugPrint('滾動到底部時出錯: $e');
        _isScrolling = false;
      });
    } catch (e) {
      debugPrint('滾動到底部時出錯: $e');
      _isScrolling = false;
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      // 檢查 WebSocket 連線狀態
      if (!widget.chatService.isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('無法傳送訊息：未連線到伺服器'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      widget.chatService.sendTextMessage(
        widget.roomId,
        widget.currentUser,
        text,
      );
      _messageController.clear();
      
      // 發送訊息後立即捲動到底部
      setState(() {
        _isUserAtBottom = true; // 標記用戶在底部
        _showScrollToBottomButton = false; // 隱藏按鈕
      });
      
      // 使用 WidgetsBinding 確保在下一幀執行滾動
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToBottom();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_onMessagesChanged);
    _scrollController.removeListener(_onScroll);
    _messageController.dispose();
    _scrollController.dispose();
    
    // 確保在頁面關閉時標記聊天室為已關閉
    _openManager.markRoomAsClosed(widget.roomId);
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: FutureBuilder<String>(
            future: widget.chatService.getChatRoomDisplayName(widget.roomId, widget.currentUser),
            builder: (context, snapshot) {
              return Text(snapshot.data ?? widget.roomName);
            },
          ),
          actions: [
            AnimatedBuilder(
              animation: widget.chatService,
              builder: (context, child) {
                return Icon(
                  widget.chatService.isConnected ? Icons.wifi : Icons.wifi_off,
                  color: widget.chatService.isConnected ? Colors.green : Colors.red,
                );
              },
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: SafeArea(
          bottom: false, // 不處理底部，讓我們手動處理
          child: Stack(
            children: [
              Column(
                children: [
              // 訊息列表
              Expanded(
                child: _cachedMessages.isEmpty
                    ? const Center(
                        child: Text('目前沒有訊息，開始聊天吧！'),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8.0),
                        itemCount: _cachedMessages.length,
                        itemBuilder: (context, index) {
                          final message = _cachedMessages[index];
                          final isMe = message.sender == widget.currentUser;
                          
                          return _buildMessageBubble(message, isMe);
                        },
                      ),
              ),
            
            // 輸入框
            Container(
              padding: EdgeInsets.only(
                left: 8.0,
                right: 8.0,
                top: 8.0,
                bottom: 8.0 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: StreamBuilder<bool>(
                stream: widget.chatService.connectionStateStream,
                initialData: widget.chatService.isConnected, // 添加初始數據
                builder: (context, snapshot) {
                  final isConnected = snapshot.data ?? false;
                  
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          enabled: isConnected,
                          decoration: InputDecoration(
                            hintText: isConnected ? '輸入訊息...' : '連線中，請稍候...',
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: isConnected ? (_) => _sendMessage() : null,
                          maxLines: null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: isConnected ? _sendMessage : null,
                        icon: const Icon(Icons.send),
                        color: isConnected 
                          ? Theme.of(context).primaryColor 
                          : Colors.grey,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
            
            // 回到底部的浮動按鈕
            if (_showScrollToBottomButton)
              Positioned(
                bottom: 80, // 輸入框上方
                right: 16,
                child: FloatingActionButton.small(
                  onPressed: () {
                    setState(() {
                      _isUserAtBottom = true;
                      _showScrollToBottomButton = false;
                    });
                    _scrollToBottom();
                  },
                  backgroundColor: Theme.of(context).primaryColor,
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // 發送者暱稱和時間
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 4),
                child: FutureBuilder<String>(
                  future: widget.chatService.getUserNickname(message.sender),
                  builder: (context, snapshot) {
                    final displayName = snapshot.data ?? message.sender;
                    return Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ),
            
            // 訊息氣泡
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? Theme.of(context).primaryColor : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 圖片訊息
                  if (message.imageUrl != null && message.imageUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        message.imageUrl!,
                        width: 200,
                        height: 150,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 200,
                            height: 150,
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.broken_image),
                          );
                        },
                      ),
                    ),
                  
                  // 文字訊息
                  if (message.content.isNotEmpty)
                    Text(
                      message.content,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontSize: 16,
                      ),
                    ),
                ],
              ),
            ),
            
            // 時間戳
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 12, right: 12),
              child: Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    if (messageDate == today) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}
