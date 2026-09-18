import 'package:near_ride/features/chat/services/chat_service.dart';

/// Shared ChatService instance used by the whole app.
class ChatServiceSingleton {
  static ChatService? _instance;

  static ChatService get instance {
    _instance ??= ChatService();
    return _instance!;
  }

  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
