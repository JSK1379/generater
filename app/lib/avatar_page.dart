import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AvatarPage extends StatefulWidget {
  const AvatarPage({
    super.key,
    required this.setAvatarThumbnailBytes,
    required this.avatarThumbnailBytes,
  });

  final void Function(Uint8List?) setAvatarThumbnailBytes;
  final Uint8List? avatarThumbnailBytes;

  // 新增：全域靜態頭像變數
  static ImageProvider? currentAvatarImage;

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
  String _selectedGender = '';
  String _selectedHair = '';
  String _selectedStyle = '';
  String _selectedBody = '';

  // 中文轉英文的輔助函數
  String _translateToEnglish(String category, String value) {
    switch (category) {
      case 'gender':
        switch (value) {
          case '男': return 'male';
          case '女': return 'female';
          default: return value;
        }
      case 'hair':
        switch (value) {
          case '長髮': return 'long hair';
          case '短髮': return 'short hair';
          default: return value;
        }
      case 'style':
        switch (value) {
          case '日系': return 'Japanese anime style';
          case '美式': return 'American comic style';
          case 'Q版': return 'chibi style';
          default: return value;
        }
      case 'body':
        switch (value) {
          case '全身': return 'full body';
          default: return value;
        }
      default:
        return value;
    }
  }

  // 新增：套用頭像
  void _applyAvatar() async {
    // 新增：彈窗確認
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認更改頭像'),
        content: const Text('確定要將目前頭像設為個人頭像並上傳嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('確定')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_base64Image != null) {
      AvatarPage.currentAvatarImage = MemoryImage(base64Decode(_base64Image!));
      widget.setAvatarThumbnailBytes(base64Decode(_base64Image!));
      // 注意：頭像現在在用戶資料編輯頁面統一上傳，不再單獨上傳
      final prefs = await SharedPreferences.getInstance();
      // 僅保存本地狀態，實際上傳在用戶資料編輯頁面進行
      await prefs.setString('temp_avatar_base64', _base64Image!);
    } else if (_imageUrl != null) {
      AvatarPage.currentAvatarImage = NetworkImage(_imageUrl!);
      // 若有需要可考慮下載圖片轉 Uint8List 再 callback
    }
    setState(() {});
    // 通知外部頁面刷新（可用 Provider/InheritWidget 改進）
    
    // 頭像套用完成後跳回用戶資料編輯頁面
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _generateAvatar() async {
    if (_descController.text.trim().isEmpty &&
        _selectedGender.isEmpty &&
        _selectedHair.isEmpty &&
        _selectedStyle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先輸入描述或選擇標籤！')),
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
    
    // 構建英文 prompt，將中文選項轉換為英文
    final englishGender = _selectedGender.isNotEmpty ? _translateToEnglish('gender', _selectedGender) : '';
    final englishHair = _selectedHair.isNotEmpty ? _translateToEnglish('hair', _selectedHair) : '';
    final englishStyle = _selectedStyle.isNotEmpty ? _translateToEnglish('style', _selectedStyle) : '';
    final isFullBody = _selectedBody == '全身';
    
    final prompt = isFullBody
        ? 'Generate a ${englishGender.isNotEmpty ? '$englishGender ' : ''}person full body portrait from hair to knees. ${_descController.text.trim()}. '
            '${englishHair.isNotEmpty ? 'Hair: $englishHair. ' : ''}'
            '${englishStyle.isNotEmpty ? 'Art style: $englishStyle. ' : ''}'
            'High quality, detailed image.'
        : 'Generate a ${englishGender.isNotEmpty ? '$englishGender ' : ''}person avatar portrait. ${_descController.text.trim()}. '
            '${englishHair.isNotEmpty ? 'Hair: $englishHair. ' : ''}'
            '${englishStyle.isNotEmpty ? 'Art style: $englishStyle. ' : ''}'
            'High quality, detailed headshot.';
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
      if (!mounted) return;
      debugPrint('Gemini API request body: $body');
      debugPrint('Gemini API response: ${response.body}');
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
        if (!mounted) return;
        setState(() {
          _base64Image = base64Image;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('API 錯誤: ${response.statusCode}\n${response.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法讀取 API 金鑰，請檢查 assets/secret.json')),
      );
    }
  }

  void _setGender(String gender) {
    setState(() {
      _selectedGender = gender;
      // 不再自動更新描述內容
    });
  }

  void _setHair(String hair) {
    setState(() {
      _selectedHair = hair;
      // 不再自動更新描述內容
    });
  }

  void _setStyle(String style) {
    setState(() {
      _selectedStyle = style;
    });
  }

  void _setBody(String body) {
    setState(() {
      _selectedBody = body;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Avatar')),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 輔助輸入按鈕區塊
                  Row(
                    children: [
                      const Text('性別：'),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('男'),
                        selected: _selectedGender == '男',
                        onSelected: (selected) => _setGender(selected ? '男' : ''),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('女'),
                        selected: _selectedGender == '女',
                        onSelected: (selected) => _setGender(selected ? '女' : ''),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('髮型：'),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('長髮'),
                        selected: _selectedHair == '長髮',
                        onSelected: (selected) => _setHair(selected ? '長髮' : ''),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('短髮'),
                        selected: _selectedHair == '短髮',
                        onSelected: (selected) => _setHair(selected ? '短髮' : ''),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 畫風選擇按鈕區塊
                  Row(
                    children: [
                      const Text('畫風：'),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('日系'),
                        selected: _selectedStyle == '日系',
                        onSelected: (selected) => _setStyle(selected ? '日系' : ''),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('美式'),
                        selected: _selectedStyle == '美式',
                        onSelected: (selected) => _setStyle(selected ? '美式' : ''),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Q版'),
                        selected: _selectedStyle == 'Q版',
                        onSelected: (selected) => _setStyle(selected ? 'Q版' : ''),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('範圍：'),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('頭像'),
                        selected: _selectedBody == '半身',
                        onSelected: (selected) => _setBody(selected ? '半身' : ''),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('全身'),
                        selected: _selectedBody == '全身',
                        onSelected: (selected) => _setBody(selected ? '全身' : ''),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: '描述（如：戴眼鏡的男孩）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 只在未生成圖片時顯示生成按鈕
                  if (_base64Image == null && _imageUrl == null)
                    ElevatedButton(
                      onPressed: _loading
                          ? null
                          : () {
                              FocusScope.of(context).unfocus(); // 按下時關閉鍵盤
                              _generateAvatar();
                            },
                      child: _loading
                          ? const CircularProgressIndicator()
                          : const Text('生成頭像'),
                    ),
                  const SizedBox(height: 24),
                  if (_base64Image != null)
                    Column(
                      children: [
                        const Text('Gemini 生成圖片結果：'),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            if (_base64Image != null) {
                              showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  child: InteractiveViewer(
                                    child: ClipOval(
                                      child: Image.memory(
                                        base64Decode(_base64Image!),
                                        width: 360,
                                        height: 360,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                          child: ClipOval(
                            child: SizedBox(
                              width: 180,
                              height: 180,
                              child: Image.memory(
                                base64Decode(_base64Image!),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: _applyAvatar,
                              child: const Text('套用頭像'),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: _loading
                                  ? null
                                  : () {
                                      FocusScope.of(context).unfocus();
                                      _generateAvatar();
                                    },
                              child: _loading
                                  ? const CircularProgressIndicator()
                                  : const Text('重新生成'),
                            ),
                          ],
                        ),
                      ],
                    )
                  else if (_imageUrl != null)
                    Column(
                      children: [
                        const Text('DiceBear 生成結果：'),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () {
                            if (_imageUrl != null) {
                              showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  child: InteractiveViewer(
                                    child: ClipOval(
                                      child: Image.network(
                                        _imageUrl!,
                                        width: 360,
                                        height: 360,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                          child: ClipOval(
                            child: SizedBox(
                              width: 180,
                              height: 180,
                              child: Image.network(
                                _imageUrl!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: _applyAvatar,
                              child: const Text('套用頭像'),
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton(
                              onPressed: _loading
                                  ? null
                                  : () {
                                      FocusScope.of(context).unfocus();
                                      _generateAvatar();
                                    },
                              child: _loading
                                  ? const CircularProgressIndicator()
                                  : const Text('重新生成'),
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      resizeToAvoidBottomInset: true,
    );
  }
}
