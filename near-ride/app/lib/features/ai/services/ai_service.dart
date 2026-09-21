import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:near_ride/core/config/api_config.dart';

/// Backend-proxied AI client. No provider API key is stored on the device.
class AiService {
  final Map<String, String> _personalities = const {
    'default': '友善、簡潔',
    'funny': '幽默風趣',
    'professional': '專業正式',
    'casual': '輕鬆自然',
  };

  String _currentPersonality = 'default';

  Future<String> sendMessage(
    String userMessage, {
    String? context,
    String? roomId,
    bool includePersonality = true,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/ai/generate'),
            headers: ApiConfig.jsonHeaders,
            body: jsonEncode({
              'message': userMessage,
              'context': context,
              'roomId': roomId,
              'personality':
                  includePersonality ? _currentPersonality : 'default',
            }),
          )
          .timeout(ApiConfig.uploadTimeout);

      if (response.statusCode != 200) {
        debugPrint('[AI] backend error ${response.statusCode}: ${response.body}');
        return '❌ AI 服務暫時無法使用';
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['response']?.toString() ?? '抱歉，我無法回應這個問題。';
    } catch (error) {
      debugPrint('[AI] request failed: $error');
      return '❌ 抱歉，目前無法連接到 AI 服務，請稍後再試。';
    }
  }

  Future<String> summarizeConversation(List<String> messages) async {
    if (messages.isEmpty) return '暫無對話內容';
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/ai/summarize'),
            headers: ApiConfig.jsonHeaders,
            body: jsonEncode({'messages': messages}),
          )
          .timeout(ApiConfig.uploadTimeout);
      if (response.statusCode != 200) return '❌ 聊天總結服務暫時無法使用';
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['summary']?.toString() ?? '無法產生總結';
    } catch (error) {
      debugPrint('[AI] summarize failed: $error');
      return '❌ 聊天總結服務暫時無法使用';
    }
  }

  Future<String> analyzeEmotion(String message) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/ai/emotion'),
            headers: ApiConfig.jsonHeaders,
            body: jsonEncode({'message': message}),
          )
          .timeout(ApiConfig.uploadTimeout);
      if (response.statusCode != 200) return '❌ 情緒分析服務暫時無法使用';
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['emotion']?.toString() ?? '無法分析情緒';
    } catch (error) {
      debugPrint('[AI] emotion analysis failed: $error');
      return '❌ 情緒分析服務暫時無法使用';
    }
  }

  Future<List<String>> getSuggestedReplies(String lastMessage) async {
    final response = await sendMessage(
      '請為以下訊息提供 3 個簡短回覆建議，每個建議用 | 分隔：\n$lastMessage',
      includePersonality: false,
    );
    final suggestions = response
        .split('|')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && !item.startsWith('❌'))
        .take(3)
        .toList();
    return suggestions.isEmpty ? ['好的', '了解', '謝謝'] : suggestions;
  }

  void setPersonality(String personality) {
    if (_personalities.containsKey(personality)) {
      _currentPersonality = personality;
    }
  }

  List<String> getAvailablePersonalities() => _personalities.keys.toList();

  String get currentPersonality => _currentPersonality;

  String getPersonalityDescription(String personality) =>
      _personalities[personality] ?? _personalities['default']!;

  /// Compatibility with the removed client-side API-key flow.
  Future<bool> setApiKey(String apiKey) async => false;
  bool get isApiKeyConfigured => true;
  String get maskedApiKey => '由伺服器管理';
  Future<void> clearApiKey() async {}
}

/// Backwards-compatible class name used by existing chat code.
class SecureGeminiService extends AiService {}
