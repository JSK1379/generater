import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:near_ride/background_gps_service.dart';
import 'package:near_ride/core/config/api_config.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gps_models.dart';

export '../models/gps_models.dart';

/// Public GPS facade used by UI code.
///
/// Keeps permission checks, point API calls and background tracking behind one
/// entry point while data models live separately under `models/`.
class GPSService {
  GPSService._();

  static Future<bool> checkAndRequestLocationPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }
    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  static Future<bool> checkAndRequestBackgroundLocationPermission() async {
    try {
      if (!await checkAndRequestLocationPermission()) {
        return false;
      }

      var foreground = await Permission.location.status;
      final background = await Permission.locationAlways.status;
      if (background.isGranted) {
        return true;
      }

      if (!foreground.isGranted) {
        foreground = await Permission.location.request();
        if (!foreground.isGranted) {
          return false;
        }
      }

      final result = await Permission.locationAlways.request();
      if (result.isGranted || result.isDenied) {
        // Foreground GPS remains available when background permission is denied.
        return true;
      }
      if (result.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      return true;
    } catch (error) {
      debugPrint('[GPSService] permission error: $error');
      return false;
    }
  }

  static Future<GPSRecordResult> recordCurrentLocation(String userId) async {
    try {
      if (!await checkAndRequestLocationPermission()) {
        return GPSRecordResult.error('定位權限被拒絕');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      );
      final now = DateTime.now();
      final response = await http.post(
        Uri.parse('${ApiConfig.gpsLocation}?user_id=$userId'),
        headers: ApiConfig.jsonHeaders,
        body: jsonEncode({
          'lat': position.latitude,
          'lng': position.longitude,
          'ts': now.toIso8601String(),
        }),
      );

      if (response.statusCode != 200) {
        return GPSRecordResult.error('記錄失敗: HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return GPSRecordResult.success(
        recordId: (data['id'] as num).toInt(),
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: now,
      );
    } catch (error) {
      debugPrint('[GPSService] record location error: $error');
      return GPSRecordResult.error('記錄失敗: $error');
    }
  }

  static Future<GPSHistoryResult> getLocationHistory(
    String userId, {
    String? date,
  }) async {
    final targetDate =
        date ?? DateTime.now().toIso8601String().substring(0, 10);
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.gpsUserLocationsByDate(userId, targetDate)),
        headers: ApiConfig.jsonHeaders,
      );
      if (response.statusCode == 404) {
        return GPSHistoryResult.success(
          date: targetDate,
          totalCount: 0,
          locations: const [],
        );
      }
      if (response.statusCode != 200) {
        return GPSHistoryResult.error('查詢失敗: HTTP ${response.statusCode}');
      }
      return _historyFromResponse(response.body, date: targetDate);
    } catch (error) {
      debugPrint('[GPSService] history error: $error');
      return GPSHistoryResult.error('查詢失敗: $error');
    }
  }

  static Future<GPSHistoryResult> getUserLocations(
    String userId, {
    String? startDate,
    String? endDate,
    int? limit,
  }) async {
    try {
      var uri = Uri.parse(ApiConfig.gpsUserLocations(userId));
      final query = <String, String>{};
      if (startDate != null) query['start_date'] = startDate;
      if (endDate != null) query['end_date'] = endDate;
      if (limit != null) query['limit'] = limit.toString();
      if (query.isNotEmpty) {
        uri = uri.replace(queryParameters: query);
      }

      final response = await http.get(uri, headers: ApiConfig.jsonHeaders);
      if (response.statusCode == 404) {
        return GPSHistoryResult.success(
          totalCount: 0,
          locations: const [],
        );
      }
      if (response.statusCode != 200) {
        return GPSHistoryResult.error('查詢失敗: HTTP ${response.statusCode}');
      }
      return _historyFromResponse(response.body);
    } catch (error) {
      debugPrint('[GPSService] user locations error: $error');
      return GPSHistoryResult.error('查詢失敗: $error');
    }
  }

  static GPSHistoryResult _historyFromResponse(
    String body, {
    String? date,
  }) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final rawLocations = data['locations'] as List<dynamic>? ?? const [];
    final locations = rawLocations
        .whereType<Map<String, dynamic>>()
        .map(GPSLocation.fromJson)
        .toList(growable: false);
    return GPSHistoryResult.success(
      date: date,
      totalCount: (data['total_locations'] as num?)?.toInt() ?? locations.length,
      locations: locations,
    );
  }

  static Future<bool> startBackgroundTracking(
    String userId, {
    int intervalMinutes = 15,
  }) async {
    try {
      await BackgroundGPSService.initialize();
      final success = await BackgroundGPSService.startBackgroundTracking(
        intervalSeconds: intervalMinutes * 60,
        userId: userId,
      );
      if (!success) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('gps_background_tracking', true);
      await prefs.setString('gps_tracking_user_id', userId);
      await prefs.setInt('gps_tracking_interval', intervalMinutes);
      return true;
    } catch (error) {
      debugPrint('[GPSService] start tracking error: $error');
      return false;
    }
  }

  static Future<bool> stopBackgroundTracking() async {
    try {
      final success = await BackgroundGPSService.stopBackgroundTracking();
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('gps_background_tracking', false);
      }
      return success;
    } catch (error) {
      debugPrint('[GPSService] stop tracking error: $error');
      return false;
    }
  }

  static Future<GPSBackgroundStatus> getBackgroundTrackingStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = await BackgroundGPSService.isBackgroundTrackingEnabled();
      final config = await BackgroundGPSService.getBackgroundTrackingConfig();
      return GPSBackgroundStatus(
        isEnabled: enabled,
        userId: config['userId']?.toString() ?? '',
        intervalMinutes: (config['intervalMinutes'] as num?)?.toInt() ?? 15,
        lastUpdateTime: prefs.getString('gps_last_update'),
      );
    } catch (error) {
      debugPrint('[GPSService] status error: $error');
      return const GPSBackgroundStatus(
        isEnabled: false,
        userId: '',
        intervalMinutes: 15,
      );
    }
  }

  static Future<bool> updateBackgroundTrackingInterval(
    int intervalMinutes,
  ) async {
    final status = await getBackgroundTrackingStatus();
    if (!status.isEnabled || status.userId.isEmpty) {
      return false;
    }
    if (!await stopBackgroundTracking()) {
      return false;
    }
    return startBackgroundTracking(
      status.userId,
      intervalMinutes: intervalMinutes,
    );
  }
}
