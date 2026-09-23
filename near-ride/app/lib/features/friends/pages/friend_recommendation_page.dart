import 'package:flutter/material.dart';
import 'package:near_ride/features/chat/services/chat_service_singleton.dart';
import 'package:near_ride/features/friends/services/friend_recommendation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FriendRecommendationPage extends StatefulWidget {
  const FriendRecommendationPage({super.key});

  @override
  State<FriendRecommendationPage> createState() => _FriendRecommendationPageState();
}

class _FriendRecommendationPageState extends State<FriendRecommendationPage> {
  final FriendRecommendationService _service = const FriendRecommendationService();
  final Set<int> _seenUserIds = <int>{};
  String? _userId;
  RecommendedFriend? _person;
  String? _status;
  String? _error;
  bool _busy = true;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (mounted) setState(() { _busy = true; _error = null; _status = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null || int.tryParse(userId) == null) {
        if (mounted) setState(() => _status = '請先登入帳號，再使用好友推薦。');
        return;
      }
      final enabled = await _service.isEnabled(userId);
      if (!mounted) return;
      setState(() {
        _userId = userId;
        _enabled = enabled;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '無法讀取推薦設定，請稍後重試。');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_enabled) _loadNext(reset: true);
      }
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    final userId = _userId;
    if (_busy || userId == null) return;
    setState(() => _busy = true);
    try {
      await _service.setEnabled(userId, enabled);
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _person = null;
        _error = null;
        _status = enabled ? null : '已停止參與推薦及分享路線相似度。';
        _seenUserIds.clear();
      });
    } catch (_) {
      if (mounted) setState(() => _error = '設定更新失敗，請確認網路連線。');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_enabled && enabled) _loadNext(reset: true);
      }
    }
  }

  Future<void> _loadNext({bool reset = false}) async {
    final userId = _userId;
    if (_busy || !_enabled || userId == null) return;
    if (reset) _seenUserIds.clear();
    final previousId = int.tryParse(_person?.userId ?? '');
    if (!reset && previousId != null) _seenUserIds.add(previousId);
    setState(() {
      _busy = true;
      _person = null;
      _status = null;
      _error = null;
    });
    try {
      final result = await _service.getNext(userId, excludedUserIds: _seenUserIds);
      if (!mounted) return;
      setState(() {
        _person = result.person;
        if (result.person == null) {
          _status = switch (result.reason) {
            'insufficient_gps' => '近兩週定位記錄不足，累積更多路線後再試試。',
            'disabled' => '請先開啟好友推薦。',
            _ => '目前沒有其他已開啟推薦、且路線相近的對象。',
          };
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = '取得推薦對象失敗，請稍後重試。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sendInvite() {
    final person = _person;
    final userId = _userId;
    if (person == null || userId == null) return;
    final chat = ChatServiceSingleton.instance;
    if (!chat.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('聊天室尚未連線，請稍後重試。')),
      );
      return;
    }
    chat.sendConnectRequest(userId, person.userId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已嘗試發送邀請；對方離線時可能不會收到。')),
    );
  }

  String _genderLabel(String? gender) => switch (gender) {
        'male' => '男性',
        'female' => '女性',
        'other' => '其他',
        _ => '未提供',
      };

  @override
  Widget build(BuildContext context) {
    final person = _person;
    final avatar = person?.avatarUrl;
    final validAvatar = avatar != null &&
        (Uri.tryParse(avatar)?.scheme == 'https' ||
            Uri.tryParse(avatar)?.scheme == 'http');

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Text('推薦好友', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('一次推薦一位近期 GPS 路線相近的使用者，不會顯示對方的精確位置或完整路線。'),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('參與好友推薦'),
          subtitle: const Text('開啟後，你也可能出現在其他參與者的推薦頁。'),
          value: _enabled,
          onChanged: _busy || _userId == null ? null : _setEnabled,
        ),
        const SizedBox(height: 16),
        if (_busy) const Center(child: CircularProgressIndicator()),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _enabled ? () => _loadNext(reset: true) : _initialize, child: const Text('重試')),
        ],
        if (_status != null && !_busy) ...[
          Text(_status!),
          const SizedBox(height: 12),
          if (_enabled)
            OutlinedButton(onPressed: () => _loadNext(reset: true), child: const Text('重新推薦')),
        ],
        if (!_enabled && !_busy && _error == null)
          const Text('開啟上方選項後，系統會比對雙方近期路線，再顯示一位推薦對象。'),
        if (person != null && _enabled && !_busy)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 46,
                    backgroundImage: validAvatar ? NetworkImage(avatar) : null,
                    child: validAvatar ? null : const Icon(Icons.person, size: 48),
                  ),
                  const SizedBox(height: 16),
                  Text(person.nickname, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('年齡：${person.age?.toString() ?? '未提供'}　性別：${_genderLabel(person.gender)}'),
                  const SizedBox(height: 12),
                  Text(person.matchReason, textAlign: TextAlign.center),
                  if (person.hobbies.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: person.hobbies.map((name) => Chip(label: Text(name))).toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _sendInvite,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('發送連接邀請'),
                  ),
                  OutlinedButton(
                    onPressed: () => _loadNext(),
                    child: const Text('下一位'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
