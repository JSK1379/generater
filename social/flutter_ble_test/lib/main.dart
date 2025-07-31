import 'package:flutter/material.dart';
import 'main_tab_page.dart';
import 'user_id_setup_page_new.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_service_singleton.dart';
import 'api_config.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const AppInitializer(),
      routes: {
        '/main': (context) => const MainTabPage(),
        '/setup_new': (context) => const UserIdSetupPage(),
      },
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  @override
  void initState() {
    super.initState();
    _checkUserId();
  }

  Future<void> _checkUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    
    await Future.delayed(const Duration(milliseconds: 500)); // 短暫載入畫面
    
    if (mounted) {
      if (userId == null || userId.isEmpty) {
        // 新的路由應該使用新的註冊頁面
        Navigator.of(context).pushReplacementNamed('/setup_new');
      } else {
        // 有 user_id，僅用 WebSocket 向伺服器發送 register_user 訊息
        await _registerUserToServer(userId);
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/main');
        }
      }
    }
  }

  Future<void> _registerUserToServer(String userId) async {
    // 設置計時器，40秒後顯示提示
    bool connectionCompleted = false;
    Future.delayed(const Duration(seconds: 40)).then((_) {
      if (!connectionCompleted && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('提示'),
              content: const Text('伺服器正在更新'),
              actions: <Widget>[
                TextButton(
                  child: const Text('關閉程式'),
                  onPressed: () {
                    // 關閉程式
                    Navigator.of(context).pop();
                    // 在實際設備上，這不會完全關閉app，但會返回到上一頁
                    // 如果需要完全關閉，可能需要平台特定的代碼
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                ),
                TextButton(
                  child: const Text('重試'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    // 重試連接
                    _registerUserToServer(userId);
                  },
                ),
              ],
            );
          },
        );
      }
    });

    try {
      final chatService = ChatServiceSingleton.instance;
      final wsUrl = ApiConfig.wsUrl;
      await chatService.connect(wsUrl, '', userId);
      connectionCompleted = true;
      chatService.webSocketService.sendMessage({
        'type': 'register_user',
        'userId': userId,
      });
      debugPrint('[Main] WebSocket 用戶註冊成功: userId=$userId');
    } catch (e) {
      connectionCompleted = true;
      debugPrint('[Main] WebSocket 用戶註冊失敗: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('載入中...'),
          ],
        ),
      ),
    );
  }
}
