import 'package:flutter/material.dart';
import 'ble_scan_body.dart';
import 'settings_page.dart';
import 'avatar_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainTabPage extends StatefulWidget {
  const MainTabPage({super.key});
  @override
  State<MainTabPage> createState() => MainTabPageState();
}

class MainTabPageState extends State<MainTabPage> {
  int currentIndex = 0;
  final bool _isAdvertising = false;
  final TextEditingController _nicknameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNicknameFromPrefs();
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

  List<Widget> get _pages => [
    const BleScanBody(),
    const AvatarPage(),
    SettingsPage(
      isAdvertising: _isAdvertising,
      onToggleAdvertise: (v) async { return; }, // 由 SettingsPage 處理
      nicknameController: _nicknameController,
      setAvatarThumbnailBytes: (_) {},
      avatarThumbnailBytes: null,
      onSaveNickname: _saveNicknameToPrefs,
    ),
  ];

  final List<BottomNavigationBarItem> _items = const [
    BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: '藍牙'),
    BottomNavigationBarItem(icon: Icon(Icons.face), label: 'Avatar'),
    BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設置'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        items: _items,
        onTap: (i) => setState(() => currentIndex = i),
      ),
    );
  }
}
