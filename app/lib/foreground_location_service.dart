/// Legacy compatibility shim.
///
/// Background GPS now uses EnhancedForegroundLocationService exclusively.
/// This class remains temporarily because BackgroundGPSService still calls
/// initialize() during the migration. It intentionally performs no work.
@Deprecated('Use EnhancedForegroundLocationService via GpsTracker')
class ForegroundLocationService {
  ForegroundLocationService._();

  static Future<void> initialize() async {}
}
