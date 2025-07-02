import 'package:flutter/material.dart';
import 'main_tab_page.dart';
import 'user_id_setup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        Navigator.of(context).pushReplacementNamed('/main');
      }
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
