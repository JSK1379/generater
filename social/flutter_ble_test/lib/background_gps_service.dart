import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'api_config.dart';
import 'gps_service.dart';
import 'foreground_location_service.dart';
import 'enhanced_foreground_location_service.dart';

/// 背景GPS服務管理器
/// 負責管理背景定位任務、通知等功能
class BackgroundGPSService {
  static const String _taskName = "backgroundGPSTask";
  
  static FlutterLocalNotificationsPlugin? _notifications;
  static Timer? _highFrequencyTimer;
  static String? _currentUserId;
  static StreamSubscription<Map<String, dynamic>>? _locationSubscription;
  static bool _useForegroundService = false;
  
  /// 初始化背景服務
  static Future<void> initialize() async {
    // 初始化 WorkManager
    await Workmanager().initialize(callbackDispatcher);
    
    // 初始化通知
    await _initializeNotifications();
    
    // 初始化前台定位服務
    await ForegroundLocationService.initialize();
    
    // 初始化增強版前台定位服務
    await EnhancedForegroundLocationService.initialize();
    
    // 檢查並恢復背景追蹤
    await _resumeBackgroundTrackingIfNeeded();
    
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
        AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }
  
  /// 檢查並恢復背景追蹤
  static Future<void> _resumeBackgroundTrackingIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('background_gps_enabled') ?? false;
      
      if (isEnabled) {
        final userId = prefs.getString('background_gps_user_id');
        final intervalSeconds = prefs.getInt('background_gps_interval_seconds');
        
        if (userId != null && intervalSeconds != null) {
          debugPrint('[BackgroundGPS] 🔄 恢復背景追蹤: $intervalSeconds秒間隔');
          await startBackgroundTracking(
            intervalSeconds: intervalSeconds,
            userId: userId,
          );
        }
      }
    } catch (e) {
      debugPrint('[BackgroundGPS] ❌ 恢復背景追蹤失敗: $e');
    }
  }
  
  /// 開始真正的背景GPS追蹤（類似Google Maps）
  /// [intervalSeconds] 追蹤間隔（秒），支援高頻率如5秒、10秒、30秒等
  /// [userId] 用戶ID
  /// 
  /// 特色：
  /// 1. 真正的背景運行（關閉APP也能繼續）
  /// 2. 高頻率定位（最低5秒間隔）
  /// 3. 智能省電策略
  /// 4. 防止系統殺死服務
  static Future<bool> startBackgroundTracking({
    int intervalSeconds = 30,
    required String userId,
  }) async {
    try {
      // 檢查定位權限
      if (!await GPSService.checkAndRequestBackgroundLocationPermission()) {
        debugPrint('[BackgroundGPS] 定位權限被拒絕，無法開始背景追蹤');
        return false;
      }

      // 停止現有的追蹤
      await stopBackgroundTracking();
      
      // 保存配置
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('background_gps_user_id', userId);
      await prefs.setInt('background_gps_interval_seconds', intervalSeconds);
      await prefs.setBool('background_gps_enabled', true);
      _currentUserId = userId;
      
      // 優先使用增強版前台服務（真正的背景運行）
      debugPrint('[BackgroundGPS] 🚀 啟動增強版前台服務...');
      final enhancedServiceStarted = await EnhancedForegroundLocationService.startService(
        userId: userId,
        intervalSeconds: intervalSeconds,
        showDetailedStats: true,
      );
      
      if (enhancedServiceStarted) {
        _useForegroundService = true;
        
        // 監聽增強版服務的統計數據
        EnhancedForegroundLocationService.statsStream.listen((stats) {
          _handleEnhancedServiceStats(stats);
        });
        
        debugPrint('[BackgroundGPS] ✅ 增強版前台服務已啟動，間隔: $intervalSeconds秒');
      } else {
        // 增強版服務啟動失敗，使用舊版前台服務
        debugPrint('[BackgroundGPS] ⚠️ 增強版服務啟動失敗，使用舊版前台服務');
        final foregroundServiceStarted = await ForegroundLocationService.startService(
          intervalSeconds: intervalSeconds,
          userId: userId,
        );
        
        if (foregroundServiceStarted) {
          _useForegroundService = true;
          
          // 監聽前台服務的位置更新
          _locationSubscription = ForegroundLocationService.locationStream.listen((locationData) {
            _onForegroundLocationReceived(locationData);
          });
          
          // 顯示前台服務通知
          await _showForegroundServiceNotification(intervalSeconds);
          
          debugPrint('[BackgroundGPS] ✅ 舊版前台服務已啟動，間隔: $intervalSeconds秒');
        } else {
          // 前台服務啟動失敗，使用Timer + WakeLock模式
          debugPrint('[BackgroundGPS] ⚠️ 前台服務啟動失敗，使用Timer + WakeLock模式');
          await _startTimerWithWakeLock(intervalSeconds, userId);
        }
      }
      
      // 立即記錄一次GPS位置（啟動時）
      try {
        debugPrint('[BackgroundGPS] 📍 啟動時立即記錄GPS位置...');
        await _recordGPSLocation(userId);
      } catch (e) {
        debugPrint('[BackgroundGPS] ⚠️ 啟動時GPS記錄失敗: $e');
      }
      
      debugPrint('[BackgroundGPS] ✅ 真正的背景GPS追蹤已開始，間隔: $intervalSeconds秒');
      debugPrint('[BackgroundGPS] 🔋 服務可在關閉APP後繼續運行');
      return true;
      
    } catch (e) {
      debugPrint('[BackgroundGPS] ❌ 開始背景追蹤失敗: $e');
      return false;
    }
  }

  /// 顯示前台服務通知（持續性）
  static Future<void> _showForegroundServiceNotification(int intervalSeconds) async {
    const androidDetails = AndroidNotificationDetails(
      'foreground_gps_service',
      'GPS前台服務',
      channelDescription: '高頻率GPS定位服務（類似Google Maps）',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      category: AndroidNotificationCategory.service,
      visibility: NotificationVisibility.public,
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
      'GPS追蹤運行中 🛰️',
      '高精度定位服務 - 每$intervalSeconds秒記錄位置',
      details,
    );
  }

  /// 使用Timer + WakeLock的備用高頻率追蹤
  static Future<void> _startTimerWithWakeLock(int intervalSeconds, String userId) async {
    _useForegroundService = false;
    
    // 顯示Timer模式通知
    await _showTimerModeNotification(intervalSeconds);
    
    // 啟動高頻率計時器
    _highFrequencyTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (timer) async {
        await _executeHighFrequencyGPSRecord();
      },
    );
    
    // 立即執行一次
    await _executeHighFrequencyGPSRecord();
  }

  /// 執行高頻率GPS記錄
  static Future<void> _executeHighFrequencyGPSRecord() async {
    if (_currentUserId == null) {
      debugPrint('[BackgroundGPS] ⚠️ GPS記錄：缺少用戶ID');
      return;
    }
    
    try {
      final result = await _recordLocationInBackground(_currentUserId!);
      
      if (result['success'] == true) {
        debugPrint('[BackgroundGPS] ✅ GPS記錄成功');
        
        // 檢查是否需要顯示通知
        final prefs = await SharedPreferences.getInstance();
        final showNotifications = prefs.getBool('show_gps_notifications') ?? false;
        if (showNotifications) {
          await showGPSRecordNotification(
            latitude: result['latitude'],
            longitude: result['longitude'],
            timestamp: result['timestamp'],
          );
        }
      } else {
        debugPrint('[BackgroundGPS] ❌ GPS記錄失敗: ${result['error']}');
      }
    } catch (e) {
      debugPrint('[BackgroundGPS] ❌ GPS記錄異常: $e');
    }
  }

  /// 顯示Timer模式通知
  static Future<void> _showTimerModeNotification(int intervalSeconds) async {
    const androidDetails = AndroidNotificationDetails(
      'timer_gps_mode',
      'GPS Timer模式',
      channelDescription: 'Timer定時GPS記錄（需保持前台）',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      color: Color.fromARGB(255, 255, 165, 0), // 橙色提醒
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
      2,
      'GPS追蹤運行中 ⚡ (Timer模式)',
      '每$intervalSeconds秒記錄 - 請保持應用前台運行',
      details,
    );
  }

  /// 立即記錄GPS位置（用於啟動時）
  static Future<void> _recordGPSLocation(String userId) async {
    try {
      // 使用 GPSService 的 recordCurrentLocation 方法
      final result = await GPSService.recordCurrentLocation(userId);
      
      if (result.success) {
        debugPrint('[BackgroundGPS] ✅ 啟動時GPS記錄成功: ${result.latitude}, ${result.longitude}');
        
        // 可選：顯示記錄成功通知
        final prefs = await SharedPreferences.getInstance();
        final showNotifications = prefs.getBool('show_gps_notifications') ?? false;
        if (showNotifications) {
          await BackgroundGPSService.showGPSRecordNotification(
            latitude: result.latitude!,
            longitude: result.longitude!,
            timestamp: result.timestamp!.toIso8601String(),
          );
        }
      } else {
        debugPrint('[BackgroundGPS] ❌ 啟動時GPS記錄失敗: ${result.error}');
      }
    } catch (e) {
      debugPrint('[BackgroundGPS] ❌ 啟動時GPS記錄異常: $e');
    }
  }

  /// 處理增強版服務的統計數據
  static Future<void> _handleEnhancedServiceStats(Map<String, dynamic> stats) async {
    try {
      final event = stats['event'] as String?;
      
      switch (event) {
        case 'location_update':
          final latitude = stats['latitude'] as double?;
          final longitude = stats['longitude'] as double?;
          final updateCount = stats['updateCount'] as int?;
          
          debugPrint('[BackgroundGPS] 📍 增強版服務位置更新 #$updateCount: $latitude, $longitude');
          
          // 檢查是否需要顯示通知
          final prefs = await SharedPreferences.getInstance();
          final showNotifications = prefs.getBool('show_gps_notifications') ?? false;
          if (showNotifications && latitude != null && longitude != null) {
            await showGPSRecordNotification(
              latitude: latitude,
              longitude: longitude,
              timestamp: stats['timestamp'] as String? ?? DateTime.now().toIso8601String(),
            );
          }
          break;
          
        case 'upload_result':
          final success = stats['success'] as bool? ?? false;
          final successCount = stats['successCount'] as int? ?? 0;
          final failureCount = stats['failureCount'] as int? ?? 0;
          
          debugPrint('[BackgroundGPS] 📤 增強版服務上傳結果: ${success ? '成功' : '失敗'} (總成功:$successCount, 總失敗:$failureCount)');
          break;
          
        case 'service_started':
          debugPrint('[BackgroundGPS] ✅ 增強版服務已啟動');
          break;
          
        case 'service_stopped':
          debugPrint('[BackgroundGPS] ⏹️ 增強版服務已停止');
          break;
          
        case 'error':
          final error = stats['error'] as String? ?? 'Unknown error';
          debugPrint('[BackgroundGPS] ❌ 增強版服務錯誤: $error');
          break;
          
        default:
          debugPrint('[BackgroundGPS] 📊 增強版服務統計: $stats');
      }
    } catch (e) {
      debugPrint('[BackgroundGPS] ❌ 處理增強版服務統計失敗: $e');
    }
  }

  /// 處理前台服務的位置更新
  static Future<void> _onForegroundLocationReceived(Map<String, dynamic> locationData) async {
    try {
      final latitude = locationData['latitude'] as double;
      final longitude = locationData['longitude'] as double;
      
      debugPrint('[BackgroundGPS] ✅ 前台服務GPS記錄成功: $latitude, $longitude');
      
      // 檢查是否需要顯示通知
      final prefs = await SharedPreferences.getInstance();
      final showNotifications = prefs.getBool('show_gps_notifications') ?? false;
      if (showNotifications) {
        await showGPSRecordNotification(
          latitude: latitude,
          longitude: longitude,
          timestamp: DateTime.now().toIso8601String(),
        );
      }
    } catch (e) {
      debugPrint('[BackgroundGPS] ❌ 處理前台服務位置更新失敗: $e');
    }
  }

  /// 停止背景GPS追蹤
  static Future<bool> stopBackgroundTracking() async {
    try {
      // 取消背景任務
      await Workmanager().cancelByUniqueName(_taskName);
      
      // 停止增強版前台服務
      await EnhancedForegroundLocationService.stopService();
      
      // 停止舊版前台服務
      if (_useForegroundService) {
        await ForegroundLocationService.stopService();
        _locationSubscription?.cancel();
        _locationSubscription = null;
        _useForegroundService = false;
      }
      
      // 停止計時器
      _highFrequencyTimer?.cancel();
      _highFrequencyTimer = null;
      _currentUserId = null;
      
      // 更新本地存儲
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('background_gps_enabled', false);
      
      // 取消所有通知
      await _notifications?.cancel(1);
      await _notifications?.cancel(2);
      
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
