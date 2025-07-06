import 'chat_service.dart';

/// 全局 ChatService 單例，確保整個應用使用同一個 WebSocket 連線
class ChatServiceSingleton {
  static ChatService? _instance;
  
  /// 獲取 ChatService 單例實例
  static ChatService get instance {
    _instance ??= ChatService();
    return _instance!;
  }
  
  /// 重置實例（僅在需要時使用，如重新登入）
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
