class GPSRecordResult {
  final bool success;
  final int? recordId;
  final double? latitude;
  final double? longitude;
  final DateTime? timestamp;
  final String? error;

  const GPSRecordResult._({
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
    return GPSRecordResult._(success: false, error: error);
  }
}

class GPSHistoryResult {
  final bool success;
  final String? date;
  final int totalCount;
  final List<GPSLocation> locations;
  final String? error;

  const GPSHistoryResult._({
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
      locations: const [],
      error: error,
    );
  }
}

class GPSLocation {
  final int id;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  const GPSLocation({
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
      };

  @override
  String toString() {
    return 'GPSLocation(id: $id, lat: $latitude, lng: $longitude, time: $timestamp)';
  }
}

class GPSBackgroundStatus {
  final bool isEnabled;
  final String userId;
  final int intervalMinutes;
  final String? lastUpdateTime;

  const GPSBackgroundStatus({
    required this.isEnabled,
    required this.userId,
    required this.intervalMinutes,
    this.lastUpdateTime,
  });

  Map<String, dynamic> toJson() => {
        'isEnabled': isEnabled,
        'userId': userId,
        'intervalMinutes': intervalMinutes,
        'lastUpdateTime': lastUpdateTime,
      };

  @override
  String toString() {
    return 'GPSBackgroundStatus(enabled: $isEnabled, user: $userId, interval: ${intervalMinutes}min, lastUpdate: $lastUpdateTime)';
  }
}
