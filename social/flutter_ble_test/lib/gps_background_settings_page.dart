import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // 間隔選項（以秒為單位）
  final List<int> _intervalOptionsSeconds = [30, 60, 300, 600, 900, 1800, 3600]; // 30秒, 1分, 5分, 10分, 15分, 30分, 60分
  final List<String> _intervalLabels = ['30 秒', '1 分鐘', '5 分鐘', '10 分鐘', '15 分鐘', '30 分鐘', '60 分鐘'];

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
      
      setState(() {
        _isBackgroundTrackingEnabled = status.isEnabled;
        _trackingInterval = status.intervalMinutes;
        // 如果間隔是1分鐘，檢查是否實際設定為30秒
        if (status.intervalMinutes == 1) {
          // 檢查 SharedPreferences 中是否有高頻設定
          final prefs = SharedPreferences.getInstance();
          prefs.then((prefs) {
            final intervalSeconds = prefs.getInt('background_gps_interval_seconds');
            if (intervalSeconds != null && intervalSeconds == 30) {
              setState(() {
                _selectedIntervalSeconds = 30;
              });
            } else {
              setState(() {
                _selectedIntervalSeconds = 60; // 1分鐘
              });
            }
          });
        } else {
          _selectedIntervalSeconds = status.intervalMinutes * 60; // 轉換為秒
        }
        _lastUpdateTime = status.lastUpdateTime;
        _showNotifications = prefs.getBool('show_gps_notifications') ?? false;
        _isLoading = false;
      });
      
      debugPrint('[GPSSettings] 載入設定完成: $status');
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

  /// 更新追蹤間隔
  Future<void> _updateTrackingInterval(int intervalSeconds) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 將秒轉換為分鐘（最小1分鐘）
      final intervalMinutes = (intervalSeconds / 60).ceil();
      
      if (_isBackgroundTrackingEnabled) {
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
                                '📱 1-14分鐘間隔使用高頻模式，需要應用保持在背景運行',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '🔋 15分鐘以上間隔使用節能模式，可在應用關閉時運行',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green[600],
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
                          Text('• 背景GPS追蹤需要定位權限'),
                          Text('• 為了節省電量，建議設定較長的追蹤間隔'),
                          Text('• 應用被系統清理後需要重新啟動追蹤'),
                          Text('• 在省電模式下可能會影響追蹤準確性'),
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
