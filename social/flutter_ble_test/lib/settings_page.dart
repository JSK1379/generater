import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'main_tab_page.dart';
import 'settings_ble_helper.dart';
import 'image_api_service.dart';
import 'chat_page.dart';
import 'chat_service.dart';

class SettingsPage extends StatefulWidget {
  final bool isAdvertising;
  final Future<void> Function(bool) onToggleAdvertise;
  final TextEditingController nicknameController;
  final void Function(Uint8List?) setAvatarThumbnailBytes;
  final Uint8List? avatarThumbnailBytes;
  final Future<void> Function(String) onSaveNickname;
  const SettingsPage({
    super.key,
    required this.isAdvertising,
    required this.onToggleAdvertise,
    required this.nicknameController,
    required this.setAvatarThumbnailBytes,
    required this.avatarThumbnailBytes,
    required this.onSaveNickname,
  });
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ImageProvider? _avatarImageProvider;
  final ImagePicker _picker = ImagePicker();
  Timer? _autoCommuteTimer;
  bool _autoTracking = false;
  TimeOfDay? _commuteStartMorning;
  TimeOfDay? _commuteEndMorning;
  TimeOfDay? _commuteStartEvening;
  TimeOfDay? _commuteEndEvening;
  bool _isTrackingCommute = false;
  final List<Map<String, dynamic>> _commuteRoute = [];
  Timer? _commuteTimer;
  bool _isAdvertising = false;

  final ImageApiService _imageApiService = ImageApiService();
  String? _mockImageUrl;
  String? _userId;

  Future<void> _pickAvatarFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      final dir = await getApplicationDocumentsDirectory();
      final avatarFile = File('${dir.path}/avatar.png');
      await File(image.path).copy(avatarFile.path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('avatar_path', avatarFile.path);
      if (!mounted) return;
      setState(() {
        _avatarImageProvider = FileImage(avatarFile);
      });
    }
  }

  Future<void> _loadAvatarFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('avatar_path');
    if (path != null && await File(path).exists()) {
      setState(() {
        _avatarImageProvider = FileImage(File(path));
      });
    } else {
      setState(() {
        _avatarImageProvider = null; // 使用預設圖示
      });
    }
  }

  void _autoCheckCommutePeriod() {
    bool inPeriod = _isNowInCommutePeriod();
    if (inPeriod && !_isTrackingCommute) {
      _autoTracking = true;
      _startCommuteTracking();
    } else if (!inPeriod && _isTrackingCommute && _autoTracking) {
      _autoTracking = false;
      _stopCommuteTracking();
      uploadCommuteRoute();
    }
  }

  bool _isNowInCommutePeriod() {
    final now = TimeOfDay.now();
    bool inMorning = _commuteStartMorning != null && _commuteEndMorning != null &&
      (_commuteStartMorning!.hour < now.hour || (_commuteStartMorning!.hour == now.hour && _commuteStartMorning!.minute <= now.minute)) &&
      (now.hour < _commuteEndMorning!.hour || (now.hour == _commuteEndMorning!.hour && now.minute <= _commuteEndMorning!.minute));
    bool inEvening = _commuteStartEvening != null && _commuteEndEvening != null &&
      (_commuteStartEvening!.hour < now.hour || (_commuteStartEvening!.hour == now.hour && _commuteStartEvening!.minute <= now.minute)) &&
      (now.hour < _commuteEndEvening!.hour || (now.hour == _commuteEndEvening!.hour && now.minute <= _commuteEndEvening!.minute));
    return inMorning || inEvening;
  }

  @override
  void initState() {
    super.initState();
    // 優先使用傳入的 avatarThumbnailBytes，沒有的話才載入本地偏好設定
    if (widget.avatarThumbnailBytes != null) {
      setState(() {
        _avatarImageProvider = MemoryImage(widget.avatarThumbnailBytes!);
      });
    } else {
      _loadAvatarFromPrefs();
    }
    _autoCommuteTimer = Timer.periodic(const Duration(minutes: 1), (_) => _autoCheckCommutePeriod());
    
    // 設定連接請求回調
    SettingsBleHelper.setOnConnectionRequestCallback((nickname, imageId, deviceId) {
      _showIncomingConnectionDialog(nickname, imageId, deviceId);
    });
    _loadUserId();
  }
  
  Future<void> _showIncomingConnectionDialog(String nickname, String imageId, String deviceId) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('收到連接請求'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('對方暱稱: $nickname'),
            Text('裝置ID: ${deviceId.substring(0, 8)}...'),
            if (imageId.isNotEmpty) Text('圖片ID: $imageId'),
            const SizedBox(height: 16),
            if (imageId.isNotEmpty && _mockImageUrl != null)
              Image.network(_imageApiService.getImageUrl(imageId), width: 100, height: 100),
          ],
        ),
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

    if (!mounted) return;
    if (result == true) {
      // 用戶接受連接，開啟聊天室
      final chatService = ChatService();
      final currentUserId = await chatService.getCurrentUserId();
      final roomId = chatService.generateRoomId(currentUserId, deviceId);
      
      // 儲存聊天室歷史
      await _saveChatRoomHistory(roomId, '與 $nickname 的聊天', deviceId);
      
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            roomId: roomId,
            roomName: '與 $nickname 的聊天',
            currentUser: currentUserId,
            chatService: chatService,
          ),
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已接受 $nickname 的連接請求')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已拒絕連接請求')),
      );
    }
  }

  Future<void> _saveChatRoomHistory(String roomId, String roomName, String otherUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList('chat_history') ?? [];
    
    // 檢查是否已存在
    final exists = historyJson.any((jsonStr) {
      final data = jsonDecode(jsonStr);
      return data['roomId'] == roomId;
    });
    
    if (!exists) {
      final newHistory = {
        'roomId': roomId,
        'roomName': roomName,
        'lastMessage': '',
        'lastMessageTime': DateTime.now().toIso8601String(),
        'otherUserId': otherUserId,
      };
      historyJson.add(jsonEncode(newHistory));
      await prefs.setStringList('chat_history', historyJson);
      
      if (!mounted) return;
      // 通知主頁面更新聊天室分頁顯示
      final mainTab = context.findAncestorStateOfType<MainTabPageState>();
      if (mainTab != null) {
        mainTab.updateChatHistoryDisplay();
      }
    }
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.avatarThumbnailBytes != null && widget.avatarThumbnailBytes != oldWidget.avatarThumbnailBytes) {
      setState(() {
        _avatarImageProvider = MemoryImage(widget.avatarThumbnailBytes!);
      });
    }
  }

  @override
  void dispose() {
    _autoCommuteTimer?.cancel();
    super.dispose();
  }

  Future<void> uploadCommuteRoute() async {
    if (_commuteRoute.isEmpty) return;
    final url = Uri.parse('https://your.api/commute/upload'); // 請替換為實際 API
    final body = jsonEncode({
      'user': widget.nicknameController.text,
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'route': _commuteRoute,
    });
    try {
      final res = await http.post(url, body: body, headers: {'Content-Type': 'application/json'});
      debugPrint('上傳結果: \\${res.statusCode} \\${res.body}');
    } catch (e) {
      debugPrint('上傳失敗: $e');
    }
  }

  void _startCommuteTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('請授權定位權限才能記錄通勤路線')),
          );
        }
        return;
      }
    }
    _commuteRoute.clear();
    _commuteTimer?.cancel();
    _commuteTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _commuteRoute.add({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'ts': DateTime.now().toIso8601String(),
        });
      });
    });
    setState(() => _isTrackingCommute = true);
  }

  void _stopCommuteTracking() {
    _commuteTimer?.cancel();
    setState(() => _isTrackingCommute = false);
    debugPrint('通勤路線：\\${_commuteRoute.toString()}');
    if (!_autoTracking) uploadCommuteRoute();
  }

  void _toggleCommuteTracking(bool value) {
    if (_autoTracking) return;
    if (value) {
      _startCommuteTracking();
    } else {
      _stopCommuteTracking();
    }
  }

  Future<void> _pickTime(BuildContext context, TimeOfDay? initialTime, ValueChanged<TimeOfDay> onTimeSelected) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null && picked != initialTime) {
      onTimeSelected(picked);
    }
  }

  Future<void> _toggleAdvertise(bool value) async {
    setState(() => _isAdvertising = value);
    await SettingsBleHelper.advertiseWithAvatar(
      nickname: widget.nicknameController.text,
      avatarImageProvider: _avatarImageProvider,
      enable: value,
    );
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getString('user_id') ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設置')),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          if (_avatarImageProvider != null) {
                            showDialog(
                              context: context,
                              builder: (context) => Dialog(
                                backgroundColor: Colors.transparent,
                                child: InteractiveViewer(
                                  child: CircleAvatar(
                                    radius: 180,
                                    backgroundImage: _avatarImageProvider,
                                    child: _avatarImageProvider == null 
                                        ? const Icon(Icons.person, size: 180, color: Colors.grey)
                                        : null,
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                        child: CircleAvatar(
                          radius: 80,
                          backgroundImage: _avatarImageProvider,
                          child: _avatarImageProvider == null 
                              ? const Icon(Icons.person, size: 80, color: Colors.grey)
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: ElevatedButton(
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (ctx) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.photo_library),
                                    title: const Text('從媒體選取'),
                                    onTap: () async {
                                      Navigator.pop(ctx);
                                      await _pickAvatarFromGallery();
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.auto_awesome),
                                    title: const Text('生成圖片'),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      final mainTab = context.findAncestorStateOfType<MainTabPageState>();
                                      if (!mounted) return;
                                      if (mainTab != null) {
                                        mainTab.setState(() { mainTab.currentIndex = 1; });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: const Text('設定頭貼'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_userId != null && _userId!.isNotEmpty)
                      Center(
                        child: Text(
                          '用戶 ID：$_userId',
                          style: const TextStyle(fontSize: 14, color: Colors.blueGrey),
                        ),
                      ),
                    const SizedBox(height: 24),
                    const Text('暱稱', style: TextStyle(fontSize: 16)),
                    TextField(
                      controller: widget.nicknameController,
                      maxLength: 8,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '請輸入暱稱',
                        counterText: '',
                      ),
                      onChanged: (v) async {
                        if (v.runes.length > 8) {
                          final newText = String.fromCharCodes(v.runes.take(8));
                          widget.nicknameController.text = newText;
                          widget.nicknameController.selection = TextSelection.fromPosition(TextPosition(offset: newText.length));
                        }
                        await widget.onSaveNickname(widget.nicknameController.text);
                        if (widget.isAdvertising) {
                          await widget.onToggleAdvertise(false);
                          await Future.delayed(const Duration(milliseconds: 300));
                          await widget.onToggleAdvertise(true);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('開啟被偵測 (BLE 廣播)', style: TextStyle(fontSize: 16)),
                        Switch(
                          value: _isAdvertising,
                          onChanged: _toggleAdvertise,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text('通勤時段設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('上班：'),
                        TextButton(
                          onPressed: () => _pickTime(context, _commuteStartMorning, (t) => setState(() => _commuteStartMorning = t)),
                          child: Text(_commuteStartMorning == null ? '開始時間' : _commuteStartMorning!.format(context)),
                        ),
                        const Text('~'),
                        TextButton(
                          onPressed: () => _pickTime(context, _commuteEndMorning, (t) => setState(() => _commuteEndMorning = t)),
                          child: Text(_commuteEndMorning == null ? '結束時間' : _commuteEndMorning!.format(context)),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('下班：'),
                        TextButton(
                          onPressed: () => _pickTime(context, _commuteStartEvening, (t) => setState(() => _commuteStartEvening = t)),
                          child: Text(_commuteStartEvening == null ? '開始時間' : _commuteStartEvening!.format(context)),
                        ),
                        const Text('~'),
                        TextButton(
                          onPressed: () => _pickTime(context, _commuteEndEvening, (t) => setState(() => _commuteEndEvening = t)),
                          child: Text(_commuteEndEvening == null ? '結束時間' : _commuteEndEvening!.format(context)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('自動記錄通勤路線', style: TextStyle(fontSize: 16)),
                        Switch(
                          value: _isTrackingCommute,
                          onChanged: _autoTracking ? null : (v) => _toggleCommuteTracking(v),
                        ),
                      ],
                    ),
                    if (_autoTracking)
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Text('已自動啟動，將於通勤時段結束自動上傳', style: TextStyle(fontSize: 12, color: Colors.blue)),
                      ),
                    const SizedBox(height: 24),
// ...已移除 BLE 測試相關按鈕...
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      resizeToAvoidBottomInset: true,
    );
  }
}
