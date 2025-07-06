import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_service_singleton.dart';
import 'user_api_service.dart';

class UserIdSetupPage extends StatefulWidget {
  const UserIdSetupPage({super.key});

  @override
  State<UserIdSetupPage> createState() => _UserIdSetupPageState();
}

class _UserIdSetupPageState extends State<UserIdSetupPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _registerWithEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入郵件地址和密碼')),
      );
      return;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入有效的郵件地址')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 通過 HTTP 註冊並獲取用戶 ID
      const baseUrl = 'https://near-ride-backend-api.onrender.com/';
      final userApiService = UserApiService(baseUrl);
      final userId = await userApiService.registerUserWithEmail(email, password);
      
      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('註冊失敗，請檢查郵件地址和密碼')),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 保存獲得的用戶 ID
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userId);
      await prefs.setString('user_email', email);
      
      debugPrint('[UserIdSetup] HTTP 註冊成功，獲得 userId: $userId');

      // 通過 WebSocket 註冊用戶
      try {
        final chatService = ChatServiceSingleton.instance;
        const wsUrl = 'wss://near-ride-backend-api.onrender.com/ws';
        await chatService.connect(wsUrl, '', userId);
        chatService.webSocketService.sendMessage({
          'type': 'register_user',
          'userId': userId,
        });
        debugPrint('[UserIdSetup] WebSocket 用戶註冊成功: $userId');
      } catch (e) {
        debugPrint('[UserIdSetup] WebSocket 用戶註冊失敗: $e');
        // WebSocket 註冊失敗不阻止進入主頁面
      }

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/main');
      }
    } catch (e) {
      debugPrint('[UserIdSetup] 註冊錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('網路錯誤，請檢查網路連線')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('用戶註冊'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.person_add,
              size: 80,
              color: Colors.blue,
            ),
            const SizedBox(height: 32),
            const Text(
              '歡迎！請註冊您的帳號',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '郵件地址',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '密碼',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _registerWithEmail,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('註冊', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
