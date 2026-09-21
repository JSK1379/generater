/// Global manager that prevents the same chat room from being opened twice.
class ChatRoomOpenManager {
  static final ChatRoomOpenManager _instance = ChatRoomOpenManager._internal();

  factory ChatRoomOpenManager() => _instance;

  ChatRoomOpenManager._internal();

  final Set<String> _openingRooms = <String>{};

  bool isRoomOpening(String roomId) => _openingRooms.contains(roomId);

  bool markRoomAsOpening(String roomId) {
    if (_openingRooms.contains(roomId)) {
      return false;
    }
    _openingRooms.add(roomId);
    return true;
  }

  void markRoomAsClosed(String roomId) {
    _openingRooms.remove(roomId);
  }

  void clearAll() {
    _openingRooms.clear();
  }
}
