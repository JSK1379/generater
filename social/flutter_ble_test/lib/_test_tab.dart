import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'chat_service_singleton.dart';
import 'user_api_service.dart';
import 'dart:async';
import 'api_config.dart';

// 使用統一的API配置
final String kTestWsServerUrl = ApiConfig.wsUrl;
const String kTestTargetUserId = '0000';


class TestTab extends StatefulWidget {
  const TestTab({super.key});

  @override
  State<TestTab> createState() => _TestTabState();
}

class _TestTabState extends State<TestTab> {
  final TextEditingController _targetUserIdController = TextEditingController(text: kTestTargetUserId);
  String _wsLog = '';
  String _currentUserId = 'unknown_user';
  bool _disposed = false;
  Timer? _logUpdateTimer;

  @override
  void initState() {
    super.initState();
    // 不再直接監聽 WebSocket 消息，改為從 ChatServiceSingleton 獲取消息更新
    // 添加連接回應監聽器
    ChatServiceSingleton.instance.addConnectResponseListener(_onConnectResponse);
    _loadCurrentUserId();
    _disposed = false;
    
    // 設置定時器，每5秒更新一次日誌顯示（進一步降低頻率）
    _logUpdateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_disposed) {
        final chatService = ChatServiceSingleton.instance;
        String newLog = '';
        
        if (chatService.isConnected) {
          if (chatService.currentRoom != null) {
            final recentMessages = chatService.messages;
            if (recentMessages.isNotEmpty) {
              final lastMsg = recentMessages.last;
              newLog = '最近消息: {type: message, sender: ${lastMsg.sender}, content: ${lastMsg.content}}';
            } else {
              newLog = '已連接到房間 ${chatService.currentRoom!.name}，暫無訊息';
            }
          } else {
            newLog = 'WebSocket 已連接，等待加入聊天室...';
          }
        } else {
          newLog = '尚未連接到 WebSocket 服務器';
        }
        
        // 只有當日誌內容變化時才更新 UI
        if (newLog != _wsLog) {
          setState(() {
            _wsLog = newLog;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    // 取消定時器
    _logUpdateTimer?.cancel();
    // 移除連接回應監聽器
    ChatServiceSingleton.instance.removeConnectResponseListener(_onConnectResponse);
    _targetUserIdController.dispose();
    super.dispose();
  }

  // 手動刷新日誌顯示
  void _refreshLog() {
    final chatService = ChatServiceSingleton.instance;
    String newLog = '';
    
    if (chatService.isConnected) {
      if (chatService.currentRoom != null) {
        final recentMessages = chatService.messages;
        if (recentMessages.isNotEmpty) {
          final lastMsg = recentMessages.last;
          newLog = '最近消息: {type: message, sender: ${lastMsg.sender}, content: ${lastMsg.content}}';
        } else {
          newLog = '已連接到房間 ${chatService.currentRoom!.name}，暫無訊息';
        }
      } else {
        newLog = 'WebSocket 已連接，等待加入聊天室...';
      }
    } else {
      newLog = '尚未連接到 WebSocket 服務器';
    }
    
    setState(() {
      _wsLog = newLog;
    });
  }

  /// 連接後自動發送連接要求並創建聊天室
  Future<void> _connectAndCreateRoom(BuildContext context) async {
    if (!context.mounted) return;
    await _sendConnectRequest(context);
    if (!context.mounted) return;
    await _createRoom(context);
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

  // 處理連接回應
  void _onConnectResponse(String from, String to, bool accept) {
    if (!mounted || _disposed) return;
    
    // 只處理回應給自己的消息（我是接收方）
    if (to != _currentUserId) return;
    
    // 如果被拒絕，顯示提示
    if (!accept) {
      // 使用安全的方式顯示 UI
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('你好像被拒絕了;;', style: TextStyle(fontSize: 16)),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      });
    }
  }

  Future<void> _sendConnectRequest(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final myUserId = prefs.getString('user_id') ?? 'unknown_user';
    final chatService = ChatServiceSingleton.instance;
    final targetUserId = _targetUserIdController.text.trim();
    if (targetUserId.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請輸入目標 userId')),
        );
      }
      return;
    }
    
    // 🔄 優化連線邏輯：只在需要時連線，避免重複
    if (!chatService.isConnected) {
      debugPrint('[TestTab] WebSocket未連線，開始連線...');
      await chatService.connectAndRegister(kTestWsServerUrl, 'test_room', myUserId);
    } else {
      debugPrint('[TestTab] WebSocket已連線，確保用戶註冊...');
      chatService.ensureUserRegistered(myUserId);
    }
    
    debugPrint('[TestTab] 發送連接要求: $myUserId -> $targetUserId');
    chatService.sendConnectRequest(myUserId, targetUserId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已發送連接要求給 $targetUserId')),
    );
  }

  Future<void> _createRoom(BuildContext context) async {
    final roomName = await _showInputDialog(context, '請輸入聊天室名稱');
    if (roomName == null || roomName.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final myUserId = prefs.getString('user_id') ?? 'unknown_user';
    final chatService = ChatServiceSingleton.instance;
    
    // 🔄 優化連線邏輯，避免重複連線
    if (!chatService.isConnected) {
      debugPrint('[TestTab] WebSocket未連線，開始連線建立房間...');
      await chatService.connectAndRegister(kTestWsServerUrl, 'test_room', myUserId);
    } else {
      debugPrint('[TestTab] WebSocket已連線，確保用戶註冊後建立房間...');
      // 確保用戶已註冊
      chatService.ensureUserRegistered(myUserId);
    }
    
    debugPrint('[TestTab] 開始建立房間: $roomName');
    final roomId = await chatService.createRoom(roomName);
    debugPrint('[TestTab] createRoom 回傳的 roomId: $roomId');
    String joinMsg = '';
    if (roomId != null) {
      debugPrint('[TestTab] roomId 不為 null，準備 joinRoom');
      
      // 不再保存聊天室歷史，由 joined_room 事件處理
      
      // 檢查是否已加入此房間
      if (chatService.chatRooms.any((room) => room.id == roomId)) {
        debugPrint('[TestTab] 房間 $roomId 已存在於聊天室列表中，跳過 joinRoom');
        joinMsg = '\n房間 $roomId 已存在，無需再次加入';
      } else {
        // 先發送 joinRoom 請求
        chatService.joinRoom(roomId).then((success) {
          debugPrint('[TestTab] joinRoom 完成: $success');
        });
        joinMsg = '\n已自動發送 join_room: {"type": "join_room", "roomId": "$roomId"}';
      }
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
      final userApiService = UserApiService(ApiConfig.baseUrl);
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

  // 上傳當前GPS位置
  Future<void> _uploadCurrentGPS(BuildContext context) async {
    try {
      // 檢查定位權限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('請授權定位權限才能上傳GPS位置')),
            );
          }
          return;
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在獲取GPS位置...')),
        );
      }

      // 獲取當前位置
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      );

      // 準備上傳數據 - 使用新的API格式
      final url = Uri.parse('${ApiConfig.gpsLocation}?user_id=$_currentUserId');
      final body = jsonEncode({
        'lat': position.latitude,
        'lng': position.longitude,
        'ts': DateTime.now().toIso8601String(),
      });

      final res = await http.post(
        url,
        body: body,
        headers: ApiConfig.jsonHeaders,
      );

      debugPrint('當前GPS位置上傳結果: ${res.statusCode} ${res.body}');
      
      if (context.mounted) {
        if (res.statusCode == 200) {
          final responseData = jsonDecode(res.body);
          debugPrint('✅ 當前GPS位置上傳成功');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'GPS定位記錄成功!\n'
                '用戶ID: $_currentUserId\n'
                '記錄ID: ${responseData['id']}\n'
                '緯度: ${position.latitude.toStringAsFixed(6)}\n'
                '經度: ${position.longitude.toStringAsFixed(6)}\n'
                '時間: ${DateTime.now().toString().substring(0, 19)}'
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          debugPrint('❌ 當前GPS位置上傳失敗: ${res.statusCode}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('GPS定位記錄失敗: ${res.statusCode}')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ 當前GPS位置上傳異常: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS定位記錄失敗: $e')),
        );
      }
    }
  }

  // 獲取今日GPS歷史記錄
  Future<void> _getTodayGPSHistory(BuildContext context) async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final url = Uri.parse(ApiConfig.gpsUserLocationsByDate(_currentUserId, today));
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在獲取今日GPS記錄...')),
        );
      }

      final res = await http.get(url, headers: ApiConfig.jsonHeaders);
      
      debugPrint('今日GPS歷史查詢結果: ${res.statusCode} ${res.body}');
      
      if (context.mounted) {
        if (res.statusCode == 200) {
          final responseData = jsonDecode(res.body);
          final totalLocations = responseData['total_locations'] ?? 0;
          final locations = responseData['locations'] as List? ?? [];
          
          debugPrint('✅ 今日GPS歷史獲取成功');
          
          String locationDetails = '';
          if (locations.isNotEmpty) {
            final firstLocation = locations.first;
            final lastLocation = locations.last;
            locationDetails = '\n最新記錄: (${firstLocation['latitude']}, ${firstLocation['longitude']})'
                             '\n最早記錄: (${lastLocation['latitude']}, ${lastLocation['longitude']})';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '今日GPS記錄查詢成功!\n'
                '用戶ID: $_currentUserId\n'
                '日期: $today\n'
                '記錄總數: $totalLocations$locationDetails'
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        } else if (res.statusCode == 404) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('今日還沒有GPS記錄')),
          );
        } else {
          debugPrint('❌ 今日GPS歷史獲取失敗: ${res.statusCode}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('GPS記錄查詢失敗: ${res.statusCode}')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ 今日GPS歷史獲取異常: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS記錄查詢失敗: $e')),
        );
      }
    }
  }

  // _saveChatRoomHistory 方法已移除，因為沒有被使用

  Future<Map<String, String>?> _showEmailPasswordDialog(BuildContext context) async {
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

  Future<String?> _showInputDialog(BuildContext context, String title, [String? initialValue]) async {
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('伺服器回傳：', style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: _refreshLog,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_wsLog, maxLines: 6, overflow: TextOverflow.ellipsis),
            ),
            Row(
              children: [
                const Text('目標 userId: '),
                Expanded(
                  child: TextField(
                    controller: _targetUserIdController,
                    decoration: const InputDecoration(hintText: '請輸入目標 userId'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _sendConnectRequest(context),
                  child: const Text('發送連接要求'),
                ),
              ],
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
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _uploadCurrentGPS(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('上傳當前GPS'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _getTodayGPSHistory(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('查看今日GPS記錄'),
            ),
          ],
        ),
      ),
    );
  }
}
