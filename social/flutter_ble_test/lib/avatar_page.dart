import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AvatarPage extends StatefulWidget {
  const AvatarPage({super.key});

  @override
  State<AvatarPage> createState() => _AvatarPageState();
}

class _AvatarPageState extends State<AvatarPage> {
  final TextEditingController _descController = TextEditingController();
  String? _imageUrl;
  String? _base64Image;
  bool _loading = false;
  String? _apiKey;
  bool _apiKeyLoaded = false;

  Future<void> _generateAvatar() async {
    if (_descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先輸入描述！')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _base64Image = null;
    });
    if (!_apiKeyLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API 金鑰讀取中，請稍候...')),
      );
      return;
    }
    if (_apiKey == null || _apiKey!.isEmpty || _apiKey == '請填入你的API金鑰') {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先在 assets/secret.json 填入正確的 GEMINI_API_KEY')),
      );
      return;
    }
    final apiKey = _apiKey;
    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-preview-image-generation:generateContent?key=$apiKey');
    final prompt = _descController.text.trim();
    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": prompt}
          ]
        }
      ],
      "generationConfig": {
        "responseModalities": ["TEXT", "IMAGE"]
      }
    });
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: body,
      );
      debugPrint('Gemini API request body: ' + body);
      debugPrint('Gemini API response: ' + response.body);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final parts = data["candidates"][0]["content"]["parts"];
        String? base64Image;
        for (final part in parts) {
          if (part["inlineData"] != null) {
            base64Image = part["inlineData"]["data"];
            break;
          }
        }
        setState(() {
          _base64Image = base64Image;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('API 錯誤: ${response.statusCode}\n${response.body}')),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('發生錯誤: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/secret.json');
      final jsonData = jsonDecode(jsonStr);
      setState(() {
        _apiKey = jsonData['GEMINI_API_KEY'];
        _apiKeyLoaded = true;
      });
    } catch (e) {
      setState(() {
        _apiKeyLoaded = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法讀取 API 金鑰，請檢查 assets/secret.json')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('漫畫頭像生成')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: '描述（如：戴眼鏡的男孩）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _generateAvatar,
              child: _loading ? const CircularProgressIndicator() : const Text('生成漫畫頭像'),
            ),
            const SizedBox(height: 24),
            if (_base64Image != null)
              Column(
                children: [
                  const Text('Gemini 生成圖片結果：'),
                  const SizedBox(height: 8),
                  Image.memory(base64Decode(_base64Image!), height: 180),
                ],
              )
            else if (_imageUrl != null)
              Column(
                children: [
                  const Text('DiceBear 生成結果：'),
                  const SizedBox(height: 8),
                  Image.network(_imageUrl!, height: 180),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
