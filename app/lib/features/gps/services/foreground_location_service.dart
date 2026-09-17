/// Legacy compatibility shim.
///
/// Background GPS now uses EnhancedForegroundLocationService exclusively.
@Deprecated('Use EnhancedForegroundLocationService via GpsTracker')
class ForegroundLocationService {
  ForegroundLocationService._();

  static Future<void> initialize() async {}
}
