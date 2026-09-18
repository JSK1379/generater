import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:near_ride/core/config/api_config.dart';

/// 增強版前台定位服務管理器
/// 提供真正的背景GPS追蹤能力，即使關閉APP也能繼續運行
class EnhancedForegroundLocationService {
  static const MethodChannel _channel = MethodChannel('enhanced_location_service');
  
  // 服務狀態
  static bool _isServiceRunning = false;
  static String? _currentUserId;
  static int _currentInterval = 30;
  
  // 統計數據流
  static final StreamController<Map<String, dynamic>> _statsController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  /// 統計數據流（位置記錄次數、成功率等）
  static Stream<Map<String, dynamic>> get statsStream => _statsController.stream;
  
  /// 初始化服務
  static Future<void> initialize() async {
    try {
      // 註冊方法調用處理器
      _channel.setMethodCallHandler(_handleMethodCall);
      
      // 檢查並恢復服務狀態
      await _restoreServiceState();
      
      debugPrint('[EnhancedLocationService] 初始化完成');
    } catch (e) {
      debugPrint('[EnhancedLocationService] 初始化失敗: $e');
    }
  }
  
  /// 開始增強版背景GPS追蹤
  /// [intervalSeconds] 追蹤間隔（秒），支援高頻率如5秒、10秒、30秒等
  /// [userId] 用戶ID
  /// [showDetailedStats] 是否顯示詳細統計信息
  static Future<bool> startService({
    required String userId,
    int intervalSeconds = 30,
    bool showDetailedStats = true,
  }) async {
    try {
      if (_isServiceRunning) {
        debugPrint('[EnhancedLocationService] 服務已在運行中');
        return true;
      }
      
      // 驗證參數
      if (userId.isEmpty) {
        debugPrint('[EnhancedLocationService] 用戶ID不能為空');
        return false;
      }
      
      // 確保最小間隔為5秒（避免過於頻繁）
      if (intervalSeconds < 5) {
        intervalSeconds = 5;
        debugPrint('[EnhancedLocationService] 間隔時間調整為最小值5秒');
      }
      
      // 調用原生服務
      final result = await _channel.invokeMethod('startEnhancedService', {
        'userId': userId,
        'intervalSeconds': intervalSeconds,
        'apiUrl': ApiConfig.gpsLocation,
        'showDetailedStats': showDetailedStats,
      });
      
      if (result == true) {
        _isServiceRunning = true;
        _currentUserId = userId;
        _currentInterval = intervalSeconds;
        
        // 保存服務狀態
        await _saveServiceState();
        
        debugPrint('[EnhancedLocationService] ✅ 增強版背景GPS服務已啟動');
        debugPrint('[EnhancedLocationService] 📊 用戶: $userId, 間隔: $intervalSeconds秒');
        
        // 發送啟動事件
        _statsController.add({
          'event': 'service_started',
          'userId': userId,
          'interval': intervalSeconds,
          'timestamp': DateTime.now().toIso8601String(),
        });
        
        return true;
      } else {
        debugPrint('[EnhancedLocationService] ❌ 啟動增強版服務失敗');
        return false;
      }
      
    } catch (e) {
      debugPrint('[EnhancedLocationService] ❌ 啟動服務異常: $e');
      return false;
    }
  }
  
  /// 停止增強版背景GPS追蹤
  static Future<bool> stopService() async {
    try {
      if (!_isServiceRunning) {
        debugPrint('[EnhancedLocationService] 服務未在運行中');
        return true;
      }
      
      // 調用原生服務停止
      final result = await _channel.invokeMethod('stopEnhancedService');
      
      if (result == true) {
        _isServiceRunning = false;
        _currentUserId = null;
        _currentInterval = 30;
        
        // 清除服務狀態
        await _clearServiceState();
        
        debugPrint('[EnhancedLocationService] ✅ 增強版背景GPS服務已停止');
        
        // 發送停止事件
        _statsController.add({
          'event': 'service_stopped',
          'timestamp': DateTime.now().toIso8601String(),
        });
        
        return true;
      } else {
        debugPrint('[EnhancedLocationService] ❌ 停止增強版服務失敗');
        return false;
      }
      
    } catch (e) {
      debugPrint('[EnhancedLocationService] ❌ 停止服務異常: $e');
      return false;
    }
  }
  
  /// 檢查服務是否正在運行
  static Future<bool> isServiceRunning() async {
    try {
      final result = await _channel.invokeMethod('isEnhancedServiceRunning');
      _isServiceRunning = result == true;
      return _isServiceRunning;
    } catch (e) {
      debugPrint('[EnhancedLocationService] 檢查服務狀態失敗: $e');
      return false;
    }
  }
  
  /// 獲取服務統計信息
  static Future<Map<String, dynamic>> getServiceStats() async {
    try {
      final result = await _channel.invokeMethod('getEnhancedServiceStats');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      debugPrint('[EnhancedLocationService] 獲取統計信息失敗: $e');
      return {};
    }
  }
  
  /// 獲取當前服務配置
  static Map<String, dynamic> getCurrentConfig() {
    return {
      'isRunning': _isServiceRunning,
      'userId': _currentUserId ?? '',
      'intervalSeconds': _currentInterval,
      'apiUrl': ApiConfig.gpsLocation,
    };
  }
  
  /// 更新追蹤間隔（需要重啟服務）
  static Future<bool> updateInterval({
    required int newIntervalSeconds,
  }) async {
    if (!_isServiceRunning || _currentUserId == null) {
      debugPrint('[EnhancedLocationService] 服務未運行或缺少用戶ID');
      return false;
    }
    
    // 停止當前服務
    await stopService();
    
    // 使用新間隔重新啟動
    return await startService(
      userId: _currentUserId!,
      intervalSeconds: newIntervalSeconds,
    );
  }
  
  /// 處理來自原生端的方法調用
  static Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onLocationUpdate':
        final args = Map<String, dynamic>.from(call.arguments);
        _handleLocationUpdate(args);
        break;
        
      case 'onServiceStatusChanged':
        final args = Map<String, dynamic>.from(call.arguments);
        _handleServiceStatusChanged(args);
        break;
        
      case 'onUploadResult':
        final args = Map<String, dynamic>.from(call.arguments);
        _handleUploadResult(args);
        break;
        
      case 'onError':
        final args = Map<String, dynamic>.from(call.arguments);
        _handleError(args);
        break;
        
      default:
        debugPrint('[EnhancedLocationService] 未知方法調用: ${call.method}');
    }
  }
  
  /// 處理位置更新
  static void _handleLocationUpdate(Map<String, dynamic> data) {
    debugPrint('[EnhancedLocationService] 📍 位置更新: ${data['latitude']}, ${data['longitude']}');
    
    _statsController.add({
      'event': 'location_update',
      'latitude': data['latitude'],
      'longitude': data['longitude'],
      'accuracy': data['accuracy'],
      'timestamp': data['timestamp'],
      'updateCount': data['updateCount'],
    });
  }
  
  /// 處理服務狀態變化
  static void _handleServiceStatusChanged(Map<String, dynamic> data) {
    final isRunning = data['isRunning'] == true;
    _isServiceRunning = isRunning;
    
    debugPrint('[EnhancedLocationService] 🔄 服務狀態變化: $isRunning');
    
    _statsController.add({
      'event': 'service_status_changed',
      'isRunning': isRunning,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// 處理上傳結果
  static void _handleUploadResult(Map<String, dynamic> data) {
    final success = data['success'] == true;
    final successCount = data['successCount'] ?? 0;
    final failureCount = data['failureCount'] ?? 0;
    
    debugPrint('[EnhancedLocationService] 📤 上傳結果: ${success ? '成功' : '失敗'} (成功:$successCount, 失敗:$failureCount)');
    
    _statsController.add({
      'event': 'upload_result',
      'success': success,
      'successCount': successCount,
      'failureCount': failureCount,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// 處理錯誤
  static void _handleError(Map<String, dynamic> data) {
    final error = data['error'] ?? 'Unknown error';
    debugPrint('[EnhancedLocationService] ❌ 錯誤: $error');
    
    _statsController.add({
      'event': 'error',
      'error': error,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// 保存服務狀態
  static Future<void> _saveServiceState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('enhanced_service_running', _isServiceRunning);
      await prefs.setString('enhanced_service_user_id', _currentUserId ?? '');
      await prefs.setInt('enhanced_service_interval', _currentInterval);
    } catch (e) {
      debugPrint('[EnhancedLocationService] 保存狀態失敗: $e');
    }
  }
  
  /// 清除服務狀態
  static Future<void> _clearServiceState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('enhanced_service_running');
      await prefs.remove('enhanced_service_user_id');
      await prefs.remove('enhanced_service_interval');
    } catch (e) {
      debugPrint('[EnhancedLocationService] 清除狀態失敗: $e');
    }
  }
  
  /// 恢復服務狀態
  static Future<void> _restoreServiceState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasRunning = prefs.getBool('enhanced_service_running') ?? false;
      final userId = prefs.getString('enhanced_service_user_id') ?? '';
      final interval = prefs.getInt('enhanced_service_interval') ?? 30;
      
      if (wasRunning && userId.isNotEmpty) {
        debugPrint('[EnhancedLocationService] 🔄 恢復服務狀態...');
        
        // 檢查原生服務是否真的在運行
        final isRunning = await isServiceRunning();
        
        if (isRunning) {
          _isServiceRunning = true;
          _currentUserId = userId;
          _currentInterval = interval;
          debugPrint('[EnhancedLocationService] ✅ 服務狀態已恢復');
        } else {
          // 如果原生服務沒在運行，清除狀態
          await _clearServiceState();
          debugPrint('[EnhancedLocationService] 🧹 清除過期狀態');
        }
      }
    } catch (e) {
      debugPrint('[EnhancedLocationService] 恢復狀態失敗: $e');
    }
  }
  
  /// 釋放資源
  static void dispose() {
    _statsController.close();
  }
}
