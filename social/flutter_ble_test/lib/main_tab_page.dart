import 'package:flutter/material.dart';
import 'ble_scan_body.dart';
import 'settings_page.dart';
import 'avatar_page.dart';
import 'chat_room_list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'settings_ble_helper.dart';

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
  bool _hasChatHistory = false;

  @override
  void initState() {
    super.initState();
    _loadNicknameFromPrefs();
    _checkChatHistory();
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

  Future<void> _checkChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('chat_history') ?? [];
    setState(() {
      _hasChatHistory = history.isNotEmpty;
    });
  }

  void updateChatHistoryDisplay() {
    _checkChatHistory();
  }

  List<Widget> get _pages => [
    const BleScanBody(),
    AvatarPage(
      setAvatarThumbnailBytes: _setAvatarThumbnailBytes,
      avatarThumbnailBytes: _avatarThumbnailBytes,
    ),
    if (_hasChatHistory) const ChatRoomListPage(),
    SettingsPage(
      isAdvertising: _isAdvertising,
      onToggleAdvertise: (v) async {
        setState(() {
          _isAdvertising = v;
        });
        // 呼叫 BLE 廣播
        final nickname = _nicknameController.text;
        // 這裡可根據你的需求選擇 avatar 或 imageId 廣播
        await SettingsBleHelper.advertiseWithAvatar(
          nickname: nickname,
          avatarImageProvider: _avatarThumbnailBytes != null ? MemoryImage(_avatarThumbnailBytes!) : null,
          enable: v,
        );
        debugPrint('[MainTabPage] onToggleAdvertise: $v, nickname: $nickname');
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
    if (_hasChatHistory)
      const BottomNavigationBarItem(icon: Icon(Icons.chat), label: '聊天室'),
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
}
