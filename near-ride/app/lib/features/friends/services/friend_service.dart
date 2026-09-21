import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FriendService {
  FriendService(this.baseUrl);

  final String baseUrl;

  String get _base => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  Future<String?> addFriend(String userId, String friendId) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/friends/add_friend'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'friend_id': friendId}),
      );
      if (response.statusCode != 200) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['room_id']?.toString();
    } catch (error) {
      debugPrint('[FriendService] add friend error: $error');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> getFriends(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$_base/friends/friends/$userId'),
      );
      if (response.statusCode != 200) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = data['friends'] as List<dynamic>? ?? const [];
      return raw.whereType<Map<String, dynamic>>().toList(growable: false);
    } catch (error) {
      debugPrint('[FriendService] friends error: $error');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> getChatHistory(
    String roomId, {
    int limit = 50,
  }) async {
    const maxRetries = 3;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await http
            .get(Uri.parse('$_base/friends/chat_history/$roomId?limit=$limit'))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          if (attempt == maxRetries) return null;
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }

        final data = jsonDecode(response.body);
        final List<dynamic>? raw = switch (data) {
          List<dynamic>() => data,
          Map<String, dynamic>() =>
            (data['messages'] ?? data['chat_history']) as List<dynamic>?,
          _ => null,
        };
        if (raw == null) return const [];

        return raw.whereType<Map<String, dynamic>>().map((message) {
          return <String, dynamic>{
            'id': message['id']?.toString() ?? '',
            'type': message['image_url'] != null ? 'image' : 'text',
            'content': message['content'] ?? '',
            'sender':
                message['sender_id']?.toString() ?? message['sender']?.toString() ?? '',
            'timestamp': message['timestamp'] ?? '',
            'image_url': message['image_url'],
          };
        }).toList(growable: false);
      } catch (error) {
        debugPrint('[FriendService] chat history attempt $attempt: $error');
        if (attempt == maxRetries) return null;
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    return null;
  }
}
