import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'background_gps_service.dart';

/// GPS定位服務類
/// 提供GPS記錄、查詢等功能
class GPSService {
  /// 檢查並請求定位權限
  static Future<bool> checkAndRequestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return false;
      }
    }
    return true;
  }

  /// 檢查並請求背景定位權限
  /// 這個方法會先確保前台定位權限，然後請求背景定位權限
  static Future<bool> checkAndRequestBackgroundLocationPermission() async {
    try {
      // 首先檢查並請求基本定位權限
      if (!await checkAndRequestLocationPermission()) {
        debugPrint('[GPSService] 基本定位權限被拒絕');
        return false;
      }

      // 使用 permission_handler 檢查權限狀態
      final locationPermission = await Permission.location.status;
      final backgroundLocationPermission = await Permission.locationAlways.status;
      
      debugPrint('[GPSService] 位置權限狀態: $locationPermission');
      debugPrint('[GPSService] 背景位置權限狀態: $backgroundLocationPermission');

      // 如果已經有背景位置權限，直接返回成功
      if (backgroundLocationPermission.isGranted) {
        debugPrint('[GPSService] ✅ 已有背景定位權限');
        return true;
      }

      // 確保前台位置權限已授權
      if (!locationPermission.isGranted) {
        debugPrint('[GPSService] 🔄 請求前台位置權限...');
        final result = await Permission.location.request();
        if (!result.isGranted) {
          debugPrint('[GPSService] ❌ 前台位置權限被拒絕');
          return false;
        }
      }

      // 請求背景位置權限
      debugPrint('[GPSService] 🔄 請求背景定位權限...');
      final backgroundResult = await Permission.locationAlways.request();
      
      if (backgroundResult.isGranted) {
        debugPrint('[GPSService] ✅ 背景定位權限授權成功');
        return true;
      } else if (backgroundResult.isDenied) {
        debugPrint('[GPSService] ⚠️ 背景定位權限被拒絕，但前台權限可用');
        return true; // 仍然可以在前台使用
      } else if (backgroundResult.isPermanentlyDenied) {
        debugPrint('[GPSService] ❌ 背景定位權限被永久拒絕');
        // 引導用戶到設定頁面
        await _showPermissionDialog();
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('[GPSService] ❌ 權限請求異常: $e');
      return false;
    }
  }

  /// 顯示權限設定對話框
  static Future<void> _showPermissionDialog() async {
    debugPrint('[GPSService] 💡 引導用戶到設定頁面設定權限');
    // 可以選擇開啟應用設定頁面
    await openAppSettings();
  }

  /// 記錄當前GPS位置
  /// [userId] 用戶ID
  /// 返回記錄結果，包含是否成功、記錄ID、錯誤信息等
  static Future<GPSRecordResult> recordCurrentLocation(String userId) async {
    try {
      // 檢查定位權限
      if (!await checkAndRequestLocationPermission()) {
        return GPSRecordResult.error('定位權限被拒絕');
      }

      // 獲取當前位置
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
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
      );

      debugPrint('GPS位置記錄結果: ${response.statusCode} ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return GPSRecordResult.success(
          recordId: responseData['id'],
          latitude: position.latitude,
          longitude: position.longitude,
          timestamp: DateTime.now(),
        );
      } else {
        return GPSRecordResult.error('記錄失敗: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('GPS位置記錄異常: $e');
      return GPSRecordResult.error('記錄失敗: $e');
    }
  }

  /// 獲取指定日期的GPS記錄
  /// [userId] 用戶ID
  /// [date] 日期，格式 YYYY-MM-DD，默認為今日
  static Future<GPSHistoryResult> getLocationHistory(
    String userId, {
    String? date,
  }) async {
    try {
      final targetDate = date ?? DateTime.now().toIso8601String().substring(0, 10);
      final url = Uri.parse(ApiConfig.gpsUserLocationsByDate(userId, targetDate));

      final response = await http.get(url, headers: ApiConfig.jsonHeaders);
      
      debugPrint('GPS歷史查詢結果: ${response.statusCode} ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final totalLocations = responseData['total_locations'] ?? 0;
        final locations = (responseData['locations'] as List? ?? [])
            .map((loc) => GPSLocation.fromJson(loc))
            .toList();

        return GPSHistoryResult.success(
          date: targetDate,
          totalCount: totalLocations,
          locations: locations,
        );
      } else if (response.statusCode == 404) {
        return GPSHistoryResult.success(
          date: targetDate,
          totalCount: 0,
          locations: [],
        );
      } else {
        return GPSHistoryResult.error('查詢失敗: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('GPS歷史查詢異常: $e');
      return GPSHistoryResult.error('查詢失敗: $e');
    }
  }

  /// 獲取用戶的GPS記錄（帶參數）
  /// [userId] 用戶ID
  /// [startDate] 開始日期 YYYY-MM-DD
  /// [endDate] 結束日期 YYYY-MM-DD
  /// [limit] 限制返回數量
  static Future<GPSHistoryResult> getUserLocations(
    String userId, {
    String? startDate,
    String? endDate,
    int? limit,
  }) async {
    try {
      var url = Uri.parse(ApiConfig.gpsUserLocations(userId));
      
      // 添加查詢參數
      final queryParams = <String, String>{};
      if (startDate != null) queryParams['start_date'] = startDate;
      if (endDate != null) queryParams['end_date'] = endDate;
      if (limit != null) queryParams['limit'] = limit.toString();
      
      if (queryParams.isNotEmpty) {
        url = url.replace(queryParameters: queryParams);
      }

      final response = await http.get(url, headers: ApiConfig.jsonHeaders);
      
      debugPrint('用戶GPS記錄查詢結果: ${response.statusCode} ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final totalLocations = responseData['total_locations'] ?? 0;
        final locations = (responseData['locations'] as List? ?? [])
            .map((loc) => GPSLocation.fromJson(loc))
            .toList();

        return GPSHistoryResult.success(
          totalCount: totalLocations,
          locations: locations,
        );
      } else if (response.statusCode == 404) {
        return GPSHistoryResult.success(
          totalCount: 0,
          locations: [],
        );
      } else {
        return GPSHistoryResult.error('查詢失敗: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('用戶GPS記錄查詢異常: $e');
      return GPSHistoryResult.error('查詢失敗: $e');
    }
  }

  /// 🔄 開始背景GPS追蹤
  /// [userId] 用戶ID
  /// [intervalMinutes] 追蹤間隔（分鐘），默認15分鐘
  static Future<bool> startBackgroundTracking(
    String userId, {
    int intervalMinutes = 15,
  }) async {
    try {
      // 初始化背景服務
      await BackgroundGPSService.initialize();
      
      // 開始背景追蹤（轉換分鐘為秒）
      final success = await BackgroundGPSService.startBackgroundTracking(
        intervalSeconds: intervalMinutes * 60,
        userId: userId,
      );
      
      if (success) {
        // 保存追蹤狀態到本地
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('gps_background_tracking', true);
        await prefs.setString('gps_tracking_user_id', userId);
        await prefs.setInt('gps_tracking_interval', intervalMinutes);
        
        debugPrint('[GPSService] ✅ 背景GPS追蹤已啟動');
        return true;
      } else {
        debugPrint('[GPSService] ❌ 背景GPS追蹤啟動失敗');
        return false;
      }
    } catch (e) {
      debugPrint('[GPSService] ❌ 啟動背景追蹤異常: $e');
      return false;
    }
  }

  /// 🛑 停止背景GPS追蹤
  static Future<bool> stopBackgroundTracking() async {
    try {
      final success = await BackgroundGPSService.stopBackgroundTracking();
      
      if (success) {
        // 更新本地狀態
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('gps_background_tracking', false);
        
        debugPrint('[GPSService] ✅ 背景GPS追蹤已停止');
        return true;
      } else {
        debugPrint('[GPSService] ❌ 背景GPS追蹤停止失敗');
        return false;
      }
    } catch (e) {
      debugPrint('[GPSService] ❌ 停止背景追蹤異常: $e');
      return false;
    }
  }

  /// 📊 獲取背景追蹤狀態
  static Future<GPSBackgroundStatus> getBackgroundTrackingStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = await BackgroundGPSService.isBackgroundTrackingEnabled();
      final config = await BackgroundGPSService.getBackgroundTrackingConfig();
      
      return GPSBackgroundStatus(
        isEnabled: isEnabled,
        userId: config['userId'] ?? '',
        intervalMinutes: config['intervalMinutes'] ?? 15,
        lastUpdateTime: prefs.getString('gps_last_update'),
      );
    } catch (e) {
      debugPrint('[GPSService] ❌ 獲取背景追蹤狀態異常: $e');
      return GPSBackgroundStatus(
        isEnabled: false,
        userId: '',
        intervalMinutes: 15,
      );
    }
  }

  /// 🔧 更新背景追蹤間隔
  /// [intervalMinutes] 新的追蹤間隔（分鐘）
  static Future<bool> updateBackgroundTrackingInterval(int intervalMinutes) async {
    try {
      final status = await getBackgroundTrackingStatus();
      
      if (status.isEnabled && status.userId.isNotEmpty) {
        // 先停止當前追蹤
        await stopBackgroundTracking();
        
        // 以新間隔重新開始
        return await startBackgroundTracking(
          status.userId,
          intervalMinutes: intervalMinutes,
        );
      } else {
        debugPrint('[GPSService] ⚠️ 背景追蹤未啟用，無法更新間隔');
        return false;
      }
    } catch (e) {
      debugPrint('[GPSService] ❌ 更新背景追蹤間隔異常: $e');
      return false;
    }
  }
}

/// GPS記錄結果
class GPSRecordResult {
  final bool success;
  final int? recordId;
  final double? latitude;
  final double? longitude;
  final DateTime? timestamp;
  final String? error;

  GPSRecordResult._({
    required this.success,
    this.recordId,
    this.latitude,
    this.longitude,
    this.timestamp,
    this.error,
  });

  factory GPSRecordResult.success({
    required int recordId,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
  }) {
    return GPSRecordResult._(
      success: true,
      recordId: recordId,
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
    );
  }

  factory GPSRecordResult.error(String error) {
    return GPSRecordResult._(
      success: false,
      error: error,
    );
  }
}

/// GPS歷史查詢結果
class GPSHistoryResult {
  final bool success;
  final String? date;
  final int totalCount;
  final List<GPSLocation> locations;
  final String? error;

  GPSHistoryResult._({
    required this.success,
    this.date,
    required this.totalCount,
    required this.locations,
    this.error,
  });

  factory GPSHistoryResult.success({
    String? date,
    required int totalCount,
    required List<GPSLocation> locations,
  }) {
    return GPSHistoryResult._(
      success: true,
      date: date,
      totalCount: totalCount,
      locations: locations,
    );
  }

  factory GPSHistoryResult.error(String error) {
    return GPSHistoryResult._(
      success: false,
      totalCount: 0,
      locations: [],
      error: error,
    );
  }
}

/// GPS位置信息
class GPSLocation {
  final int id;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  GPSLocation({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory GPSLocation.fromJson(Map<String, dynamic> json) {
    return GPSLocation(
      id: json['id'] ?? 0,
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'GPSLocation(id: $id, lat: $latitude, lng: $longitude, time: $timestamp)';
  }
}

/// GPS背景追蹤狀態
class GPSBackgroundStatus {
  final bool isEnabled;
  final String userId;
  final int intervalMinutes;
  final String? lastUpdateTime;

  GPSBackgroundStatus({
    required this.isEnabled,
    required this.userId,
    required this.intervalMinutes,
    this.lastUpdateTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'isEnabled': isEnabled,
      'userId': userId,
      'intervalMinutes': intervalMinutes,
      'lastUpdateTime': lastUpdateTime,
    };
  }

  @override
  String toString() {
    return 'GPSBackgroundStatus(enabled: $isEnabled, user: $userId, interval: ${intervalMinutes}min, lastUpdate: $lastUpdateTime)';
  }
}
