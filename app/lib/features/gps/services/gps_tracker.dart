import 'package:near_ride/features/gps/services/background_gps_service.dart';

/// Single application-facing entry point for background GPS tracking.
///
/// The implementation currently delegates to [BackgroundGPSService]. This
/// keeps pages and app bootstrap code independent from the underlying Android
/// foreground-service / WorkManager details so those can be replaced later
/// without touching UI code.
class GpsTracker {
  GpsTracker._();

  static Future<void> initialize() => BackgroundGPSService.initialize();

  static Future<bool> start({
    required String userId,
    int intervalSeconds = 30,
    Map<String, dynamic>? commuteTimeSettings,
    bool skipCommuteTimeCheck = false,
  }) {
    return BackgroundGPSService.startBackgroundTracking(
      userId: userId,
      intervalSeconds: intervalSeconds,
      commuteTimeSettings: commuteTimeSettings,
      skipCommuteTimeCheck: skipCommuteTimeCheck,
    );
  }

  static Future<bool> stop() => BackgroundGPSService.stopBackgroundTracking();

  static Future<bool> isEnabled() =>
      BackgroundGPSService.isBackgroundTrackingEnabled();

  static Future<Map<String, dynamic>> config() =>
      BackgroundGPSService.getBackgroundTrackingConfig();
}
