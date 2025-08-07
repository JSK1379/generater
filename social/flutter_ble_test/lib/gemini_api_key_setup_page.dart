import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'secure_gemini_service.dart';
import 'dart:convert';

class GeminiApiKeySetupPage extends StatefulWidget {
  const GeminiApiKeySetupPage({super.key});

  @override
  State<GeminiApiKeySetupPage> createState() => _GeminiApiKeySetupPageState();
}

class _GeminiApiKeySetupPageState extends State<GeminiApiKeySetupPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  final SecureGeminiService _geminiService = SecureGeminiService();
  bool _isLoading = false;
  bool _isObscured = true;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _checkCurrentApiKey();
  }

  Future<void> _checkCurrentApiKey() async {
    // 檢查從 secret.json 或 SharedPreferences 的 API Key 狀態
    try {
      final jsonStr = await rootBundle.loadString('assets/secret.json');
      final jsonData = jsonDecode(jsonStr);
      final secretApiKey = jsonData['GEMINI_API_KEY'];
      
      if (secretApiKey != null && secretApiKey.isNotEmpty && secretApiKey != '請填入你的API金鑰') {
        setState(() {
          _status = '✅ 檢測到 assets/secret.json 中的 API Key\n'
                   '當前 API Key: ${_geminiService.maskedApiKey}\n'
                   '可以直接開始使用 AI 功能！';
        });
      } else {
        setState(() {
          _status = '⚠️ assets/secret.json 中的 API Key 無效\n'
                   '當前 API Key: ${_geminiService.maskedApiKey}';
        });
      }
    } catch (e) {
      setState(() {
        _status = '⚠️ 無法讀取 assets/secret.json\n'
                 '當前 API Key: ${_geminiService.maskedApiKey}';
      });
    }
  }

  Future<void> _setApiKey() async {
    if (_apiKeyController.text.trim().isEmpty) {
      setState(() {
        _status = '❌ 請輸入 API Key';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _status = '⏳ 驗證 API Key...';
    });

    final success = await _geminiService.setApiKey(_apiKeyController.text.trim());
    
    if (success) {
      setState(() {
        _isLoading = false;
        _status = '✅ API Key 設定成功！';
      });
      
      // 測試 API
      _testApi();
    } else {
      setState(() {
        _isLoading = false;
        _status = '❌ API Key 設定失敗，請檢查是否正確';
      });
    }
  }

  Future<void> _testApi() async {
    setState(() {
      _status = '🧪 測試 API 連接...';
    });

    try {
      final response = await _geminiService.sendMessage('你好，請用繁體中文回應我');
      setState(() {
        _status = '✅ API 測試成功！\n回應: ${response.length > 50 ? '${response.substring(0, 50)}...' : response}';
      });
    } catch (e) {
      setState(() {
        _status = '❌ API 測試失敗: $e';
      });
    }
  }

  Future<void> _clearApiKey() async {
    await _geminiService.clearApiKey();
    setState(() {
      _apiKeyController.clear();
      _status = '🗑️ API Key 已清除';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemini API Key 設定'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 說明卡片
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'API Key 設定方式',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '🎉 檢測到你已在 assets/secret.json 中設定 API Key！\n'
                      '系統會自動使用該 API Key，無需重複設定。\n\n'
                      '如需更換 API Key，可以：\n'
                      '1. 直接修改 assets/secret.json 中的 GEMINI_API_KEY\n'
                      '2. 或在下方輸入新的 API Key 覆蓋\n\n'
                      '獲取新 API Key 的方式：\n'
                      '• 前往 Google AI Studio (makersuite.google.com)\n'
                      '• 登入你的 Google 帳戶\n'
                      '• 點擊 "Create API Key"\n'
                      '• 複製生成的 API Key',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        // 在異步操作之前先獲取 ScaffoldMessenger
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        await Clipboard.setData(
                          const ClipboardData(text: 'https://makersuite.google.com/app/apikey')
                        );
                        if (mounted) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(content: Text('網址已複製到剪貼簿')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('複製 Google AI Studio 網址'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade100,
                        foregroundColor: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // API Key 輸入
            Text(
              'Gemini API Key',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKeyController,
              obscureText: _isObscured,
              decoration: InputDecoration(
                hintText: '輸入你的 Gemini API Key',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _isObscured = !_isObscured;
                        });
                      },
                      icon: Icon(_isObscured ? Icons.visibility : Icons.visibility_off),
                    ),
                    IconButton(
                      onPressed: () async {
                        final clipboardData = await Clipboard.getData('text/plain');
                        if (clipboardData?.text != null) {
                          _apiKeyController.text = clipboardData!.text!;
                        }
                      },
                      icon: const Icon(Icons.paste),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 按鈕區域
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _setApiKey,
                    icon: _isLoading 
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                    label: Text(_isLoading ? '設定中...' : '設定 API Key'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _clearApiKey,
                  icon: const Icon(Icons.delete),
                  label: const Text('清除'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade100,
                    foregroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // 狀態顯示
            if (_status.isNotEmpty)
              Card(
                color: _status.startsWith('✅') 
                    ? Colors.green.shade50 
                    : _status.startsWith('❌') 
                        ? Colors.red.shade50 
                        : Colors.grey.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(
                        _status.startsWith('✅') 
                            ? Icons.check_circle 
                            : _status.startsWith('❌') 
                                ? Icons.error 
                                : Icons.info,
                        color: _status.startsWith('✅') 
                            ? Colors.green.shade700 
                            : _status.startsWith('❌') 
                                ? Colors.red.shade700 
                                : Colors.grey.shade700,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _status,
                          style: TextStyle(
                            color: _status.startsWith('✅') 
                                ? Colors.green.shade700 
                                : _status.startsWith('❌') 
                                    ? Colors.red.shade700 
                                    : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            const Spacer(),
            
            // 安全提醒
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.security, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🔒 你的 API Key 會安全地儲存在本地裝置中，不會傳送到任何第三方伺服器',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }
}
