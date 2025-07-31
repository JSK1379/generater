import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

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
