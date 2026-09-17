import 'package:flutter/foundation.dart';

/// Central runtime configuration for Near Ride network endpoints.
///
/// Production URLs can be overridden at build time:
///
/// flutter run \
///   --dart-define=API_URL=https://example.com \
///   --dart-define=WS_URL=wss://example.com
class ApiConfig {
  ApiConfig._();

  static const String _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://near-ride-backend-api.onrender.com',
  );

  static const String _wsBaseUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'wss://near-ride-backend-api.onrender.com',
  );

  static String get baseUrl => _baseUrl;
  static String get wsBaseUrl => _wsBaseUrl;

  static String get health => '$_baseUrl/health';

  // Users
  static String get users => '$_baseUrl/users';
  static String userProfile(String userId) => '$_baseUrl/users/$userId';
  static String userAvatar(String userId) => '$_baseUrl/users/$userId/avatar';

  // GPS
  static String get gpsLocation => '$_baseUrl/gps/location';
  static String get gpsUpload => '$_baseUrl/gps/upload';
  static String gpsUserLocations(String userId) =>
      '$_baseUrl/gps/locations/$userId';
  static String gpsUserLocationsByDate(String userId, String date) =>
      '$_baseUrl/gps/locations/$userId/date/$date';
  static String gpsDeleteLocations(String userId) =>
      '$_baseUrl/gps/locations/$userId';
  static String gpsSimilarUsers(String userId) =>
      '$_baseUrl/gps/similar/$userId';

  // Chat / Friends
  static String get chatHistory => '$_baseUrl/chat_history';
  static String friendsChatHistory(String roomId, {int? limit}) {
    final uri = '$_baseUrl/friends/chat_history/$roomId';
    return limit == null ? uri : '$uri?limit=$limit';
  }

  static String get addFriend => '$_baseUrl/friends/add_friend';
  static String friendsList(String userId) =>
      '$_baseUrl/friends/friends/$userId';

  // Images
  static String get imageUpload => '$_baseUrl/images/upload';
  static String imageUrl(String imageId) => '$_baseUrl/images/$imageId';

  // WebSocket
  static String get wsUrl => '$_wsBaseUrl/ws';

  static const Map<String, String> jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  static const Duration defaultTimeout = Duration(seconds: 15);
  static const Duration uploadTimeout = Duration(seconds: 30);
  static const Duration wsTimeout = Duration(seconds: 15);

  static void printEndpoint(String name, String url) {
    if (kDebugMode) {
      debugPrint('[ApiConfig] $name: $url');
    }
  }
}
