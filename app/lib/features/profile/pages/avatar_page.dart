import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:near_ride/core/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI avatar generator backed by the Near Ride server.
///
/// No Gemini/provider credential is stored or read on the device.
class AvatarPage extends StatefulWidget {
  const AvatarPage({
    super.key,
    required this.setAvatarThumbnailBytes,
    required this.avatarThumbnailBytes,
  });

  final void Function(Uint8List?) setAvatarThumbnailBytes;
  final Uint8List? avatarThumbnailBytes;

  static ImageProvider? currentAvatarImage;

  @override
  State<AvatarPage> createState() => _AvatarPageState();
}

class _AvatarPageState extends State<AvatarPage> {
  final TextEditingController _descriptionController = TextEditingController();

  String _gender = '';
  String _hair = '';
  String _style = '';
  String _body = 'portrait';
  Uint8List? _generatedBytes;
  bool _loading = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_descriptionController.text.trim().isEmpty &&
        _gender.isEmpty &&
        _hair.isEmpty &&
        _style.isEmpty) {
      _message('請輸入描述或選擇至少一個條件');
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/ai/avatar'),
            headers: ApiConfig.jsonHeaders,
            body: jsonEncode({
              'description': _descriptionController.text.trim(),
              'gender': _gender,
              'hair': _hair,
              'style': _style,
              'body': _body,
            }),
          )
          .timeout(const Duration(seconds: 70));

      if (!mounted) return;
      if (response.statusCode != 200) {
        _message('頭像生成失敗 (${response.statusCode})');
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final encoded = data['image_base64']?.toString();
      if (encoded == null || encoded.isEmpty) {
        _message('伺服器沒有回傳圖片');
        return;
      }
      setState(() => _generatedBytes = base64Decode(encoded));
    } catch (error) {
      if (mounted) _message('頭像生成失敗：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final bytes = _generatedBytes;
    if (bytes == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('套用頭像'),
        content: const Text('確定使用目前生成的圖片作為頭像嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('套用'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final encoded = base64Encode(bytes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('temp_avatar_base64', encoded);
    AvatarPage.currentAvatarImage = MemoryImage(bytes);
    widget.setAvatarThumbnailBytes(bytes);
    if (mounted) Navigator.pop(context, true);
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _choices(
    String title,
    List<String> values,
    String selected,
    ValueChanged<String> onSelected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values
              .map(
                (value) => ChoiceChip(
                  label: Text(value),
                  selected: selected == value,
                  onSelected: (_) => onSelected(value),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _generatedBytes ?? widget.avatarThumbnailBytes;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 頭像')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(
              radius: 72,
              backgroundImage: preview == null ? null : MemoryImage(preview),
              child: preview == null
                  ? const Icon(Icons.person_outline, size: 72)
                  : null,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '描述',
              hintText: '例如：戴眼鏡、短髮、簡潔背景',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          _choices('性別', ['male', 'female'], _gender,
              (value) => setState(() => _gender = value)),
          const SizedBox(height: 16),
          _choices('髮型', ['short hair', 'long hair'], _hair,
              (value) => setState(() => _hair = value)),
          const SizedBox(height: 16),
          _choices(
            '風格',
            ['Japanese anime', 'American comic', 'chibi'],
            _style,
            (value) => setState(() => _style = value),
          ),
          const SizedBox(height: 16),
          _choices('構圖', ['portrait', 'full body'], _body,
              (value) => setState(() => _body = value)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _loading ? null : _generate,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_loading ? '生成中...' : '生成頭像'),
          ),
          if (_generatedBytes != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _apply,
              icon: const Icon(Icons.check),
              label: const Text('套用這張頭像'),
            ),
          ],
        ],
      ),
    );
  }
}
