import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:near_ride/core/config/api_config.dart';

class RecommendedFriend {
  const RecommendedFriend({
    required this.userId,
    required this.nickname,
    required this.matchReason,
    this.avatarUrl,
    this.age,
    this.gender,
    this.hobbies = const [],
    this.commuteModes = const [],
    this.sharedCommuteModes = const [],
  });

  final String userId;
  final String nickname;
  final String matchReason;
  final String? avatarUrl;
  final int? age;
  final String? gender;
  final List<String> hobbies;
  final List<String> commuteModes;
  final List<String> sharedCommuteModes;

  factory RecommendedFriend.fromJson(Map<String, dynamic> data) {
    final rawHobbies = data['hobbies'] as List<dynamic>? ?? const [];
    return RecommendedFriend(
      userId: data['user_id'].toString(),
      nickname: data['nickname']?.toString() ?? '未知使用者',
      matchReason: data['match_reason']?.toString() ?? '近期 GPS 路線相近',
      avatarUrl: data['avatar_url']?.toString(),
      age: (data['age'] as num?)?.toInt(),
      gender: data['gender']?.toString(),
      commuteModes: (data['commute_modes'] as List<dynamic>? ?? const [])
          .whereType<String>().toList(growable: false),
      sharedCommuteModes: (data['shared_commute_modes'] as List<dynamic>? ?? const [])
          .whereType<String>().toList(growable: false),
      hobbies: rawHobbies
          .whereType<Map<String, dynamic>>()
          .map((hobby) => hobby['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList(growable: false),
    );
  }
}

class RecommendationResult {
  const RecommendationResult({this.person, this.reason});

  final RecommendedFriend? person;
  final String? reason;
}

class FriendRecommendationService {
  const FriendRecommendationService();

  Future<Map<String, dynamic>> _read(http.Response response) async {
    if (response.statusCode != 200) {
      throw Exception('推薦服務暫時無法使用（HTTP ${response.statusCode}）');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('推薦資料格式不正確');
    }
    return data;
  }

  Future<bool> isEnabled(String userId) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/friends/recommendation-settings/$userId');
    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    return (await _read(response))['enabled'] == true;
  }

  Future<void> setEnabled(String userId, bool enabled) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/friends/recommendation-settings/$userId');
    final response = await http
        .put(uri, headers: ApiConfig.jsonHeaders, body: jsonEncode({'enabled': enabled}))
        .timeout(const Duration(seconds: 20));
    await _read(response);
  }

  Future<RecommendationResult> getNext(
    String userId, {
    Set<int> excludedUserIds = const {},
  }) async {
    final url = '${ApiConfig.baseUrl}/friends/recommendation/$userId';
    final query = excludedUserIds.take(30).map((id) => 'exclude_user_ids=$id').join('&');
    final uri = Uri.parse(query.isEmpty ? url : '$url?$query');
    final response = await http.get(uri).timeout(const Duration(seconds: 45));
    final data = await _read(response);
    final raw = data['recommendation'];
    return RecommendationResult(
      person: raw is Map<String, dynamic> ? RecommendedFriend.fromJson(raw) : null,
      reason: data['reason']?.toString(),
    );
  }
}
