/// 🌐 統一的API配置檔案
/// 集中管理所有API端點，方便維護和更新
class ApiConfig {
  // 🏠 基礎URL配置
  static const String _baseUrl = 'https://near-ride-backend-api.onrender.com';
  static const String _wsBaseUrl = 'wss://near-ride-backend-api.onrender.com';
  
  // 📡 HTTP API 端點
  static String get baseUrl => _baseUrl;
  static String get health => '$_baseUrl/health';
  static String get users => '$_baseUrl/users';
  static String userProfile(String userId) => '$_baseUrl/users/$userId';
  static String userAvatar(String userId) => '$_baseUrl/users/$userId/avatar';
  
  // 🗂️ GPS 相關端點
  static String get gpsUpload => '$_baseUrl/gps/upload';
  static String gpsRoute(String userId, String date) => '$_baseUrl/gps/$userId/$date';
  static String gpsHistory(String userId) => '$_baseUrl/gps/$userId/routes';
  
  // 💬 聊天相關端點
  static String get chatHistory => '$_baseUrl/chat_history';
  static String friendsChatHistory(String roomId, {int? limit}) {
    final uri = '$_baseUrl/friends/chat_history/$roomId';
    return limit != null ? '$uri?limit=$limit' : uri;
  }
  static String get addFriend => '$_baseUrl/friends/add_friend';
  static String friendsList(String userId) => '$_baseUrl/friends/friends/$userId';
  
  // 🔌 WebSocket 端點
  static String get wsUrl => '$_wsBaseUrl/ws';
  
  // 📋 常用的HTTP標頭
  static Map<String, String> get jsonHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
  
  // ⚙️ 超時設定
  static const Duration defaultTimeout = Duration(seconds: 15);
  static const Duration uploadTimeout = Duration(seconds: 30);
  static const Duration wsTimeout = Duration(seconds: 10);
  
  // 🔧 調試用功能
  static void printEndpoint(String name, String url) {
    if (const bool.fromEnvironment('dart.vm.product') == false) {
      print('[ApiConfig] $name: $url');
    }
  }
}
