import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'settings_ble_helper.dart';
import 'user_profile_edit_page.dart';
import 'api_config.dart';
import 'high_frequency_gps_test_page.dart';
import 'background_gps_service.dart';
import 'gemini_api_key_setup_page.dart';

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
  Timer? _autoCommuteTimer;
  bool _autoTracking = false;
  TimeOfDay? _commuteStartMorning;
  TimeOfDay? _commuteEndMorning;
  TimeOfDay? _commuteStartEvening;
  TimeOfDay? _commuteEndEvening;
  bool _isTrackingCommute = false;
  final List<Map<String, dynamic>> _commuteRoute = [];
  Timer? _commuteTimer;

  String? _userId;

  Future<void> _loadAvatarFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 🖼️ 優先載入網路頭像URL
    final avatarUrl = prefs.getString('avatar_url');
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      setState(() {
        _avatarImageProvider = NetworkImage(avatarUrl);
      });
      return;
    }
    
    // 如果沒有網路頭像，則載入本地頭像
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
  
  /// 檢查是否已設定通勤時段
  bool _hasCommuteTimeSettings() {
    return (_commuteStartMorning != null && _commuteEndMorning != null) ||
           (_commuteStartEvening != null && _commuteEndEvening != null);
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
    _loadUserId();
    _loadCommuteSettings(); // 🔄 載入通勤時段設定
    _checkHighFrequencyGPSStatus(); // 檢查高頻率GPS狀態
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
    final url = Uri.parse(ApiConfig.gpsUpload); // 🚀 使用統一的API配置
    final body = jsonEncode({
      'user_id': _userId ?? '',  // 🆔 使用用戶 ID 而非暱稱
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'route': _commuteRoute,
    });
    try {
      final res = await http.post(url, body: body, headers: ApiConfig.jsonHeaders);
      debugPrint('GPS路線上傳結果: ${res.statusCode} ${res.body}');
      if (res.statusCode == 200) {
        debugPrint('✅ GPS路線上傳成功');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('通勤路線上傳成功')),
          );
        }
      } else {
        debugPrint('❌ GPS路線上傳失敗: ${res.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('通勤路線上傳失敗: ${res.statusCode}')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ GPS路線上傳異常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('通勤路線上傳失敗: $e')),
        );
      }
    }
  }

  // 上傳當前GPS位置
  Future<void> uploadCurrentLocation() async {
    try {
      // 檢查定位權限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('請授權定位權限才能上傳GPS位置')),
            );
          }
          return;
        }
      }

      // 獲取當前位置
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      );

      // 準備上傳數據 - 使用新的API格式
      final url = Uri.parse('${ApiConfig.gpsLocation}?user_id=${_userId ?? ''}');
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
      
      if (mounted) {
        if (res.statusCode == 200) {
          final responseData = jsonDecode(res.body);
          debugPrint('✅ 當前GPS位置上傳成功');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'GPS定位記錄成功!\n'
                '記錄ID: ${responseData['id']}\n'
                '緯度: ${position.latitude.toStringAsFixed(6)}\n'
                '經度: ${position.longitude.toStringAsFixed(6)}\n'
                '時間: ${DateTime.now().toString().substring(0, 19)}'
              ),
              duration: const Duration(seconds: 3),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS定位記錄失敗: $e')),
        );
      }
    }
  }

  // 獲取今日GPS歷史記錄
  Future<void> getTodayGPSHistory() async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final url = Uri.parse(ApiConfig.gpsUserLocationsByDate(_userId ?? '', today));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('正在獲取今日GPS記錄...')),
        );
      }

      final res = await http.get(url, headers: ApiConfig.jsonHeaders);
      
      debugPrint('今日GPS歷史查詢結果: ${res.statusCode} ${res.body}');
      
      if (mounted) {
        if (res.statusCode == 200) {
          final responseData = jsonDecode(res.body);
          final totalLocations = responseData['total_locations'] ?? 0;
          final locations = responseData['locations'] as List? ?? [];
          
          debugPrint('✅ 今日GPS歷史獲取成功');
          
          String locationDetails = '';
          if (locations.isNotEmpty) {
            final firstLocation = locations.first;
            final lastLocation = locations.last;
            locationDetails = '\n最新: (${firstLocation['latitude']}, ${firstLocation['longitude']})'
                             '\n最早: (${lastLocation['latitude']}, ${lastLocation['longitude']})';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '今日GPS記錄 ($today)\n'
                '記錄總數: $totalLocations$locationDetails'
              ),
              duration: const Duration(seconds: 4),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS記錄查詢失敗: $e')),
        );
      }
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

  /// 檢查高頻率GPS追蹤狀態
  Future<void> _checkHighFrequencyGPSStatus() async {
    final isEnabled = await BackgroundGPSService.isBackgroundTrackingEnabled();
    if (mounted) {
      setState(() {
        _isTrackingCommute = isEnabled;
      });
    }
  }
  
  /// 格式化間隔顯示
  String _formatInterval(int seconds) {
    if (seconds < 60) {
      return '$seconds秒';
    } else if (seconds < 3600) {
      return '${(seconds / 60).round()}分鐘';
    } else {
      return '${(seconds / 3600).round()}小時';
    }
  }

  /// 獲取當前GPS間隔設定
  Future<String> _getCurrentGPSInterval() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final intervalSeconds = prefs.getInt('background_gps_interval_seconds') ?? 30;
      return _formatInterval(intervalSeconds);
    } catch (e) {
      debugPrint('[Settings] 讀取GPS間隔設定時發生錯誤: $e');
      return '30秒 (預設)';
    }
  }

  void _toggleCommuteTracking(bool value) async {
    if (_autoTracking) return;
    
    if (value) {
      // 檢查是否已設定通勤時段
      if (!_hasCommuteTimeSettings()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ 請先設定通勤時段，才能啟動自動記錄功能'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }
      
      // 檢查是否在通勤時段內
      if (!_isNowInCommutePeriod()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📍 目前不在設定的通勤時段內，GPS追蹤將在通勤時段自動啟動'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 4),
            ),
          );
        }
        // 仍然允許啟動，但會顯示提示
      }
      
      // 啟動高頻率背景GPS追蹤
      final commuteSettings = {
        'morningStart': _commuteStartMorning != null ? {
          'hour': _commuteStartMorning!.hour,
          'minute': _commuteStartMorning!.minute,
        } : null,
        'morningEnd': _commuteEndMorning != null ? {
          'hour': _commuteEndMorning!.hour,
          'minute': _commuteEndMorning!.minute,
        } : null,
        'eveningStart': _commuteStartEvening != null ? {
          'hour': _commuteStartEvening!.hour,
          'minute': _commuteStartEvening!.minute,
        } : null,
        'eveningEnd': _commuteEndEvening != null ? {
          'hour': _commuteEndEvening!.hour,
          'minute': _commuteEndEvening!.minute,
        } : null,
      };
      
      // 從SharedPreferences讀取保存的間隔設定
      final prefs = await SharedPreferences.getInstance();
      final savedInterval = prefs.getInt('background_gps_interval_seconds') ?? 30;
      
      final success = await BackgroundGPSService.startBackgroundTracking(
        intervalSeconds: savedInterval, // 使用保存的間隔設定
        userId: _userId ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
        commuteTimeSettings: commuteSettings,
      );
      
      if (success) {
        setState(() {
          _isTrackingCommute = true;
        });
        if (mounted) {
          final statusMessage = _isNowInCommutePeriod() 
            ? '✅ 高頻率背景GPS追蹤已啟動（通勤時段內）- 間隔: ${_formatInterval(savedInterval)}'
            : '✅ 高頻率背景GPS追蹤已啟動（將在通勤時段內記錄）- 間隔: ${_formatInterval(savedInterval)}';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(statusMessage),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ 啟動失敗，請檢查權限設定'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      // 停止高頻率背景GPS追蹤
      final success = await BackgroundGPSService.stopBackgroundTracking();
      
      if (success) {
        setState(() {
          _isTrackingCommute = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ 背景GPS追蹤已停止'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
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
      // 🔄 時間設定後立即儲存
      await _saveCommuteSettings();
    }
  }
  
  // 🔄 儲存通勤時段設定
  Future<void> _saveCommuteSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 儲存早上通勤時段
    if (_commuteStartMorning != null) {
      await prefs.setString('commute_start_morning', '${_commuteStartMorning!.hour}:${_commuteStartMorning!.minute}');
    } else {
      await prefs.remove('commute_start_morning');
    }
    
    if (_commuteEndMorning != null) {
      await prefs.setString('commute_end_morning', '${_commuteEndMorning!.hour}:${_commuteEndMorning!.minute}');
    } else {
      await prefs.remove('commute_end_morning');
    }
    
    // 儲存晚上通勤時段
    if (_commuteStartEvening != null) {
      await prefs.setString('commute_start_evening', '${_commuteStartEvening!.hour}:${_commuteStartEvening!.minute}');
    } else {
      await prefs.remove('commute_start_evening');
    }
    
    if (_commuteEndEvening != null) {
      await prefs.setString('commute_end_evening', '${_commuteEndEvening!.hour}:${_commuteEndEvening!.minute}');
    } else {
      await prefs.remove('commute_end_evening');
    }
    
    debugPrint('[Settings] 通勤時段設定已儲存');
    if (mounted) {
      debugPrint('[Settings] 早上: ${_commuteStartMorning?.format(context)} - ${_commuteEndMorning?.format(context)}');
      debugPrint('[Settings] 晚上: ${_commuteStartEvening?.format(context)} - ${_commuteEndEvening?.format(context)}');
    }
  }
  
  // 🔄 載入通勤時段設定
  Future<void> _loadCommuteSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 載入早上通勤時段
    final morningStart = prefs.getString('commute_start_morning');
    if (morningStart != null) {
      final parts = morningStart.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          _commuteStartMorning = TimeOfDay(hour: hour, minute: minute);
        }
      }
    }
    
    final morningEnd = prefs.getString('commute_end_morning');
    if (morningEnd != null) {
      final parts = morningEnd.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          _commuteEndMorning = TimeOfDay(hour: hour, minute: minute);
        }
      }
    }
    
    // 載入晚上通勤時段
    final eveningStart = prefs.getString('commute_start_evening');
    if (eveningStart != null) {
      final parts = eveningStart.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          _commuteStartEvening = TimeOfDay(hour: hour, minute: minute);
        }
      }
    }
    
    final eveningEnd = prefs.getString('commute_end_evening');
    if (eveningEnd != null) {
      final parts = eveningEnd.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          _commuteEndEvening = TimeOfDay(hour: hour, minute: minute);
        }
      }
    }
    
    if (mounted) {
      setState(() {
        // UI 更新
      });
    }
    
    debugPrint('[Settings] 通勤時段設定已載入');
    if (mounted) {
      debugPrint('[Settings] 早上: ${_commuteStartMorning?.format(context)} - ${_commuteEndMorning?.format(context)}');
      debugPrint('[Settings] 晚上: ${_commuteStartEvening?.format(context)} - ${_commuteEndEvening?.format(context)}');
    }
  }

  Future<void> _toggleAdvertise(bool value) async {
    await widget.onToggleAdvertise(value);
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
                    if (_userId != null && _userId!.isNotEmpty) ...[
                      Center(
                        child: Text(
                          '用戶 ID：$_userId',
                          style: const TextStyle(fontSize: 14, color: Colors.blueGrey),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (_userId != null && _userId!.isNotEmpty) {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserProfileEditPage(
                                    userId: _userId!,
                                    initialNickname: widget.nicknameController.text,
                                  ),
                                ),
                              );
                              
                              // 如果用戶資料有更新，重新載入暱稱和頭像
                              if (result == true) {
                                final prefs = await SharedPreferences.getInstance();
                                final newNickname = prefs.getString('nickname') ?? '';
                                if (newNickname.isNotEmpty) {
                                  widget.nicknameController.text = newNickname;
                                }
                                
                                // 🖼️ 重新載入頭像
                                await _loadAvatarFromPrefs();
                              }
                            }
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('編輯用戶資料'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
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
                          value: widget.isAdvertising,
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
                    if (_isTrackingCommute && !_autoTracking)
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Text('高頻率背景GPS追蹤運行中', style: TextStyle(fontSize: 12, color: Colors.green)),
                      ),
                    const SizedBox(height: 24),
                    
                    // AI 設定區塊
                    const Text('AI 助手設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.smart_toy, color: Colors.purple.shade600, size: 24),
                                const SizedBox(width: 8),
                                const Text(
                                  'Gemini AI 整合',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '設定你的 Google Gemini API Key 來啟用 AI 聊天功能',
                              style: TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const GeminiApiKeySetupPage(),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.key),
                                label: const Text('設定 API Key'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // GPS定位功能區塊
                    const Text('GPS定位功能', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: uploadCurrentLocation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.gps_fixed),
                            label: const Text('記錄當前位置'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: getTodayGPSHistory,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.history),
                            label: const Text('今日記錄'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // GPS間隔設定顯示
                    FutureBuilder<String>(
                      future: _getCurrentGPSInterval(),
                      builder: (context, snapshot) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer, size: 20, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                'GPS記錄間隔: ${snapshot.data ?? "載入中..."}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    // 高頻率背景GPS測試按鈕
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const HighFrequencyGPSTestPage(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.gps_fixed),
                        label: const Text('🛰️ 高頻率背景GPS測試'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // 測試 BLE 連接提示窗
                    if (widget.isAdvertising)
                      ElevatedButton(
                        onPressed: () {
                          // 模擬收到連接請求來測試提示窗
                          SettingsBleHelper.simulateIncomingConnection(
                            'Test Device',
                            'test_image_123',
                            'AA:BB:CC:DD:EE:FF'
                          );
                        },
                        child: const Text('測試連接提示窗'),
                      ),
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
