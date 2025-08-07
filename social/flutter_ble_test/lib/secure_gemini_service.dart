import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

/// Gemini AI 服務類（安全版本）
/// 提供與 Google Gemini 2.5 Flash 的整合功能
/// API Key 從 SharedPreferences 讀取，更安全
class SecureGeminiService {
  GenerativeModel? _model;
  bool _isInitialized = false;
  String? _apiKey;
  
  // AI 角色設定
  final Map<String, String> _aiPersonalities = {
    'default': '你是一個友善、樂於助人的AI助手。請用繁體中文回應，保持簡潔而有用。',
    'funny': '你是一個幽默風趣的AI助手，喜歡開玩笑但仍然有用。請用繁體中文回應。',
    'professional': '你是一個專業、正式的AI助手，提供準確和詳細的信息。請用繁體中文回應。',
    'casual': '你是一個輕鬆、隨意的AI助手，就像朋友一樣聊天。請用繁體中文回應。',
  };
  
  String _currentPersonality = 'default';
  
  SecureGeminiService() {
    _initializeModel();
  }
  
  Future<void> _initializeModel() async {
    try {
      // 首先嘗試從 SharedPreferences 讀取 API Key
      final prefs = await SharedPreferences.getInstance();
      _apiKey = prefs.getString('gemini_api_key');
      
      // 如果 SharedPreferences 中沒有，嘗試從 assets/secret.json 讀取
      if (_apiKey == null || _apiKey!.isEmpty) {
        try {
          final jsonStr = await rootBundle.loadString('assets/secret.json');
          final jsonData = jsonDecode(jsonStr);
          _apiKey = jsonData['GEMINI_API_KEY'];
          
          // 如果從 secret.json 成功讀取，也儲存到 SharedPreferences
          if (_apiKey != null && _apiKey!.isNotEmpty && _apiKey != '請填入你的API金鑰') {
            await prefs.setString('gemini_api_key', _apiKey!);
            debugPrint('✅ [SecureGeminiService] 從 assets/secret.json 讀取並儲存 API Key');
          }
        } catch (e) {
          debugPrint('⚠️ [SecureGeminiService] 無法從 assets/secret.json 讀取 API Key: $e');
        }
      }
      
      if (_apiKey == null || _apiKey!.isEmpty || _apiKey == '請填入你的API金鑰') {
        debugPrint('⚠️ [SecureGeminiService] 請設定 Gemini API Key');
        _isInitialized = false;
        return;
      }
      
      _model = GenerativeModel(
        model: 'gemini-2.0-flash-exp',
        apiKey: _apiKey!,
        generationConfig: GenerationConfig(
          temperature: 0.7,
          topK: 40,
          topP: 0.95,
          maxOutputTokens: 1024,
        ),
        safetySettings: [
          SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium),
          SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium),
          SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.medium),
          SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.medium),
        ],
      );
      
      _isInitialized = true;
      debugPrint('✅ [SecureGeminiService] Gemini AI 服務已初始化');
    } catch (e) {
      debugPrint('❌ [SecureGeminiService] 初始化失敗: $e');
      _isInitialized = false;
    }
  }
  
  /// 設定 API Key
  Future<bool> setApiKey(String apiKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gemini_api_key', apiKey);
      _apiKey = apiKey;
      await _initializeModel();
      return _isInitialized;
    } catch (e) {
      debugPrint('❌ [SecureGeminiService] 設定 API Key 失敗: $e');
      return false;
    }
  }
  
  /// 發送訊息給 Gemini AI
  Future<String> sendMessage(
    String userMessage, {
    String? context,
    String? roomId,
    bool includePersonality = true,
  }) async {
    try {
      if (!_isInitialized || _model == null) {
        return '❌ 請先設定 Gemini API Key 才能使用 AI 功能';
      }
      
      // 構建完整的提示詞
      String fullPrompt = '';
      
      // 添加 AI 個性
      if (includePersonality) {
        fullPrompt += '${_aiPersonalities[_currentPersonality]}\n\n';
      }
      
      // 添加上下文（聊天歷史）
      if (context != null && context.isNotEmpty) {
        fullPrompt += '聊天室上下文:\n$context\n\n';
      }
      
      // 添加用戶訊息
      fullPrompt += '用戶訊息: $userMessage';
      
      debugPrint('🤖 [SecureGeminiService] 發送訊息給 Gemini: ${userMessage.substring(0, userMessage.length > 50 ? 50 : userMessage.length)}...');
      
      final content = Content.text(fullPrompt);
      final response = await _model!.generateContent([content]);
      
      final aiResponse = response.text ?? '抱歉，我無法回應這個問題。';
      debugPrint('✅ [SecureGeminiService] 收到 Gemini 回應: ${aiResponse.substring(0, aiResponse.length > 50 ? 50 : aiResponse.length)}...');
      
      return aiResponse;
      
    } catch (e) {
      debugPrint('❌ [SecureGeminiService] Gemini API 錯誤: $e');
      
      // 根據錯誤類型返回不同訊息
      if (e.toString().contains('API_KEY')) {
        return '❌ API Key 無效，請檢查設定。';
      } else if (e.toString().contains('QUOTA')) {
        return '❌ API 配額已用完，請稍後再試。';
      } else if (e.toString().contains('SAFETY')) {
        return '⚠️ 抱歉，您的訊息包含不當內容，無法回應。';
      } else {
        return '❌ 抱歉，目前無法連接到 AI 服務，請稍後再試。';
      }
    }
  }
  
  /// 設定 AI 個性
  void setPersonality(String personality) {
    if (_aiPersonalities.containsKey(personality)) {
      _currentPersonality = personality;
      debugPrint('🎭 [SecureGeminiService] AI 個性已切換至: $personality');
    }
  }
  
  /// 獲取可用的 AI 個性列表
  List<String> getAvailablePersonalities() {
    return _aiPersonalities.keys.toList();
  }
  
  /// 生成聊天總結
  Future<String> summarizeConversation(List<String> messages) async {
    if (messages.isEmpty) return '暫無對話內容';
    
    final conversationText = messages.join('\n');
    const summaryPrompt = '請為以下對話生成一個簡潔的總結，用繁體中文回應：\n\n';
    
    return await sendMessage(
      summaryPrompt + conversationText,
      includePersonality: false,
    );
  }
  
  /// 情緒分析
  Future<String> analyzeEmotion(String message) async {
    const emotionPrompt = '請分析以下訊息的情緒（正面/負面/中性），並用一個 emoji 和簡短說明回應：\n\n';
    
    return await sendMessage(
      emotionPrompt + message,
      includePersonality: false,
    );
  }
  
  /// 智能回覆建議
  Future<List<String>> getSuggestedReplies(String lastMessage) async {
    const suggestionPrompt = '為以下訊息提供3個簡短的回覆建議，每個建議用|分隔：\n\n';
    
    try {
      final response = await sendMessage(
        suggestionPrompt + lastMessage,
        includePersonality: false,
      );
      
      // 解析回覆建議
      final suggestions = response.split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(3)
          .toList();
      
      return suggestions.isNotEmpty ? suggestions : ['好的', '了解', '謝謝'];
    } catch (e) {
      debugPrint('❌ [SecureGeminiService] 獲取回覆建議失敗: $e');
      return ['好的', '了解', '謝謝'];
    }
  }
  
  /// 檢查 API Key 是否已設定
  bool get isApiKeyConfigured => _isInitialized && _apiKey != null && _apiKey!.isNotEmpty;
  
  /// 獲取當前 API Key（僅顯示前幾個字符）
  String get maskedApiKey {
    if (_apiKey == null || _apiKey!.isEmpty) return '未設定';
    return '${_apiKey!.substring(0, 8)}...${_apiKey!.substring(_apiKey!.length - 4)}';
  }
  
  /// 獲取當前 AI 個性
  String get currentPersonality => _currentPersonality;
  
  /// 獲取 AI 個性描述
  String getPersonalityDescription(String personality) {
    return _aiPersonalities[personality] ?? _aiPersonalities['default']!;
  }
  
  /// 清除 API Key
  Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('gemini_api_key');
    _apiKey = null;
    _isInitialized = false;
    _model = null;
  }
}
