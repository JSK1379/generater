import 'package:flutter/material.dart';
import 'chat_service.dart';
import 'chat_models.dart';

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

  @override
  void initState() {
    super.initState();
    widget.chatService.setCurrentUser(widget.currentUser);
    
    // 如果還沒連線，先連線到 WebSocket 伺服器
    if (!widget.chatService.isConnected) {
      _connectToWebSocket();
    } else {
      // 已連線則直接加入房間
      widget.chatService.joinRoom(widget.roomId);
    }
    
    // 監聽訊息變化，自動捲動到底部
    widget.chatService.addListener(_scrollToBottom);
  }

  Future<void> _connectToWebSocket() async {
    final success = await widget.chatService.connect(
      'wss://near-ride-backend-api.onrender.com/ws',
      widget.roomId,
      widget.currentUser,
    );
    if (success) {
      widget.chatService.joinRoom(widget.roomId);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法連接到聊天伺服器')),
        );
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      widget.chatService.sendTextMessage(
        widget.roomId,
        widget.currentUser,
        text,
      );
      _messageController.clear();
    }
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_scrollToBottom);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(widget.roomName),
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
          child: Column(
            children: [
              // 訊息列表
              Expanded(
                child: AnimatedBuilder(
                  animation: widget.chatService,
                  builder: (context, child) {
                    if (widget.chatService.messages.isEmpty) {
                      return const Center(
                        child: Text('目前沒有訊息，開始聊天吧！'),
                    );
                  }
                  
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: widget.chatService.messages.length,
                    itemBuilder: (context, index) {
                      final message = widget.chatService.messages[index];
                      final isMe = message.sender == widget.currentUser;
                      
                      return _buildMessageBubble(message, isMe);
                    },
                  );
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: '輸入訊息...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                      maxLines: null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send),
                    color: Theme.of(context).primaryColor,
                  ),
                ],
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
                child: Text(
                  message.sender,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
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
