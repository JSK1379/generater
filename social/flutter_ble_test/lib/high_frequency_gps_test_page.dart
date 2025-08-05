import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'background_gps_service.dart';
import 'enhanced_foreground_location_service.dart';

/// 高頻率背景GPS測試頁面
/// 用於測試類似Google Maps的背景GPS追蹤功能
class HighFrequencyGPSTestPage extends StatefulWidget {
  const HighFrequencyGPSTestPage({super.key});

  @override
  State<HighFrequencyGPSTestPage> createState() => _HighFrequencyGPSTestPageState();
}

class _HighFrequencyGPSTestPageState extends State<HighFrequencyGPSTestPage> {
  bool _isTracking = false;
  bool _isLoading = false; // 添加載入狀態
  String _userId = '';
  int _selectedInterval = 30; // 默認30秒
  String _statusMessage = '準備開始高頻率背景GPS追蹤';
  
  // 統計數據
  Map<String, dynamic> _stats = {};
  StreamSubscription<Map<String, dynamic>>? _statsSubscription;
  
  // 支援的間隔選項（秒）
  final List<int> _intervalOptions = [5, 10, 15, 30, 60, 120, 300, 900]; // 5秒到15分鐘
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkTrackingStatus();
    _listenToStats();
  }
  
  @override
  void dispose() {
    _statsSubscription?.cancel();
    super.dispose();
  }
  
  /// 載入設定
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 檢查 widget 是否仍然存在於 widget tree 中
    if (!mounted) return;
    
    setState(() {
      // 使用系統的主要用戶ID，而不是背景GPS專用ID
      _userId = prefs.getString('user_id') ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
      final savedInterval = prefs.getInt('background_gps_interval_seconds') ?? 30;
      // 確保載入的間隔值在可選項目中，否則使用默認值
      _selectedInterval = _intervalOptions.contains(savedInterval) ? savedInterval : 30;
    });
  }
  
  /// 保存間隔設定
  Future<void> _saveIntervalSetting(int intervalSeconds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('background_gps_interval_seconds', intervalSeconds);
      
      // 顯示保存成功的提示
      if (mounted) {
        _showSnackBar('✅ 間隔設定已保存：${_formatInterval(intervalSeconds)}', Colors.blue);
      }
      
      debugPrint('[HighFrequencyGPS] 間隔設定已保存: $intervalSeconds秒');
    } catch (e) {
      debugPrint('[HighFrequencyGPS] 保存間隔設定失敗: $e');
      if (mounted) {
        _showSnackBar('❌ 保存設定失敗', Colors.red);
      }
    }
  }
  
  /// 檢查追蹤狀態
  Future<void> _checkTrackingStatus() async {
    final isTracking = await BackgroundGPSService.isBackgroundTrackingEnabled();
    final isEnhancedRunning = await EnhancedForegroundLocationService.isServiceRunning();
    
    // 檢查 widget 是否仍然存在於 widget tree 中
    if (!mounted) return;
    
    setState(() {
      _isTracking = isTracking || isEnhancedRunning;
      if (_isTracking) {
        _statusMessage = '背景GPS追蹤運行中...';
      } else {
        _statusMessage = '背景GPS追蹤已停止';
      }
    });
  }
  
  /// 監聽統計數據
  void _listenToStats() {
    _statsSubscription = EnhancedForegroundLocationService.statsStream.listen((stats) {
      // 檢查 widget 是否仍然存在於 widget tree 中
      if (!mounted) return;
      
      setState(() {
        _stats = stats;
        
        // 更新狀態消息
        final event = stats['event'] as String?;
        switch (event) {
          case 'location_update':
            final count = stats['updateCount'] ?? 0;
            _statusMessage = '已記錄 $count 次GPS位置';
            break;
          case 'service_started':
            _statusMessage = '高頻率背景GPS追蹤已啟動';
            break;
          case 'service_stopped':
            _statusMessage = '背景GPS追蹤已停止';
            break;
          case 'error':
            _statusMessage = '錯誤: ${stats['error']}';
            break;
        }
      });
    });
  }
  
  /// 開始高頻率背景追蹤
  Future<void> _startTracking() async {
    // 檢查 widget 是否仍然存在於 widget tree 中
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _statusMessage = '正在啟動高頻率背景GPS追蹤...';
    });
    
    final success = await BackgroundGPSService.startBackgroundTracking(
      intervalSeconds: _selectedInterval,
      userId: _userId,
    );
    
    // 檢查 widget 是否仍然存在於 widget tree 中
    if (!mounted) return;
    
    setState(() {
      _isLoading = false;
      if (success) {
        _isTracking = true;
        _statusMessage = '高頻率背景GPS追蹤已啟動';
      } else {
        _statusMessage = '啟動失敗，請檢查權限設定';
      }
    });
    
    if (success) {
      _showSnackBar('✅ 背景GPS追蹤已啟動！現在可以關閉APP進行測試。', Colors.green);
    } else {
      _showSnackBar('❌ 啟動失敗，請檢查定位權限', Colors.red);
    }
  }
  
  /// 停止背景追蹤
  Future<void> _stopTracking() async {
    // 檢查 widget 是否仍然存在於 widget tree 中
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _statusMessage = '正在停止背景GPS追蹤...';
    });
    
    final success = await BackgroundGPSService.stopBackgroundTracking();
    
    // 檢查 widget 是否仍然存在於 widget tree 中
    if (!mounted) return;
    
    setState(() {
      _isLoading = false;
      if (success) {
        _isTracking = false;
        _statusMessage = '背景GPS追蹤已停止';
        _stats.clear();
      }
    });
    
    if (success) {
      _showSnackBar('✅ 背景GPS追蹤已停止', Colors.orange);
    } else {
      _showSnackBar('❌ 停止失敗', Colors.red);
    }
  }
  
  /// 獲取服務統計
  Future<void> _refreshStats() async {
    final stats = await EnhancedForegroundLocationService.getServiceStats();
    
    // 檢查 widget 是否仍然存在於 widget tree 中
    if (!mounted) return;
    
    setState(() {
      _stats = stats;
    });
  }
  
  /// 顯示提示訊息
  void _showSnackBar(String message, Color color) {
    // 檢查 widget 是否仍然存在於 widget tree 中
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('高頻率背景GPS測試'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _checkTrackingStatus();
              _refreshStats();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 狀態卡片
            Card(
              color: _isTracking ? Colors.green.shade50 : Colors.grey.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isTracking ? Icons.gps_fixed : Icons.gps_off,
                          color: _isTracking ? Colors.green : Colors.grey,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '追蹤狀態',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _isTracking ? Colors.green.shade700 : Colors.grey.shade700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 配置設定
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '追蹤配置',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    
                    // 用戶ID (只讀顯示)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.grey.shade50,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.person, color: Colors.grey),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '用戶ID',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _userId.isNotEmpty ? _userId : '載入中...',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // 追蹤間隔
                    Row(
                      children: [
                        const Icon(Icons.timer),
                        const SizedBox(width: 8),
                        const Text('追蹤間隔：'),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButton<int>(
                            value: _selectedInterval,
                            items: _intervalOptions.map((interval) {
                              return DropdownMenuItem<int>(
                                value: interval,
                                child: Text(_formatInterval(interval)),
                              );
                            }).toList(),
                            onChanged: (_isTracking || _isLoading) ? null : (value) async {
                              if (value != null) {
                                setState(() {
                                  _selectedInterval = value;
                                });
                                
                                // 保存間隔設定到SharedPreferences
                                await _saveIntervalSetting(value);
                              }
                            },
                            isExpanded: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 控制按鈕
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : (_isTracking ? _stopTracking : _startTracking),
                icon: _isLoading 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(_isTracking ? Icons.stop : Icons.play_arrow),
                label: Text(
                  _isLoading 
                    ? (_isTracking ? '正在停止...' : '正在啟動...')
                    : (_isTracking ? '停止背景追蹤' : '開始背景追蹤')
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isLoading 
                    ? Colors.grey 
                    : (_isTracking ? Colors.red : Colors.green),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 統計信息
            if (_stats.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '即時統計',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      
                      ..._stats.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 120,
                                child: Text(
                                  '${entry.key}:',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                child: Text(entry.value.toString()),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // 說明信息
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          '使用說明',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '• 這是真正的背景GPS追蹤，關閉APP後也會繼續運行\n'
                      '• 支援5秒到5分鐘的高頻率間隔\n'
                      '• 使用前台服務確保不被系統殺死\n'
                      '• 類似Google Maps的背景定位技術\n'
                      '• 智能省電策略，延長電池使用時間',
                      style: TextStyle(height: 1.5),
                    ),
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
