import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserLoginPage extends StatefulWidget {
  const UserLoginPage({super.key});

  @override
  State<UserLoginPage> createState() => _UserLoginPageState();
}

class _UserLoginPageState extends State<UserLoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // 立即清除焦點，防止自動彈出鍵盤
    Future.microtask(() {
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
    });
  }

  Future<void> _loginWithEmail() async {
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
      // TODO: 實作登入 API 調用
      // 目前先模擬登入成功，實際需要添加到 UserApiService
      
      // 模擬網路延遲
      await Future.delayed(const Duration(seconds: 2));
      
      // 暫時使用郵件作為用戶 ID（實際應該從服務器獲取）
      final userId = email.split('@')[0]; // 簡單提取用戶名作為 ID
      
      // 保存用戶 ID 到本地存儲
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userId);
      await prefs.setString('email', email);
      
      // 登入成功，聊天服務會在需要時自動連接
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登入成功！'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // 返回 true 表示登入成功
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登入失敗: $e')),
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
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('用戶登入'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 
                         MediaQuery.of(context).padding.top - 
                         kToolbarHeight - 48,
            ),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 標題
                  const Text(
                    '歡迎回來',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '請輸入您的郵件地址和密碼登入',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  
                  // 郵件輸入框
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofocus: false,
                    decoration: const InputDecoration(
                      labelText: '郵件地址',
                      hintText: '請輸入您的郵件地址',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 密碼輸入框
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofocus: false,
                    decoration: InputDecoration(
                      labelText: '密碼',
                      hintText: '請輸入您的密碼',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // 登入按鈕
                  ElevatedButton(
                    onPressed: _isLoading ? null : _loginWithEmail,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            '登入',
                            style: TextStyle(fontSize: 18),
                          ),
                  ),
                  const SizedBox(height: 24),
                  
                  // 註冊提示
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('還沒有帳號？'),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // 返回註冊頁面
                        },
                        child: const Text(
                          '立即註冊',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
