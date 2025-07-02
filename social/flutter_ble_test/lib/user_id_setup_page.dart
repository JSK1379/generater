import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'user_api_service.dart';

class UserIdSetupPage extends StatefulWidget {
  const UserIdSetupPage({super.key});

  @override
  State<UserIdSetupPage> createState() => _UserIdSetupPageState();
}

class _UserIdSetupPageState extends State<UserIdSetupPage> {
  final TextEditingController _userIdController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrGenerateUserId();
  }

  Future<void> _loadOrGenerateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    String? existingUserId = prefs.getString('user_id');
    
    if (existingUserId == null || existingUserId.isEmpty) {
      // 生成新的 user ID
      existingUserId = _generateUserId();
      await prefs.setString('user_id', existingUserId);
    }
    
    setState(() {
      _userIdController.text = existingUserId!;
      _isLoading = false;
    });
  }

  String _generateUserId() {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomNum = random.nextInt(9999);
    return 'user_${timestamp}_$randomNum';
  }

  Future<void> _saveUserId() async {
    final userId = _userIdController.text.trim();
    if (userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入有效的 User ID')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', userId);

    // 上傳 userId 給 server
    const wsUrl = 'wss://near-ride-backend-api.onrender.com/ws';
    final userApi = UserApiService(wsUrl);
    await userApi.uploadUserId(userId);
    userApi.dispose();

    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/main');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定用戶 ID'),
        automaticallyImplyLeading: false,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.person,
                    size: 80,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '歡迎使用 BLE 聊天應用',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '請設定您的用戶 ID，這將用於聊天室識別',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _userIdController,
                    decoration: const InputDecoration(
                      labelText: 'User ID',
                      border: OutlineInputBorder(),
                      hintText: '輸入您的用戶 ID',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '建議使用易記的名稱，如：張三、Mary 等',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveUserId,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        '開始使用',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () async {
                      final newId = _generateUserId();
                      setState(() {
                        _userIdController.text = newId;
                      });
                    },
                    child: const Text('重新生成隨機 ID'),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }
}
