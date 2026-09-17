import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'ble_scan_body.dart';
import 'chat_models.dart';
import 'chat_page.dart';
import 'chat_room_list_page.dart';
import 'chat_room_open_manager.dart';
import 'chat_service_singleton.dart';
import 'settings_ble_helper.dart';
import 'settings_page.dart';
import 'user_api_service.dart';

class MainTabPage extends StatefulWidget {
  const MainTabPage({super.key});

  @override
  State<MainTabPage> createState() => MainTabPageState();
}

class MainTabPageState extends State<MainTabPage> {
  int currentIndex = 0;
  bool _isAdvertising = false;
  final TextEditingController _nicknameController = TextEditingController();
  final ChatRoomOpenManager _openManager = ChatRoomOpenManager();
  late final UserApiService _userApiService;

  @override
  void initState() {
    super.initState();
    _userApiService = UserApiService(ApiConfig.baseUrl);
    _loadNickname();
    ChatServiceSingleton.instance.addConnectRequestListener(_handleConnectRequest);
    ChatServiceSingleton.instance.webSocketService.addMessageListener(_onWsMessage);
  }

  @override
  void dispose() {
    ChatServiceSingleton.instance.removeConnectRequestListener(_handleConnectRequest);
    ChatServiceSingleton.instance.webSocketService.removeMessageListener(_onWsMessage);
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _loadNickname() async {
    final prefs = await SharedPreferences.getInstance();
    _nicknameController.text = prefs.getString('nickname') ?? '';
  }

  Future<void> _saveNickname(String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nickname', nickname);
  }

  void updateChatHistoryDisplay() => setState(() {});

  List<Widget> get _pages => [
        const BleScanBody(),
        const ChatRoomListPage(),
        SettingsPage(
          isAdvertising: _isAdvertising,
          onToggleAdvertise: _toggleAdvertise,
          nicknameController: _nicknameController,
          onSaveNickname: _saveNickname,
        ),
      ];

  List<BottomNavigationBarItem> get _items => const [
        BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: '藍牙'),
        BottomNavigationBarItem(icon: Icon(Icons.chat), label: '聊天室'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設定'),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _pages[currentIndex]),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: currentIndex,
        items: _items,
        onTap: (index) => setState(() => currentIndex = index),
      ),
    );
  }

  Future<void> _toggleAdvertise(bool enabled) async {
    setState(() => _isAdvertising = enabled);
    final chatService = ChatServiceSingleton.instance;
    final userId = await chatService.getCurrentUserId();
    await SettingsBleHelper.advertiseWithUserId(
      nickname: _nicknameController.text,
      userId: userId,
      imageId: '',
      enable: enabled,
    );
  }

  Future<Map<String, dynamic>?> _fetchUserProfile(String userId) async {
    try {
      return await _userApiService.getUserProfile(userId);
    } catch (error) {
      debugPrint('[MainTabPage] fetch profile failed: $error');
      return null;
    }
  }

  String _genderText(String? gender) {
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

  Future<void> _handleConnectRequest(String fromUserId, String toUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('user_id') ?? 'unknown_user';
    if (toUserId != currentUserId || !mounted) return;

    final profile = await _fetchUserProfile(fromUserId);
    if (!mounted) return;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('收到連接請求'),
        content: _ConnectionProfile(profile: profile, genderText: _genderText),
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

    ChatServiceSingleton.instance.sendConnectResponse(
      currentUserId,
      fromUserId,
      accepted == true,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(accepted == true ? '已接受連接請求' : '已拒絕連接請求')),
    );
  }

  Future<void> _saveChatRoomHistory(
    String roomId,
    String roomName,
    String otherUserId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    String otherNickname = otherUserId;

    try {
      for (final jsonText in prefs.getStringList('connection_history') ?? <String>[]) {
        final data = jsonDecode(jsonText);
        if (data['userId'] == otherUserId && data['nickname'] != null) {
          otherNickname = data['nickname'];
          break;
        }
      }
    } catch (error) {
      debugPrint('[MainTabPage] read nickname failed: $error');
    }

    final info = ChatRoomHistory(
      roomId: roomId,
      roomName: roomName.isNotEmpty ? roomName : '與 $otherNickname 的聊天室',
      lastMessage: '',
      lastMessageTime: DateTime.now(),
      otherUserId: otherUserId,
      otherNickname: otherNickname,
    );

    await prefs.setString('chat_room_info_$roomId', jsonEncode(info.toJson()));
    final roomIds = prefs.getStringList('room_ids') ?? <String>[];
    if (!roomIds.contains(roomId)) {
      roomIds.add(roomId);
      await prefs.setStringList('room_ids', roomIds);
    }
  }

  Future<void> _onWsMessage(Map<String, dynamic> data) async {
    final type = data['type'];

    if (type == 'joined_room' && data['roomId'] != null) {
      await _handleJoinedRoom(data);
      return;
    }

    if (type == 'connect_response' &&
        data['accept'] == true &&
        data['roomId'] != null) {
      await _handleAcceptedConnection(data);
    }
  }

  Future<void> _handleJoinedRoom(Map<String, dynamic> data) async {
    final roomId = data['roomId'].toString();
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('user_id') ?? 'unknown_user';
    final roomName = data['roomName']?.toString() ?? '聊天室 $roomId';
    final otherUserId = data['otherUserId']?.toString() ??
        data['from']?.toString() ??
        '未知用戶';

    await _saveChatRoomHistory(roomId, roomName, otherUserId);
    if (!mounted) return;
    ChatRoomListPage.refresh?.call();
    _navigateToChatPage(roomId, currentUserId);
  }

  Future<void> _handleAcceptedConnection(Map<String, dynamic> data) async {
    if (data['error'] != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('連接錯誤: ${data['error']}')),
        );
      }
      return;
    }

    final roomId = data['roomId'].toString();
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('user_id') ?? 'unknown_user';
    final fromUser = data['from']?.toString() ?? '';
    final toUser = data['to']?.toString() ?? '';
    final otherUserId = fromUser == currentUserId ? toUser : fromUser;

    await _saveChatRoomHistory(roomId, '與 $otherUserId 的聊天', otherUserId);

    final chatService = ChatServiceSingleton.instance;
    await chatService.fetchChatHistoryHttp(roomId);
    final joined = await chatService.joinRoom(roomId);
    if (!mounted) return;

    if (!joined) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('加入聊天室失敗')),
      );
      return;
    }

    ChatRoomListPage.refresh?.call();
    _navigateToChatPage(roomId, currentUserId);
  }

  void _navigateToChatPage(String roomId, String currentUserId) {
    if (!_openManager.markRoomAsOpening(roomId)) return;

    ChatServiceSingleton.instance
        .getChatRoomDisplayName(roomId, currentUserId)
        .then((roomName) {
      if (!mounted) {
        _openManager.markRoomAsClosed(roomId);
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            roomId: roomId,
            roomName: roomName,
            currentUser: currentUserId,
            chatService: ChatServiceSingleton.instance,
          ),
        ),
      ).whenComplete(() => _openManager.markRoomAsClosed(roomId));
    }).catchError((error) {
      _openManager.markRoomAsClosed(roomId);
      debugPrint('[MainTabPage] open room failed: $error');
    });
  }
}

class _ConnectionProfile extends StatelessWidget {
  const _ConnectionProfile({
    required this.profile,
    required this.genderText,
  });

  final Map<String, dynamic>? profile;
  final String Function(String?) genderText;

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return const Text('無法取得對方資料，是否仍接受連接？');
    }

    final hobbies = profile!['hobbies'] as List? ?? const [];
    final avatarUrl = profile!['avatar_url']?.toString() ?? '';

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 44,
            backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl.isEmpty ? const Icon(Icons.person, size: 44) : null,
          ),
          const SizedBox(height: 12),
          Text(
            profile!['nickname']?.toString() ?? '未知用戶',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(genderText(profile!['gender']?.toString())),
          if (profile!['age'] != null) Text('${profile!['age']} 歲'),
          if (hobbies.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: hobbies
                  .map((hobby) => Chip(label: Text(hobby['name']?.toString() ?? '未知')))
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          const Text('是否接受連接請求？'),
        ],
      ),
    );
  }
}
