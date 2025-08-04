import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// 前台定位服務管理器
/// 使用 Android 原生前台服務實現真正的背景 GPS 追蹤
class ForegroundLocationService {
  static const MethodChannel _channel = MethodChannel('location_foreground_service');
  static StreamController<Map<String, dynamic>>? _locationController;
  static bool _isServiceRunning = false;
  
  /// 位置更新流
  static Stream<Map<String, dynamic>> get locationStream {
    _locationController ??= StreamController<Map<String, dynamic>>.broadcast();
    return _locationController!.stream;
  }
  
  /// 初始化服務
  static Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleMethodCall);
    debugPrint('[ForegroundLocationService] 服務已初始化');
  }
  
  /// 處理來自原生的方法調用
  static Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onLocationUpdate':
        final arguments = call.arguments as Map<dynamic, dynamic>;
        final locationData = {
          'latitude': arguments['latitude'] as double,
          'longitude': arguments['longitude'] as double,
          'timestamp': arguments['timestamp'] as int,
        };
        
        _locationController?.add(locationData);
        debugPrint('[ForegroundLocationService] 收到位置更新: ${locationData['latitude']}, ${locationData['longitude']}');
        break;
      default:
        debugPrint('[ForegroundLocationService] 未知方法: ${call.method}');
    }
  }
  
  /// 開始前台定位服務
  /// [intervalSeconds] 位置更新間隔（秒）
  /// [userId] 用戶ID
  static Future<bool> startService({
    required int intervalSeconds,
    required String userId,
  }) async {
    try {
      final result = await _channel.invokeMethod('startForegroundService', {
        'intervalSeconds': intervalSeconds,
        'userId': userId,
      });
      
      _isServiceRunning = result == true;
      
      if (_isServiceRunning) {
        debugPrint('[ForegroundLocationService] ✅ 前台定位服務已啟動，間隔: $intervalSeconds秒');
      } else {
        debugPrint('[ForegroundLocationService] ❌ 前台定位服務啟動失敗');
      }
      
      return _isServiceRunning;
    } on PlatformException catch (e) {
      debugPrint('[ForegroundLocationService] ❌ 啟動服務失敗: ${e.message}');
      return false;
    }
  }
  
  /// 停止前台定位服務
  static Future<bool> stopService() async {
    try {
      final result = await _channel.invokeMethod('stopForegroundService');
      _isServiceRunning = false;
      
      debugPrint('[ForegroundLocationService] ✅ 前台定位服務已停止');
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('[ForegroundLocationService] ❌ 停止服務失敗: ${e.message}');
      return false;
    }
  }
  
  /// 手動上傳位置到服務器
  /// [latitude] 緯度
  /// [longitude] 經度
  static Future<bool> uploadLocation({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final result = await _channel.invokeMethod('uploadLocation', {
        'latitude': latitude,
        'longitude': longitude,
      });
      
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('[ForegroundLocationService] ❌ 上傳位置失敗: ${e.message}');
      return false;
    }
  }
  
  /// 檢查服務是否正在運行
  static bool get isServiceRunning => _isServiceRunning;
  
  /// 清理資源
  static void dispose() {
    _locationController?.close();
    _locationController = null;
    _isServiceRunning = false;
  }
}
