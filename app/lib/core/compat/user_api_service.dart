import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:near_ride/features/ai/services/ai_service.dart';
import 'package:near_ride/features/auth/services/auth_service.dart';
import 'package:near_ride/features/friends/services/friend_service.dart';
import 'package:near_ride/features/profile/services/profile_service.dart';

/// Compatibility facade for legacy callers.
///
/// New code should depend directly on AuthService, ProfileService,
/// FriendService or AiService instead of adding more methods here.
class UserApiService {
  UserApiService(this.baseUrl)
      : _auth = AuthService(baseUrl),
        _profile = ProfileService(baseUrl),
        _friends = FriendService(baseUrl),
        _ai = AiService();

  final String baseUrl;
  final AuthService _auth;
  final ProfileService _profile;
  final FriendService _friends;
  final AiService _ai;

  Future<String?> registerUserWithEmail(String email, String password) =>
      _auth.register(email, password);

  Future<String?> loginUser(String email, String password) =>
      _auth.login(email, password);

  Future<Map<String, dynamic>?> getUserProfile(String userId) =>
      _profile.getUserProfile(userId);

  Future<String?> uploadAvatar(String userId, String base64Image) =>
      _profile.uploadAvatar(userId, base64Image);

  Future<String?> addFriend(String userId, String friendId) =>
      _friends.addFriend(userId, friendId);

  Future<List<Map<String, dynamic>>?> getFriends(String userId) =>
      _friends.getFriends(userId);

  Future<List<Map<String, dynamic>>?> getChatHistory(
    String roomId, {
    int limit = 50,
  }) =>
      _friends.getChatHistory(roomId, limit: limit);

  Future<String?> generateAIResponse({
    required String message,
    String? context,
    String? personality = 'default',
    String? roomId,
  }) async {
    if (personality != null) {
      _ai.setPersonality(personality);
    }
    return _ai.sendMessage(
      message,
      context: context,
      roomId: roomId,
    );
  }

  Future<String?> generateChatSummary(List<String> messages) async =>
      _ai.summarizeConversation(messages);

  Future<String?> analyzeEmotion(String message) async =>
      _ai.analyzeEmotion(message);

  /// Legacy registration endpoint retained because older test utilities may
  /// still call it with an exact URL.
  Future<bool> registerUser(String userId) async {
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId}),
      );
      return response.statusCode == 200;
    } catch (error) {
      debugPrint('[UserApiService] legacy register error: $error');
      return false;
    }
  }

  Future<void> uploadUserId(String userId) async {
    debugPrint('[UserApiService] legacy uploadUserId: $userId');
  }

  void dispose() {}
}
