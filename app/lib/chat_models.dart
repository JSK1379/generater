class ChatMessage {
  final String id;
  final String type;
  final String sender;
  final String content;
  final DateTime timestamp;
  final String? imageUrl;
  final String? senderAvatar;

  ChatMessage({
    required this.id,
    required this.type,
    required this.sender,
    required this.content,
    required this.timestamp,
    this.imageUrl,
    this.senderAvatar,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] ?? '',
      type: json['type'] ?? 'text',
      sender: json['sender'] ?? '',
      content: json['content'] ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      imageUrl: json['imageUrl'],
      senderAvatar: json['senderAvatar'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'sender': sender,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'imageUrl': imageUrl,
      'senderAvatar': senderAvatar,
    };
  }
}

class ChatRoomHistory {
  final String roomId;
  final String roomName;
  final String lastMessage;
  final DateTime lastMessageTime;
  final String otherUserId;
  final String otherNickname;

  ChatRoomHistory({
    required this.roomId,
    required this.roomName,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.otherUserId,
    this.otherNickname = '',
  });

  factory ChatRoomHistory.fromJson(Map<String, dynamic> json) {
    return ChatRoomHistory(
      roomId: json['roomId'] ?? '',
      roomName: json['roomName'] ?? '',
      lastMessage: json['lastMessage'] ?? '',
      lastMessageTime: DateTime.tryParse(json['lastMessageTime'] ?? '') ?? DateTime.now(),
      otherUserId: json['otherUserId'] ?? '',
      otherNickname: json['otherNickname'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'roomId': roomId,
      'roomName': roomName,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime.toIso8601String(),
      'otherUserId': otherUserId,
      'otherNickname': otherNickname,
    };
  }
}

class ChatRoom {
  final String id;
  final String name;
  final List<String> participants;
  final DateTime createdAt;

  ChatRoom({
    required this.id,
    required this.name,
    required this.participants,
    required this.createdAt,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      participants: List<String>.from(json['participants'] ?? []),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'participants': participants,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
