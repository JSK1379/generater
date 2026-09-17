import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'gps_service.dart';

/// GPS背景追蹤設定頁面
class GPSBackgroundSettingsPage extends StatefulWidget {
  const GPSBackgroundSettingsPage({super.key});

  @override
  State<GPSBackgroundSettingsPage> createState() => _GPSBackgroundSettingsPageState();
}

class _GPSBackgroundSettingsPageState extends State<GPSBackgroundSettingsPage> {
  bool _isLoading = true;
  bool _isBackgroundTrackingEnabled = false;
  int _trackingInterval = 15; // 分鐘
  int _selectedIntervalSeconds = 900; // 預設15分鐘的秒數
  String _userId = '';
  String? _lastUpdateTime;
  bool _showNotifications = false;

  // 間隔選項（僅節能模式，≥15分鐘）
  final List<int> _intervalOptionsSeconds = [900, 1800, 3600, 5400, 7200]; // 15分, 30分, 60分, 90分, 120分
  final List<String> _intervalLabels = ['15 分鐘', '30 分鐘', '60 分鐘', '90 分鐘', '120 分鐘'];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 載入當前設定
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getString('user_id') ?? '';
      
      final status = await GPSService.getBackgroundTrackingStatus();
      
      // 確定實際的間隔秒數
      int actualIntervalSeconds;
      if (status.intervalMinutes == 1) {
        // 檢查 SharedPreferences 中是否有高頻設定
        final intervalSeconds = prefs.getInt('background_gps_interval_seconds');
        actualIntervalSeconds = intervalSeconds ?? 60; // 預設1分鐘
      } else {
        actualIntervalSeconds = status.intervalMinutes * 60; // 轉換為秒
      }
      
      setState(() {
        _isBackgroundTrackingEnabled = status.isEnabled;
        _trackingInterval = status.intervalMinutes;
        _selectedIntervalSeconds = actualIntervalSeconds;
        _lastUpdateTime = status.lastUpdateTime;
        _showNotifications = prefs.getBool('show_gps_notifications') ?? false;
        _isLoading = false;
      });
      
      debugPrint('[GPSSettings] 載入設定完成: $status, 實際間隔: $actualIntervalSeconds秒');
    } catch (e) {
      debugPrint('[GPSSettings] 載入設定失敗: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 切換背景追蹤狀態
  Future<void> _toggleBackgroundTracking(bool enabled) async {
    if (_userId.isEmpty) {
      _showError('請先登入後再啟用背景追蹤');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      bool success;
      if (enabled) {
        success = await GPSService.startBackgroundTracking(
          _userId,
          intervalMinutes: _trackingInterval,
        );
        if (success) {
          _showSuccess('背景GPS追蹤已啟動！');
        }
      } else {
        success = await GPSService.stopBackgroundTracking();
        if (success) {
          _showSuccess('背景GPS追蹤已停止');
        }
      }

      if (success) {
        setState(() {
          _isBackgroundTrackingEnabled = enabled;
        });
      } else {
        _showError(enabled ? '啟動背景追蹤失敗' : '停止背景追蹤失敗');
      }
    } catch (e) {
      _showError('操作失敗: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  /// 更新追蹤間隔（僅節能模式）
  Future<void> _updateTrackingInterval(int intervalSeconds) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 將秒轉換為分鐘（最小15分鐘）
      final intervalMinutes = (intervalSeconds / 60).ceil();
      
      if (_isBackgroundTrackingEnabled) {
        // 使用節能模式重新啟動
        final success = await GPSService.updateBackgroundTrackingInterval(intervalMinutes);
        final label = _getIntervalLabel(intervalSeconds);
        if (success) {
          _showSuccess('追蹤間隔已更新為 $label');
        } else {
          _showError('更新追蹤間隔失敗');
        }
      }

      setState(() {
        _trackingInterval = intervalMinutes; // 保存為分鐘單位
        _selectedIntervalSeconds = intervalSeconds; // 保存實際選擇的秒數
      });
      
      debugPrint('[GPSSettings] 追蹤間隔已更新: $intervalSeconds秒 ($intervalMinutes分鐘)');
    } catch (e) {
      _showError('更新間隔失敗: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  /// 獲取間隔標籤
  String _getIntervalLabel(int intervalSeconds) {
    final index = _intervalOptionsSeconds.indexOf(intervalSeconds);
    return index >= 0 ? _intervalLabels[index] : '$intervalSeconds 秒';
  }

  /// 切換通知設定
  Future<void> _toggleNotifications(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_gps_notifications', enabled);
    
    setState(() {
      _showNotifications = enabled;
    });
  }

  /// 檢查並請求權限
  Future<void> _checkAndRequestPermissions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 檢查前台位置權限
      final locationPermission = await Permission.location.status;
      final backgroundLocationPermission = await Permission.locationAlways.status;
      final notificationPermission = await Permission.notification.status;
      
      debugPrint('[GPSSettings] 權限狀態檢查:');
      debugPrint('[GPSSettings] 位置權限: $locationPermission');
      debugPrint('[GPSSettings] 背景位置權限: $backgroundLocationPermission');
      debugPrint('[GPSSettings] 通知權限: $notificationPermission');

      // 構建權限狀態報告
      final locationStatus = _getPermissionStatusText(locationPermission);
      final backgroundStatus = _getPermissionStatusText(backgroundLocationPermission);
      final notificationStatus = _getPermissionStatusText(notificationPermission);

      // 嘗試請求背景定位權限
      final hasBackgroundPermission = await GPSService.checkAndRequestBackgroundLocationPermission();
      
      // 顯示詳細的權限狀態
      final message = '權限檢查完成！\n\n'
          '📍 位置權限: $locationStatus\n'
          '🔄 背景位置權限: $backgroundStatus\n'
          '🔔 通知權限: $notificationStatus\n\n'
          '${hasBackgroundPermission ? 
            '✅ 您現在可以啟用背景GPS追蹤' : 
            '⚠️ 建議手動到設定中授權「始終允許」位置權限'}';
      
      if (hasBackgroundPermission) {
        _showSuccess(message);
      } else {
        _showError('$message\n\n💡 點擊「開啟應用設定」按鈕前往設定頁面');
        
        // 提供開啟設定的選項
        _showOpenSettingsDialog();
      }
    } catch (e) {
      _showError('權限檢查失敗: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  /// 獲取權限狀態文字
  String _getPermissionStatusText(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
        return '✅ 已授權';
      case PermissionStatus.denied:
        return '❌ 被拒絕';
      case PermissionStatus.restricted:
        return '🚫 受限制';
      case PermissionStatus.permanentlyDenied:
        return '⛔ 永久拒絕';
      case PermissionStatus.limited:
        return '⚠️ 有限授權';
      default:
        return '❓ 未知狀態';
    }
  }

  /// 顯示開啟設定對話框
  Future<void> _showOpenSettingsDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('需要權限設定'),
          content: const Text(
            '為了讓應用能在背景追蹤GPS位置，請到系統設定中：\n\n'
            '1. 找到此應用的權限設定\n'
            '2. 點擊「位置」權限\n'
            '3. 選擇「始終允許」\n\n'
            '是否要前往設定頁面？'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
              child: const Text('開啟設定'),
            ),
          ],
        );
      },
    );
  }

  /// 手動記錄一次GPS位置
  Future<void> _recordCurrentLocation() async {
    if (_userId.isEmpty) {
      _showError('請先登入');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await GPSService.recordCurrentLocation(_userId);
      
      if (result.success) {
        _showSuccess('GPS位置記錄成功！\n'
                    '緯度: ${result.latitude?.toStringAsFixed(6)}\n'
                    '經度: ${result.longitude?.toStringAsFixed(6)}');
      } else {
        _showError('GPS位置記錄失敗: ${result.error}');
      }
    } catch (e) {
      _showError('記錄GPS位置失敗: $e');
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS背景追蹤設定'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadSettings,
            icon: const Icon(Icons.refresh),
            tooltip: '重新整理',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 狀態概覽卡片
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📍 追蹤狀態',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                _isBackgroundTrackingEnabled ? Icons.gps_fixed : Icons.gps_off,
                                color: _isBackgroundTrackingEnabled ? Colors.green : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isBackgroundTrackingEnabled ? '背景追蹤運行中' : '背景追蹤已停止',
                                style: TextStyle(
                                  color: _isBackgroundTrackingEnabled ? Colors.green : Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          if (_isBackgroundTrackingEnabled) ...[
                            const SizedBox(height: 8),
                            Text('追蹤間隔: ${_getIntervalLabel(_selectedIntervalSeconds)}'),
                            if (_lastUpdateTime != null) ...[
                              const SizedBox(height: 4),
                              Text('最後更新: $_lastUpdateTime'),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 權限檢查卡片
                  Card(
                    color: Colors.orange[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🔐 權限檢查',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '背景GPS追蹤需要以下權限：\n'
                            '• 定位權限（使用應用時）\n'
                            '• 背景定位權限（始終允許）← 重要！\n'
                            '• 通知權限\n\n'
                            '⚠️ Android 10+ 系統需要分步驟授權：\n'
                            '1. 先授權「使用應用時」位置權限\n'
                            '2. 再授權「始終允許」背景權限\n'
                            '3. 如果系統未顯示對話框，需手動到設定授權',
                            style: TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _checkAndRequestPermissions,
                              icon: const Icon(Icons.security),
                              label: const Text('檢查並請求權限'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange[600],
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 背景追蹤開關
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🔄 背景追蹤',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            title: const Text('啟用背景GPS追蹤'),
                            subtitle: Text(_userId.isEmpty 
                                ? '請先登入以啟用此功能' 
                                : '應用在背景時持續記錄GPS位置'),
                            value: _isBackgroundTrackingEnabled,
                            onChanged: _userId.isEmpty ? null : _toggleBackgroundTracking,
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 追蹤間隔設定
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '⏱️ 追蹤間隔',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          const Text('選擇GPS位置記錄的頻率：'),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: List.generate(_intervalOptionsSeconds.length, (index) {
                              final intervalSeconds = _intervalOptionsSeconds[index];
                              final label = _intervalLabels[index];
                              final isSelected = _selectedIntervalSeconds == intervalSeconds; // 直接比較秒數
                              return ChoiceChip(
                                label: Text(label),
                                selected: isSelected,
                                onSelected: (_) => _updateTrackingInterval(intervalSeconds),
                              );
                            }),
                          ),
                          const SizedBox(height: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '⚠️ 較短的間隔會消耗更多電量',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange[700],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '� 使用節能模式，應用可在關閉時背景運行',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '� 適合路線記錄，不需要持續開啟應用',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 通知設定
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🔔 通知設定',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            title: const Text('顯示GPS記錄通知'),
                            subtitle: const Text('每次GPS位置記錄成功時顯示通知'),
                            value: _showNotifications,
                            onChanged: _toggleNotifications,
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 手動操作
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🎯 手動操作',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _userId.isEmpty ? null : _recordCurrentLocation,
                              icon: const Icon(Icons.my_location),
                              label: const Text('立即記錄GPS位置'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 注意事項
                  Card(
                    color: Colors.blue[50],
                    child: const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💡 注意事項',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text('• 使用節能模式，應用可完全關閉並在背景運行'),
                          Text('• Android 10+ 需要「始終允許」位置權限'),
                          Text('• 最小追蹤間隔為15分鐘（系統限制）'),
                          Text('• 適合路線記錄，無需持續開啟應用'),
                          Text('• 在省電模式下可能會影響追蹤準確性'),
                          SizedBox(height: 8),
                          Text(
                            '🔧 權限設定提示：',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text('• 如果權限請求失敗，請到「設定 > 應用程式 > [應用名稱] > 權限」手動設定'),
                          Text('• 選擇「位置」權限 > 「始終允許」'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
