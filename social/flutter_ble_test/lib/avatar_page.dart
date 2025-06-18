import 'package:flutter/material.dart';

class AvatarPage extends StatefulWidget {
  const AvatarPage({super.key});

  @override
  State<AvatarPage> createState() => _AvatarPageState();
}

class _AvatarPageState extends State<AvatarPage> {
  final TextEditingController _descController = TextEditingController();
  String? _imageUrl;
  bool _loading = false;

  void _generateAvatar() async {
    if (_descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先輸入描述！')),
      );
      return;
    }
    setState(() => _loading = true);
    // 這裡應該呼叫 AI 服務或本地生成邏輯，這裡僅用範例圖片
    await Future.delayed(const Duration(seconds: 2));
    setState(() {
      _imageUrl = 'https://api.dicebear.com/7.x/comic/svg?seed=' + Uri.encodeComponent(_descController.text);
      _loading = false;
    });
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
            if (_imageUrl != null)
              Column(
                children: [
                  const Text('生成結果：'),
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
