import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'api_config.dart';
import 'gps_service.dart';

/// 背景GPS服務管理器
/// 負責管理背景定位任務、通知等功能
class BackgroundGPSService {
  static const String _taskName = "backgroundGPSTask";
  static const String _taskTag = "gps_tracking";
  
  static FlutterLocalNotificationsPlugin? _notifications;
  
  /// 初始化背景服務
  static Future<void> initialize() async {
    // 初始化 WorkManager
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
    
    // 初始化通知
    await _initializeNotifications();
    
    debugPrint('[BackgroundGPS] 背景GPS服務初始化完成');
  }
  
  /// 初始化通知系統
  static Future<void> _initializeNotifications() async {
    _notifications = FlutterLocalNotificationsPlugin();
    
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications?.initialize(initSettings);
    
    // 請求通知權限
    await _notifications?.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.requestExactAlarmsPermission();
    
    await _notifications?.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }
  
  /// 開始背景GPS追蹤
  /// [intervalMinutes] 追蹤間隔（分鐘），默認15分鐘
  /// [userId] 用戶ID
  static Future<bool> startBackgroundTracking({
    int intervalMinutes = 15,
    required String userId,
  }) async {
    try {
      // 檢查定位權限
      if (!await GPSService.checkAndRequestLocationPermission()) {
        debugPrint('[BackgroundGPS] 定位權限被拒絕，無法開始背景追蹤');
        return false;
      }
      
      // 請求背景定位權限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.always) {
          debugPrint('[BackgroundGPS] 背景定位權限被拒絕');
          // 仍然可以在前台運行，所以不返回false
        }
      }
      
      // 保存用戶ID到本地存儲
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('background_gps_user_id', userId);
      await prefs.setInt('background_gps_interval', intervalMinutes);
      await prefs.setBool('background_gps_enabled', true);
      
      // 註冊背景任務
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskTag,
        frequency: Duration(minutes: intervalMinutes),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 1),
      );
      
      // 顯示持續通知
      await _showPersistentNotification();
      
      debugPrint('[BackgroundGPS] ✅ 背景GPS追蹤已開始，間隔: $intervalMinutes分鐘');
      return true;
      
    } catch (e) {
      debugPrint('[BackgroundGPS] ❌ 開始背景追蹤失敗: $e');
      return false;
    }
  }
  
  /// 停止背景GPS追蹤
  static Future<bool> stopBackgroundTracking() async {
    try {
      // 取消背景任務
      await Workmanager().cancelByUniqueName(_taskName);
      
      // 更新本地存儲
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('background_gps_enabled', false);
      
      // 取消持續通知
      await _notifications?.cancel(1);
      
      debugPrint('[BackgroundGPS] ✅ 背景GPS追蹤已停止');
      return true;
      
    } catch (e) {
      debugPrint('[BackgroundGPS] ❌ 停止背景追蹤失敗: $e');
      return false;
    }
  }
  
  /// 檢查背景追蹤狀態
  static Future<bool> isBackgroundTrackingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('background_gps_enabled') ?? false;
  }
  
  /// 獲取背景追蹤配置
  static Future<Map<String, dynamic>> getBackgroundTrackingConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'enabled': prefs.getBool('background_gps_enabled') ?? false,
      'userId': prefs.getString('background_gps_user_id') ?? '',
      'intervalMinutes': prefs.getInt('background_gps_interval') ?? 15,
    };
  }
  
  /// 顯示持續通知
  static Future<void> _showPersistentNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'background_gps_channel',
      '背景GPS追蹤',
      channelDescription: '持續追蹤GPS位置',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications?.show(
      1,
      'GPS追蹤運行中',
      '應用正在背景追蹤您的位置',
      details,
    );
  }
  
  /// 顯示GPS記錄成功通知
  static Future<void> showGPSRecordNotification({
    required double latitude,
    required double longitude,
    required String timestamp,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'gps_record_channel',
      'GPS記錄通知',
      channelDescription: 'GPS位置記錄結果通知',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      autoCancel: true,
      showWhen: true,
    );
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications?.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'GPS位置已記錄',
      '緯度: ${latitude.toStringAsFixed(6)}, 經度: ${longitude.toStringAsFixed(6)}',
      details,
    );
  }
}

/// WorkManager 回調函數
/// 這個函數會在背景執行
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[BackgroundGPS] 🔄 執行背景GPS任務: $task');
    
    try {
      // 獲取用戶配置
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('background_gps_user_id');
      final isEnabled = prefs.getBool('background_gps_enabled') ?? false;
      
      if (!isEnabled || userId == null || userId.isEmpty) {
        debugPrint('[BackgroundGPS] ⚠️ 背景GPS追蹤未啟用或缺少用戶ID');
        return Future.value(true);
      }
      
      // 執行GPS記錄
      final result = await _recordLocationInBackground(userId);
      
      if (result['success'] == true) {
        debugPrint('[BackgroundGPS] ✅ 背景GPS記錄成功');
        
        // 顯示記錄成功通知（可選）
        final showNotifications = prefs.getBool('show_gps_notifications') ?? false;
        if (showNotifications) {
          await BackgroundGPSService.showGPSRecordNotification(
            latitude: result['latitude'],
            longitude: result['longitude'],
            timestamp: result['timestamp'],
          );
        }
      } else {
        debugPrint('[BackgroundGPS] ❌ 背景GPS記錄失敗: ${result['error']}');
      }
      
      return Future.value(result['success'] == true);
      
    } catch (e) {
      debugPrint('[BackgroundGPS] ❌ 背景任務異常: $e');
      return Future.value(false);
    }
  });
}

/// 在背景記錄GPS位置
/// 這是一個獨立的函數，不依賴Flutter上下文
Future<Map<String, dynamic>> _recordLocationInBackground(String userId) async {
  try {
    // 檢查定位服務是否可用
    if (!await Geolocator.isLocationServiceEnabled()) {
      return {'success': false, 'error': '定位服務未開啟'};
    }
    
    // 檢查權限
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return {'success': false, 'error': '定位權限被拒絕'};
    }
    
    // 獲取當前位置
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        timeLimit: Duration(seconds: 30), // 設置超時時間
      ),
    );
    
    // 準備上傳數據
    final url = Uri.parse('${ApiConfig.gpsLocation}?user_id=$userId');
    final body = jsonEncode({
      'lat': position.latitude,
      'lng': position.longitude,
      'ts': DateTime.now().toIso8601String(),
    });
    
    final response = await http.post(
      url,
      body: body,
      headers: ApiConfig.jsonHeaders,
    ).timeout(const Duration(seconds: 30));
    
    if (response.statusCode == 200) {
      return {
        'success': true,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } else {
      return {
        'success': false,
        'error': 'HTTP ${response.statusCode}: ${response.body}',
      };
    }
    
  } catch (e) {
    return {
      'success': false,
      'error': e.toString(),
    };
  }
}
