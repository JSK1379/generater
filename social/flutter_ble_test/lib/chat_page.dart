import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'chat_service.dart';
import 'chat_models.dart';
import 'chat_room_open_manager.dart'; // 導入全局管理器
import 'api_config.dart';

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
  String _previousInputText = ''; // 追蹤之前的輸入文字
  bool _hasTriggeredInputScroll = false; // 防止同一次輸入多次滾動
  
  // AI輔助聊天相關變數（用於未來擴展）
  // bool _isAIAssistantOpen = false; // 是否正在使用AI輔助
  // String? _selectedMessageType; // 選擇的訊息類型
  List<String> _aiSuggestions = []; // AI生成的建議選項

  @override
  void initState() {
    super.initState();
    
    // 設置滾動監聽器
    _scrollController.addListener(_onScroll);
    
    // 設置文字輸入監聽器，當使用者開始輸入時自動滾動到底部
    _messageController.addListener(_onTextInputChanged);
    
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
        
        // 初始化訊息數量和緩存
        _updateMessagesCache();
        
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
  
  // 更新訊息緩存
  void _updateMessagesCache() {
    final currentMessages = widget.chatService.messages;
    debugPrint('[ChatPage] 更新訊息緩存，訊息數量: ${currentMessages.length}');
    debugPrint('[ChatPage] 當前用戶: ${widget.currentUser}');
    debugPrint('[ChatPage] 房間ID: ${widget.roomId}');
    
    // 打印每條訊息的詳細信息
    for (int i = 0; i < currentMessages.length; i++) {
      final msg = currentMessages[i];
      debugPrint('[ChatPage] 訊息 $i: sender=${msg.sender}, content=${msg.content}, isMe=${msg.sender == widget.currentUser}');
    }
    
    setState(() {
      _cachedMessages = List.from(currentMessages);
      _previousMessageCount = currentMessages.length;
    });
  }

  Future<void> _connectToWebSocket() async {
    final success = await widget.chatService.connect(
      ApiConfig.wsUrl,
      widget.roomId,
      widget.currentUser,
    );
    
    if (!mounted) return;
    
    if (success) {
      // 連線成功，刷新訊息顯示
      debugPrint('[ChatPage] WebSocket 連線成功，刷新訊息顯示');
      _updateMessagesCache();
      
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
  
  // 監聽文字輸入變化，當使用者開始輸入時自動滾動到底部
  void _onTextInputChanged() {
    if (!mounted || !_scrollController.hasClients) return;
    
    final currentText = _messageController.text;
    
    // 檢查是否為新的輸入內容（文字增加且不是空白）
    final isNewInput = currentText.length > _previousInputText.length && 
                      currentText.trim().isNotEmpty;
    
    // 只在以下情況自動滾動：
    // 1. 使用者開始新的輸入
    // 2. 使用者不在底部
    // 3. 此次輸入尚未觸發過滾動
    if (isNewInput && !_isUserAtBottom && !_hasTriggeredInputScroll) {
      _hasTriggeredInputScroll = true;
      
      // 設置短暫延遲，避免在快速輸入時頻繁滾動
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() {
            _isUserAtBottom = true;
            _showScrollToBottomButton = false;
          });
          _scrollToBottom();
        }
      });
    }
    
    // 如果文字被清空，重置滾動觸發狀態
    if (currentText.isEmpty) {
      _hasTriggeredInputScroll = false;
    }
    
    _previousInputText = currentText;
  }
  
  // 智能自動捲動：只在用戶在底部且有新訊息時才自動捲動
  void _onMessagesChanged() {
    if (!mounted) return;
    
    final currentMessages = widget.chatService.messages;
    final currentMessageCount = currentMessages.length;
    
    debugPrint('[ChatPage] _onMessagesChanged 被調用，當前訊息數: $currentMessageCount，之前訊息數: $_previousMessageCount');
    
    // 如果訊息數量有變化，或者緩存為空，則更新UI
    if (currentMessageCount != _previousMessageCount || _cachedMessages.isEmpty) {
      debugPrint('[ChatPage] 訊息數量變化: $_previousMessageCount -> $currentMessageCount');
      
      // 更新緩存的訊息列表
      setState(() {
        _cachedMessages = List.from(currentMessages);
      });
      
      // 只有當用戶在底部時才自動捲動
      if (_isUserAtBottom && currentMessageCount > _previousMessageCount) {
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
      
      // 重置輸入相關狀態
      _previousInputText = '';
      _hasTriggeredInputScroll = false;
      
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

  Future<void> _selectAndUploadImage() async {
    try {
      // 檢查 WebSocket 連線狀態
      if (!widget.chatService.isConnected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('無法上傳圖片：未連線到伺服器'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final ImagePicker picker = ImagePicker();
      
      // 顯示選擇來源的對話框
      final ImageSource? source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (BuildContext context) {
          return SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('從相簿選擇'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('拍攝照片'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.cancel),
                  title: const Text('取消'),
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        },
      );

      if (source == null) return;

      // 選擇圖片
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image == null) return;

      // 顯示上傳進度
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('正在上傳圖片...'),
              ],
            ),
            duration: Duration(minutes: 1), // 設置較長時間，實際會被手動dismiss
          ),
        );
      }

      // 上傳圖片並發送訊息
      final success = await widget.chatService.sendImageMessage(
        widget.roomId,
        widget.currentUser,
        image.path,
      );

      // 隱藏進度提示
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      if (success) {
        // 上傳成功，自動捲動到底部
        setState(() {
          _isUserAtBottom = true;
          _showScrollToBottomButton = false;
        });
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollToBottom();
          }
        });
      } else {
        // 上傳失敗
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('圖片上傳功能暫時不可用\n後端服務器尚未實現此功能'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('選擇或上傳圖片時發生錯誤: $e');
      
      // 隱藏進度提示
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('圖片上傳功能暫時不可用\n後端服務器尚未實現此功能'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // AI輔助聊天功能
  Future<void> _showAIAssistantDialog() async {
    // 第一階段：選擇訊息類型
    final messageType = await _showMessageTypeSelection();
    if (messageType == null) return;
    
    // 第二階段：顯示AI建議選項
    await _showAISuggestions(messageType);
  }
  
  // 顯示訊息類型選擇對話框
  Future<String?> _showMessageTypeSelection() async {
    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.8,
            child: Column(
              children: [
                // 固定頭部內容
                Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 標題
                      Row(
                        children: [
                          const Icon(Icons.smart_toy, color: Colors.purple, size: 28),
                          const SizedBox(width: 12),
                          const Text(
                            'AI輔助聊天',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '請選擇您想要傳送的訊息類型：',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                
                // 可滾動的訊息類型選項
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: _buildMessageTypeOptions(),
                    ),
                  ),
                ),
                
                // 底部間距
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
  
  // 建立訊息類型選項
  List<Widget> _buildMessageTypeOptions() {
    final messageTypes = [
      {'type': '問候', 'icon': Icons.waving_hand, 'description': '打招呼、問好'},
      {'type': '感謝', 'icon': Icons.favorite, 'description': '表達感謝、感激'},
      {'type': '邀請', 'icon': Icons.event_available, 'description': '邀請活動、聚會'},
      {'type': '詢問', 'icon': Icons.help_outline, 'description': '提出問題、詢問'},
      {'type': '道歉', 'icon': Icons.sentiment_very_dissatisfied, 'description': '表達歉意、道歉'},
      {'type': '關心', 'icon': Icons.health_and_safety, 'description': '關心對方、問候近況'},
      {'type': '分享', 'icon': Icons.share, 'description': '分享心情、經驗'},
      {'type': '鼓勵', 'icon': Icons.emoji_emotions, 'description': '給予鼓勵、支持'},
    ];
    
    return messageTypes.map((typeData) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).pop(typeData['type'] as String),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300, width: 1),
                borderRadius: BorderRadius.circular(12),
                color: Colors.transparent,
              ),
              child: Row(
                children: [
                  // 圖標
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      typeData['icon'] as IconData,
                      color: Colors.purple,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 文字內容
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          typeData['type'] as String,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          typeData['description'] as String,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 箭頭圖標
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
  
  // 顯示AI建議選項
  Future<void> _showAISuggestions(String messageType) async {
    // 模擬AI生成建議（實際應該調用AI API）
    final suggestions = _generateMockAISuggestions(messageType);
    
    setState(() {
      _aiSuggestions = suggestions;
    });
    
    if (!mounted) return;
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              // 固定頭部內容
              Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 標題
                    Row(
                      children: [
                        const Icon(Icons.lightbulb, color: Colors.amber, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          'AI建議：$messageType',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _resetAIAssistant();
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '選擇一個您喜歡的選項：',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              
              // 可滾動的AI建議選項
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        elevation: 2,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.purple.shade100,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: Colors.purple.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            suggestions[index],
                            style: const TextStyle(fontSize: 15),
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            _selectAISuggestion(suggestions[index]);
                          },
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              // 固定底部按鈕
              Container(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showAISuggestions(messageType); // 重新生成
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新生成建議'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  // 模擬AI生成建議（實際應該調用AI API）
  List<String> _generateMockAISuggestions(String messageType) {
    final suggestionMap = {
      '問候': [
        '嗨！你好嗎？希望你今天過得愉快！',
        '早安！今天是美好的一天，你有什麼計劃嗎？',
        '哈囉～好久不見，最近怎麼樣？',
        '你好！很高興又能和你聊天了～'
      ],
      '感謝': [
        '真的非常感謝你的幫助，太感激了！',
        '謝謝你總是在我需要的時候出現💕',
        '感謝你的耐心和理解，你真的很棒！',
        '謝謝你讓我的一天變得更美好～'
      ],
      '邀請': [
        '這個週末要不要一起出去走走？',
        '下次有時間的話，我們約個咖啡聊聊吧！',
        '最近有個很棒的活動，要不要一起參加？',
        '如果你有空的話，歡迎來我們的聚會！'
      ],
      '詢問': [
        '請問你對這件事情有什麼看法嗎？',
        '能不能請教你一個問題？',
        '你覺得這樣做會比較好嗎？',
        '想聽聽你的建議，你覺得呢？'
      ],
      '道歉': [
        '真的很抱歉，是我考慮不周。',
        '對不起讓你等這麼久，下次我會注意的。',
        '很抱歉造成你的困擾，我會改進的。',
        'Sorry，是我的錯，請原諒我。'
      ],
      '關心': [
        '你最近還好嗎？有什麼需要幫忙的嗎？',
        '天氣變冷了，記得多穿點衣服保暖喔！',
        '工作不要太累，記得好好休息～',
        '希望你一切都順利，有事隨時找我！'
      ],
      '分享': [
        '今天發生了一件很有趣的事情想和你分享！',
        '我剛看到一個很棒的東西，推薦給你～',
        '分享一個好消息，希望你也會開心！',
        '想和你聊聊最近的一些想法和感受。'
      ],
      '鼓勵': [
        '你一定可以的！我相信你的能力！',
        '加油！困難只是暫時的，你很棒！',
        '不要放棄，你已經做得很好了！',
        '相信自己，你比想像中還要厲害！'
      ],
    };
    
    return suggestionMap[messageType] ?? [
      '這是一個很棒的想法！',
      '我覺得你說得很有道理。',
      '謝謝你的分享，很有意思！',
      '希望我們能夠繼續保持聯繫。'
    ];
  }
  
  // 選擇AI建議並發送
  void _selectAISuggestion(String suggestion) {
    _messageController.text = suggestion;
    _resetAIAssistant();
    
    // 自動聚焦到輸入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(FocusNode());
    });
  }
  
  // 重置AI輔助狀態
  void _resetAIAssistant() {
    setState(() {
      _aiSuggestions.clear();
    });
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_onMessagesChanged);
    _scrollController.removeListener(_onScroll);
    _messageController.removeListener(_onTextInputChanged);
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
                child: Builder(
                  builder: (context) {
                    // 調試信息
                    debugPrint('[ChatPage] 構建訊息列表，緩存訊息數: ${_cachedMessages.length}');
                    
                    if (_cachedMessages.isEmpty) {
                      return const Center(
                        child: Text('目前沒有訊息，開始聊天吧！'),
                      );
                    }
                    
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8.0),
                      itemCount: _cachedMessages.length,
                      itemBuilder: (context, index) {
                        final message = _cachedMessages[index];
                        final isMe = message.sender == widget.currentUser;
                        
                        debugPrint('[ChatPage] 構建訊息 $index: ${message.content}');
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
              child: StreamBuilder<bool>(
                stream: widget.chatService.connectionStateStream,
                initialData: widget.chatService.isConnected, // 添加初始數據
                builder: (context, snapshot) {
                  final isConnected = snapshot.data ?? false;
                  
                  return Row(
                    children: [
                      // AI輔助按鈕
                      IconButton(
                        onPressed: isConnected ? _showAIAssistantDialog : null,
                        icon: const Icon(Icons.smart_toy),
                        color: isConnected 
                          ? Colors.purple 
                          : Colors.grey,
                        tooltip: 'AI輔助聊天',
                      ),
                      // 圖片上傳按鈕
                      IconButton(
                        onPressed: isConnected ? _selectAndUploadImage : null,
                        icon: const Icon(Icons.image),
                        color: isConnected 
                          ? Colors.grey.shade400  // 使用較淡的顏色表示功能暫時不可用
                          : Colors.grey,
                        tooltip: '上傳圖片 (功能開發中)',
                      ),
                      const SizedBox(width: 4),
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
    debugPrint('[ChatPage] 構建訊息氣泡: sender=${message.sender}, currentUser=${widget.currentUser}, isMe=$isMe, content=${message.content}');
    
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
    // 🌍 轉換為本地時區
    final localDateTime = dateTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(localDateTime.year, localDateTime.month, localDateTime.day);
    
    if (messageDate == today) {
      // 今天：只顯示時間
      return '${localDateTime.hour.toString().padLeft(2, '0')}:${localDateTime.minute.toString().padLeft(2, '0')}';
    } else {
      // 其他日期：顯示月/日 時間
      return '${localDateTime.month}/${localDateTime.day} ${localDateTime.hour.toString().padLeft(2, '0')}:${localDateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}
