import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:near_ride/core/config/api_config.dart';
import 'package:near_ride/features/chat/services/chat_service_singleton.dart';
import 'features/gps/services/gps_tracker.dart';
import 'package:near_ride/features/home/pages/main_tab_page.dart';
import 'package:near_ride/features/auth/pages/user_id_setup_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await GpsTracker.initialize();
    debugPrint('[Main] GPS tracker initialized');
  } catch (error) {
    debugPrint('[Main] GPS tracker initialization failed: $error');
  }

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

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    if (userId == null || userId.isEmpty) {
      Navigator.of(context).pushReplacementNamed('/setup_new');
      return;
    }

    await _registerUserToServer(userId);
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/main');
    }
  }

  Future<void> _registerUserToServer(String userId) async {
    var connectionCompleted = false;

    Future.delayed(const Duration(seconds: 40)).then((_) {
      if (connectionCompleted || !mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('提示'),
          content: const Text('伺服器正在更新'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text('關閉程式'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _registerUserToServer(userId);
              },
              child: const Text('重試'),
            ),
          ],
        ),
      );
    });

    try {
      final chatService = ChatServiceSingleton.instance;
      await chatService.connect(ApiConfig.wsUrl, '', userId);
      connectionCompleted = true;
      chatService.webSocketService.sendMessage({
        'type': 'register_user',
        'userId': userId,
      });
      debugPrint('[Main] WebSocket user registered: $userId');
    } catch (error) {
      connectionCompleted = true;
      debugPrint('[Main] WebSocket registration failed: $error');
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
