// 全局的防重複開啟管理器
// 這個類用於跨頁面管理聊天室的開啟狀態，避免重複開啟同一個聊天室
class ChatRoomOpenManager {
  // 單例模式
  static final ChatRoomOpenManager _instance = ChatRoomOpenManager._internal();
  factory ChatRoomOpenManager() => _instance;
  ChatRoomOpenManager._internal();

  // 目前已開啟的聊天室集合
  final Set<String> _openingRooms = {};

  // 檢查聊天室是否已開啟
  bool isRoomOpening(String roomId) {
    return _openingRooms.contains(roomId);
  }

  // 標記聊天室為已開啟
  bool markRoomAsOpening(String roomId) {
    if (_openingRooms.contains(roomId)) {
      return false; // 已經開啟，不需再次標記
    }
    _openingRooms.add(roomId);
    return true; // 成功標記
  }

  // 標記聊天室為已關閉
  void markRoomAsClosed(String roomId) {
    _openingRooms.remove(roomId);
  }

  // 清除所有開啟狀態
  void clearAll() {
    _openingRooms.clear();
  }
}
