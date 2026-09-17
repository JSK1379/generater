import 'package:flutter/material.dart';

import 'api_config.dart';

/// Compatibility page retained for Settings navigation.
///
/// Gemini credentials are no longer entered or stored on the mobile device.
/// They are configured only on the backend through GEMINI_API_KEY.
class GeminiApiKeySetupPage extends StatelessWidget {
  const GeminiApiKeySetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 助手設定')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.lock_outline, size: 72),
          const SizedBox(height: 24),
          Text(
            'API Key 已改由伺服器管理',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const Text(
            'Near Ride 不再把 Gemini API Key 儲存在手機、SharedPreferences 或 assets 中。'
            'AI 請求會送到 Near Ride 後端，再由伺服器安全地呼叫 Gemini。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '目前 AI 後端',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(ApiConfig.baseUrl),
                  const SizedBox(height: 16),
                  const Text(
                    '部署時請在伺服器環境變數設定 GEMINI_API_KEY。手機端不需要輸入任何金鑰。',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
