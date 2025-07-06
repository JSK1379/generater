import 'package:flutter/material.dart';
import 'main_tab_page.dart';
import 'user_id_setup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_service.dart';

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
        '/setup': (context) => const UserIdSetupPage(),
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
        Navigator.of(context).pushReplacementNamed('/setup');
      } else {
        // 有 user_id，向伺服器發送 register_user 訊息
        await _registerUserToServer(userId);
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/main');
        }
      }
    }
  }

  Future<void> _registerUserToServer(String userId) async {
    try {
      final chatService = ChatService();
      const wsUrl = 'wss://near-ride-backend-api.onrender.com/ws';
      await chatService.connect(wsUrl, '', userId);
      chatService.webSocketService.sendMessage({
        'type': 'register_user',
        'userId': userId,
      });
      debugPrint('[Main] 已發送 register_user: userId=$userId');
    } catch (e) {
      debugPrint('[Main] 發送 register_user 失敗: $e');
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
