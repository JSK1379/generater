import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'chat_service.dart';
import 'chat_models.dart';
import 'chat_room_open_manager.dart'; // 導入全局管理器
import 'api_config.dart';
import 'user_api_service.dart'; // 導入用戶 API 服務

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
  late UserApiService _userApiService; // 用戶 API 服務
  
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

  @override
  void initState() {
    super.initState();
    
    // 初始化用戶 API 服務
    _userApiService = UserApiService(ApiConfig.baseUrl);
    
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
      
      // 發送用戶訊息
      widget.chatService.sendTextMessage(
        widget.roomId,
        widget.currentUser,
        text,
      );
      
      // 檢查是否需要觸發 AI 回應
      if (widget.chatService.shouldTriggerAI(text)) {
        // 異步發送 AI 訊息，不阻塞用戶界面
        widget.chatService.sendAIMessage(widget.roomId, text);
      }
      
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
    // 檢查 AI 服務是否可用
    if (!widget.chatService.isAIServiceAvailable) {
      _showAIConfigurationDialog();
      return;
    }
    
    // 顯示 AI 功能選擇對話框
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildAIAssistantBottomSheet(),
    );
  }
  
  // 構建 AI 助手底部彈窗
  Widget _buildAIAssistantBottomSheet() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 標題
          Row(
            children: [
              const Icon(Icons.smart_toy, color: Colors.purple, size: 28),
              const SizedBox(width: 12),
              const Text(
                '🤖 AI 助手',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // AI 功能選項
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.0, // 調整為 2.0，增加卡片高度
            children: [
              _buildAIOptionCard(
                icon: Icons.reply,
                title: '回覆建議',
                subtitle: '生成回覆建議',
                onTap: () => _generateReplySuggestion(),
              ),
              _buildAIOptionCard(
                icon: Icons.summarize,
                title: '對話總結',
                subtitle: '總結聊天內容',
                onTap: () => _generateChatSummary(),
              ),
              _buildAIOptionCard(
                icon: Icons.person_search,
                title: '個性化建議',
                subtitle: '基於雙方資料建議',
                onTap: () => _generatePersonalizedSuggestion(),
              ),
              _buildAIOptionCard(
                icon: Icons.emoji_emotions,
                title: '情緒分析',
                subtitle: '分析訊息情緒',
                onTap: () => _showEmotionAnalysis(),
              ),
              _buildAIOptionCard(
                icon: Icons.settings,
                title: 'AI 設定',
                subtitle: '調整 AI 個性',
                onTap: () => _showAISettings(),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // 提示文字
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '💡 提示：在訊息中使用 @ai、@助手、? 等關鍵字可自動觸發 AI 回應',
              style: TextStyle(fontSize: 12, color: Colors.blue),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
  
  // 構建 AI 選項卡片
  Widget _buildAIOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8), // 減少 padding 從 12 到 8
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.purple, size: 20), // 減少圖示大小
              const SizedBox(height: 3), // 減少間距
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11), // 略微減少字體大小
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1), // 減少間距
              Expanded( // 使用 Expanded 而不是 Flexible，確保利用所有可用空間
                child: Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 9), // 略微減少字體大小
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // 顯示 AI 提問對話框
  void _generateReplySuggestion() async {
    Navigator.pop(context); // 關閉底部彈窗
    
    // 取得最近的幾條訊息作為上下文
    final messages = widget.chatService.getMessagesForRoom(widget.roomId);
    if (messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('沒有對話內容可以分析')),
      );
      return;
    }
    
    // 顯示載入中
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('🤖 AI 正在生成回覆建議...'),
          ],
        ),
      ),
    );
    
    try {
      // 檢查是否有對話內容
      final messages = widget.chatService.getMessagesForRoom(widget.roomId);
      final userMessages = messages.where((msg) => !msg.sender.startsWith('ai_')).toList();
      
      String suggestion;
      if (userMessages.isEmpty) {
        // 沒有對話內容時，生成問候語
        suggestion = await widget.chatService.generateReplySuggestion(
          widget.roomId, 
          '請生成一條友善的問候語來開始對話', // 明確指示生成問候語
          widget.currentUser
        );
      } else {
        // 有對話內容時，生成回覆建議
        suggestion = await widget.chatService.generateReplySuggestion(
          widget.roomId, 
          '', // 空字符串，因為 ChatService 會自己分析訊息
          widget.currentUser
        );
      }
      
      // 關閉載入對話框
      if (mounted) Navigator.pop(context);
      
      if (suggestion.isNotEmpty) {
        // 將建議填入打字欄
        setState(() {
          _messageController.text = suggestion;
        });
        
        // 顯示成功提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ 回覆建議已填入打字欄')),
          );
          
          // 聚焦到輸入框
          FocusScope.of(context).requestFocus();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ 無法生成回覆建議')),
          );
        }
      }
    } catch (e) {
      // 關閉載入對話框
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 生成回覆建議失敗: $e')),
        );
      }
    }
  }
  
  // 生成聊天總結
  void _generateChatSummary() async {
    Navigator.pop(context); // 關閉底部彈窗
    
    // 檢查是否有足夠的訊息進行總結
    final messages = widget.chatService.getMessagesForRoom(widget.roomId);
    final userMessages = messages.where((msg) => !msg.sender.startsWith('ai_')).toList();
    
    if (userMessages.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要至少3條用戶訊息才能進行總結分析')),
      );
      return;
    }
    
    // 顯示載入中
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('AI 正在分析對話內容...'),
          ],
        ),
      ),
    );
    
    try {
      final summary = await widget.chatService.generateChatSummary(widget.roomId);
      
      if (mounted) {
        Navigator.pop(context); // 關閉載入對話框
        
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.summarize, color: Colors.blue),
                SizedBox(width: 8),
                Text('📊 對話總結'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '基於最近 ${userMessages.length} 條訊息的分析：',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Text(summary),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '💡 提示：可以要求 AI 基於這個總結提供更多建議',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('關閉'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.chatService.sendAIMessage(widget.roomId, '請基於這個對話總結，為我提供一些有用的回覆建議和對話方向：$summary');
                },
                child: const Text('請 AI 提供建議'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 關閉載入對話框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成總結失敗：$e')),
        );
      }
    }
  }
  
  // 生成個性化建議
  void _generatePersonalizedSuggestion() async {
    Navigator.pop(context); // 關閉底部彈窗
    
    // 顯示載入中
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('🤖 AI 正在分析雙方資料並生成個性化建議...'),
          ],
        ),
      ),
    );
    
    try {
      // 使用房間ID提取雙方用戶ID (格式: room_user1_user2)
      final roomParts = widget.roomId.split('_');
      String otherUserId = '';
      if (roomParts.length >= 3) {
        final user1 = roomParts[1];
        final user2 = roomParts[2];
        otherUserId = (user1 == widget.currentUser) ? user2 : user1;
      }
      
      // 並行獲取雙方用戶資料
      final currentUserProfile = await _userApiService.getUserProfile(widget.currentUser);
      final otherUserProfile = await _userApiService.getUserProfile(otherUserId);
      
      // 獲取對話歷史
      final messages = widget.chatService.getMessagesForRoom(widget.roomId);
      final conversationHistory = messages
          .take(10) // 取最近10條訊息作為參考
          .map((msg) => '${msg.sender}: ${msg.content}')
          .join('\n');
      
      // 構建詳細的用戶資料描述
      String currentUserInfo = _buildUserInfoString(currentUserProfile, '當前用戶');
      String otherUserInfo = _buildUserInfoString(otherUserProfile, '對方用戶');
      
      // 構建包含雙方資料和對話歷史的提示
      final prompt = '''
請基於以下詳細資料為聊天提供個性化建議：

=== 用戶資料 ===
$currentUserInfo

$otherUserInfo

=== 最近對話記錄 ===
$conversationHistory

=== 請提供以下建議 ===
1. 基於雙方的興趣愛好、年齡和背景，推薦3-5個有趣且合適的話題
2. 分析當前對話氛圍並建議如何保持良好互動
3. 根據對方的興趣，推薦一些個性化的回覆方式或問題
4. 建議適合雙方的見面活動或深入交流的方式
5. 如果對話顯得冷淡，提供破冰或重新點燃興趣的方法

請用友善、自然的語調回覆，確保建議實用且符合雙方的個性特點。
''';
      
      // 發送給 AI 處理
      await widget.chatService.sendAIMessage(widget.roomId, prompt);
      
      if (mounted) {
        Navigator.pop(context); // 關閉載入對話框
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ AI 已基於雙方資料生成個性化建議，請查看聊天訊息'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 關閉載入對話框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成個性化建議失敗：$e')),
        );
      }
    }
  }
  
  // 構建用戶資料字符串
  String _buildUserInfoString(Map<String, dynamic>? userProfile, String label) {
    if (userProfile == null) {
      return '$label: 資料獲取失敗';
    }
    
    final nickname = userProfile['nickname'] ?? '未知';
    final age = userProfile['age']?.toString() ?? '未知';
    final gender = _getGenderText(userProfile['gender']);
    
    String info = '$label: $nickname (年齡: $age, 性別: $gender)';
    
    // 添加興趣愛好
    if (userProfile['hobbies'] != null && (userProfile['hobbies'] as List).isNotEmpty) {
      final hobbies = (userProfile['hobbies'] as List)
          .map((hobby) => hobby['name'] ?? '未知')
          .join(', ');
      info += '\n興趣愛好: $hobbies';
    }
    
    // 添加自定義興趣描述
    if (userProfile['custom_hobby_description'] != null &&
        userProfile['custom_hobby_description'].toString().isNotEmpty) {
      info += '\n其他興趣: ${userProfile['custom_hobby_description']}';
    }
    
    return info;
  }
  
  // 獲取性別文字
  String _getGenderText(String? gender) {
    switch (gender) {
      case 'male':
        return '男性';
      case 'female':
        return '女性';
      case 'other':
        return '其他';
      default:
        return '未設定';
    }
  }
  
  // 顯示情緒分析
  void _showEmotionAnalysis() async {
    Navigator.pop(context); // 關閉底部彈窗
    
    // 獲取最近的用戶訊息進行分析
    final messages = widget.chatService.getMessagesForRoom(widget.roomId);
    final recentUserMessages = messages
        .where((msg) => !msg.sender.startsWith('ai_'))
        .take(5)
        .toList();
    
    if (recentUserMessages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('沒有用戶訊息可以分析')),
      );
      return;
    }
    
    // 顯示載入中
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('🤖 AI 正在分析對話情緒...'),
          ],
        ),
      ),
    );
    
    try {
      // 準備分析內容
      final analysisContent = recentUserMessages
          .map((msg) => '${msg.sender}: ${msg.content}')
          .join('\n');
      
      // 生成情緒分析
      final analysis = await widget.chatService.generateEmotionAnalysis(
        widget.roomId,
        analysisContent,
        widget.currentUser
      );
      
      if (mounted) {
        Navigator.pop(context); // 關閉載入對話框
        
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.emoji_emotions, color: Colors.orange),
                SizedBox(width: 8),
                Text('😊 情緒分析'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '基於最近 ${recentUserMessages.length} 條訊息的情緒分析：',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Text(analysis),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '💡 提示：可以要求 AI 根據情緒分析提供溝通建議',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('關閉'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.chatService.sendAIMessage(
                    widget.roomId, 
                    '基於剛才的情緒分析，請為我提供一些溝通建議和適合的回覆方式：$analysis'
                  );
                },
                child: const Text('請 AI 提供溝通建議'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // 關閉載入對話框
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('情緒分析失敗：$e')),
        );
      }
    }
  }
  
  // 顯示 AI 設定
  void _showAISettings() {
    Navigator.pop(context); // 關閉底部彈窗
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.green),
            SizedBox(width: 8),
            Text('⚙️ AI 設定'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('選擇 AI 個性：', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...widget.chatService.getAvailableAIPersonalities().map((personality) {
              return RadioListTile<String>(
                title: Text(_getPersonalityDisplayName(personality)),
                subtitle: Text(_getPersonalityDescription(personality)),
                value: personality,
                groupValue: widget.chatService.getCurrentAIPersonality(),
                onChanged: (value) {
                  if (value != null) {
                    widget.chatService.setAIPersonality(value);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('AI 個性已切換至：${_getPersonalityDisplayName(value)}')),
                    );
                  }
                },
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }
  
  // 獲取個性顯示名稱
  String _getPersonalityDisplayName(String personality) {
    switch (personality) {
      case 'default': return '🤖 預設';
      case 'funny': return '😄 幽默';
      case 'professional': return '💼 專業';
      case 'casual': return '😊 輕鬆';
      default: return personality;
    }
  }
  
  // 獲取個性描述
  String _getPersonalityDescription(String personality) {
    switch (personality) {
      case 'default': return '友善、樂於助人';
      case 'funny': return '幽默風趣，喜歡開玩笑';
      case 'professional': return '專業正式，提供詳細信息';
      case 'casual': return '輕鬆隨意，像朋友聊天';
      default: return '';
    }
  }
  
  // 顯示 AI 配置對話框
  void _showAIConfigurationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('⚠️ AI 功能未配置'),
          ],
        ),
        content: const Text(
          'AI 功能需要配置 Google Gemini API Key 才能使用。\n\n'
          '請在 lib/gemini_service.dart 文件中設定您的 API Key。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
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
                            hintText: isConnected 
                                ? '輸入訊息... (使用 @ai 呼叫 AI 助手)' 
                                : '連線中，請稍候...',
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
    
    // 檢查是否為 AI 訊息
    final isAI = message.sender.startsWith('ai_');
    
    return Align(
      alignment: isMe ? Alignment.centerRight : (isAI ? Alignment.centerLeft : Alignment.centerLeft),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // 發送者暱稱和時間
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isAI) ...[
                      const Icon(Icons.smart_toy, size: 14, color: Colors.purple),
                      const SizedBox(width: 4),
                    ],
                    FutureBuilder<String>(
                      future: widget.chatService.getUserNickname(message.sender),
                      builder: (context, snapshot) {
                        final displayName = isAI ? '🤖 AI 助手' : (snapshot.data ?? message.sender);
                        return Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: isAI ? Colors.purple : Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            
            // 訊息氣泡
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe 
                    ? Theme.of(context).primaryColor 
                    : (isAI ? Colors.purple.shade50 : Colors.grey.shade200),
                border: isAI ? Border.all(color: Colors.purple.shade200, width: 1) : null,
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
