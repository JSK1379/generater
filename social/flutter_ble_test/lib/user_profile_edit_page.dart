import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'api_config.dart';

class UserProfileEditPage extends StatefulWidget {
  final String userId;
  final String initialNickname;

  const UserProfileEditPage({
    super.key,
    required this.userId,
    required this.initialNickname,
  });

  @override
  State<UserProfileEditPage> createState() => _UserProfileEditPageState();
}

class _UserProfileEditPageState extends State<UserProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  
  String _selectedGender = 'male';
  List<int> _selectedHobbyIds = [];
  List<Map<String, dynamic>> _availableHobbies = [];
  bool _isLoading = false;
  bool _isLoadingProfile = true;
  
  // 頭貼相關變數
  ImageProvider? _avatarImageProvider;
  File? _selectedAvatarFile;
  String? _currentAvatarUrl;
  final ImagePicker _picker = ImagePicker();

  // 預設興趣列表
  final List<Map<String, dynamic>> _defaultHobbies = [
    {'id': 1, 'name': '籃球', 'description': '喜歡打籃球'},
    {'id': 2, 'name': '閱讀', 'description': '愛看書'},
    {'id': 3, 'name': '音樂', 'description': '聽音樂和唱歌'},
    {'id': 4, 'name': '旅遊', 'description': '探索新地方'},
    {'id': 5, 'name': '料理', 'description': '烹飪美食'},
    {'id': 6, 'name': '攝影', 'description': '拍照記錄生活'},
    {'id': 7, 'name': '運動', 'description': '各種體育運動'},
    {'id': 8, 'name': '電影', 'description': '看電影'},
    {'id': 9, 'name': '遊戲', 'description': '玩電子遊戲'},
    {'id': 10, 'name': '繪畫', 'description': '藝術創作'},
  ];

  @override
  void initState() {
    super.initState();
    _nicknameController.text = widget.initialNickname;
    _availableHobbies = List.from(_defaultHobbies);
    _testServerConnection(); // 測試伺服器連線
    _loadUserProfile();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _ageController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _testServerConnection() async {
    try {
      debugPrint('[UserProfileEdit] 測試伺服器連線...');
      
      // 測試基本連線
      final healthCheck = Uri.parse(ApiConfig.health);
      debugPrint('[UserProfileEdit] 測試健康檢查端點: $healthCheck');
      
      final healthResponse = await http.get(healthCheck).timeout(ApiConfig.defaultTimeout);
      debugPrint('[UserProfileEdit] 健康檢查回應: ${healthResponse.statusCode} - ${healthResponse.body}');
      
      if (healthResponse.statusCode == 200) {
        debugPrint('[UserProfileEdit] ✅ 伺服器連線正常');
      } else {
        debugPrint('[UserProfileEdit] ⚠️ 伺服器健康檢查異常: ${healthResponse.statusCode}');
      }
      
    } catch (e) {
      debugPrint('[UserProfileEdit] ❌ 伺服器連線測試失敗: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      debugPrint('[UserProfileEdit] 開始載入用戶資料，用戶 ID: ${widget.userId}');
      
      final uri = Uri.parse(ApiConfig.userProfile(widget.userId));
      
      debugPrint('[UserProfileEdit] 請求 URL: $uri');
      debugPrint('[UserProfileEdit] 請求標頭: ${ApiConfig.jsonHeaders}');
      
      final response = await http.get(
        uri,
        headers: ApiConfig.jsonHeaders,
      ).timeout(ApiConfig.defaultTimeout);
      
      debugPrint('[UserProfileEdit] HTTP 回應狀態碼: ${response.statusCode}');
      debugPrint('[UserProfileEdit] HTTP 回應標頭: ${response.headers}');
      debugPrint('[UserProfileEdit] HTTP 回應內容: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('[UserProfileEdit] 成功獲取用戶資料: $data');
        
        setState(() {
          _nicknameController.text = data['nickname'] ?? widget.initialNickname;
          _selectedGender = data['gender'] ?? 'male';
          _ageController.text = data['age']?.toString() ?? '';
          _locationController.text = data['location'] ?? '';
          
          // 處理頭貼
          if (data['avatar_url'] != null && data['avatar_url'].toString().isNotEmpty) {
            _currentAvatarUrl = data['avatar_url'].toString();
            _avatarImageProvider = NetworkImage(_currentAvatarUrl!);
          }
          
          // 處理興趣
          if (data['hobbies'] != null && data['hobbies'] is List) {
            _selectedHobbyIds = (data['hobbies'] as List)
                .map((hobby) => hobby['id'] as int)
                .toList();
          }
          
          _isLoadingProfile = false;
        });
      } else {
        // API 失敗時的處理
        debugPrint('[UserProfileEdit] 獲取用戶資料失敗: ${response.statusCode}');
        debugPrint('[UserProfileEdit] 錯誤回應: ${response.body}');
        
        // 嘗試解析錯誤訊息
        String errorMessage = 'HTTP ${response.statusCode}';
        try {
          final errorData = jsonDecode(response.body);
          if (errorData['message'] != null) {
            errorMessage += ' - ${errorData['message']}';
          } else if (errorData['error'] != null) {
            errorMessage += ' - ${errorData['error']}';
          }
        } catch (e) {
          // 如果無法解析錯誤訊息，使用原始回應
          errorMessage += ' - ${response.body}';
        }
        
        // 使用預設值並顯示警告
        setState(() {
          _isLoadingProfile = false;
        });
        
        if (mounted) {
          // 對於 500 錯誤，提供重試選項
          if (response.statusCode == 500) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('伺服器錯誤'),
                content: const Text('伺服器目前遇到內部錯誤，無法載入您的資料。\n\n您可以選擇重試，或先使用預設值編輯資料。'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _loadUserProfile(); // 重試
                    },
                    child: const Text('重試'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('使用預設值'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('技術詳情'),
                          content: SingleChildScrollView(
                            child: Text(
                              '錯誤代碼: ${response.statusCode}\n'
                              '用戶 ID: ${widget.userId}\n'
                              '請求 URL: $uri\n'
                              '回應內容: ${response.body}\n'
                              '錯誤訊息: $errorMessage\n'
                              '時間: ${DateTime.now()}'
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('關閉'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('技術詳情'),
                  ),
                ],
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('無法載入用戶資料 ($errorMessage)，將使用預設值'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[UserProfileEdit] 載入用戶資料時發生錯誤: $e');
      
      // 使用預設值
      setState(() {
        _isLoadingProfile = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('網路錯誤，無法載入用戶資料: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 選擇頭貼
  Future<void> _pickAvatar() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 512,
        maxHeight: 512,
      );
      
      if (image != null) {
        final file = File(image.path);
        setState(() {
          _selectedAvatarFile = file;
          _avatarImageProvider = FileImage(file);
        });
        
        debugPrint('[UserProfileEdit] 選擇了新頭貼: ${file.path}');
      }
    } catch (e) {
      debugPrint('[UserProfileEdit] 選擇頭貼時發生錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('選擇頭貼失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('[UserProfileEdit] 開始儲存用戶資料，用戶 ID: ${widget.userId}');
      
      final uri = Uri.parse(ApiConfig.userProfile(widget.userId));
      
      // 🔄 改用 JSON 格式上傳基本資料
      final profileData = <String, dynamic>{
        'nickname': _nicknameController.text.trim(),
        'gender': _selectedGender,
        'hobby_ids': _selectedHobbyIds,
      };
      
      // 只在有值時才加入年齡和地點
      if (_ageController.text.trim().isNotEmpty) {
        final age = int.tryParse(_ageController.text.trim());
        if (age != null) {
          profileData['age'] = age;
        }
      }
      if (_locationController.text.trim().isNotEmpty) {
        profileData['location'] = _locationController.text.trim();
      }
      
      debugPrint('[UserProfileEdit] 準備發送的JSON資料: $profileData');
      debugPrint('[UserProfileEdit] 請求 URL: $uri');

      // 先更新基本資料
      final response = await http.patch(
        uri,
        headers: ApiConfig.jsonHeaders,
        body: jsonEncode(profileData),
      ).timeout(ApiConfig.defaultTimeout);

      debugPrint('[UserProfileEdit] HTTP 回應狀態碼: ${response.statusCode}');
      debugPrint('[UserProfileEdit] HTTP 回應內容: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        debugPrint('[UserProfileEdit] 用戶資料更新成功: $responseData');
        
        // 更新本地暱稱
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('nickname', _nicknameController.text.trim());
        
        // 🖼️ 如果有選擇新頭貼，直接用 base64 格式上傳
        String? avatarUploadResult;
        if (_selectedAvatarFile != null) {
          debugPrint('[UserProfileEdit] 開始上傳頭貼（使用 base64 格式）...');
          avatarUploadResult = await _uploadAvatarAsBase64();
        }
        
        if (mounted) {
          final hasAvatarUpload = _selectedAvatarFile != null;
          final avatarSuccess = avatarUploadResult != null;
          
          String message;
          if (hasAvatarUpload && avatarSuccess) {
            if (avatarUploadResult == 'success_no_url') {
              message = '用戶資料和頭貼更新成功（頭貼處理中，請稍後刷新頁面查看）';
            } else {
              message = '用戶資料和頭貼更新成功';
            }
          } else if (hasAvatarUpload && !avatarSuccess) {
            message = '用戶資料更新成功，但頭貼上傳失敗';
          } else {
            message = '用戶資料更新成功';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: (hasAvatarUpload && !avatarSuccess) ? Colors.red : 
                              (avatarUploadResult == 'success_no_url') ? Colors.orange : Colors.green,
              duration: avatarUploadResult == 'success_no_url' 
                  ? const Duration(seconds: 4) 
                  : const Duration(seconds: 2),
            ),
          );
          Navigator.of(context).pop(true); // 返回 true 表示有更新
        }
      } else {
        // 處理錯誤回應
        String errorMessage = 'HTTP ${response.statusCode}';
        
        try {
          final errorData = jsonDecode(response.body);
          if (errorData['message'] != null) {
            errorMessage += ' - ${errorData['message']}';
          } else if (errorData['error'] != null) {
            errorMessage += ' - ${errorData['error']}';
          } else if (errorData['detail'] != null) {
            errorMessage += ' - ${errorData['detail']}';
          }
        } catch (e) {
          // 如果無法解析 JSON，顯示原始回應
          errorMessage += ' - ${response.body}';
        }

        debugPrint('[UserProfileEdit] 更新失敗: $errorMessage');
        
        if (mounted) {
          // 根據狀態碼顯示不同的錯誤訊息
          String userMessage;
          if (response.statusCode == 404) {
            userMessage = '找不到用戶資料，請確認用戶 ID 是否正確';
          } else if (response.statusCode == 400) {
            userMessage = '資料格式錯誤，請檢查輸入的資料';
          } else if (response.statusCode == 422) {
            userMessage = '資料驗證失敗，請檢查必填欄位和資料格式';
          } else if (response.statusCode == 500) {
            userMessage = '伺服器內部錯誤，請稍後再試。如果問題持續存在，請聯繫技術支援';
          } else {
            userMessage = '更新失敗: $errorMessage';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(userMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: '查看詳情',
                textColor: Colors.white,
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('錯誤詳情'),
                      content: SingleChildScrollView(
                        child: Text('狀態碼: ${response.statusCode}\n\n回應內容:\n${response.body}'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('確定'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[UserProfileEdit] 更新用戶資料時發生錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('網路錯誤: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
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
  
  // 🖼️ 使用 base64 格式上傳頭像
  Future<String?> _uploadAvatarAsBase64() async {
    if (_selectedAvatarFile == null) return null;
    
    try {
      // 讀取檔案並轉換為 base64
      final bytes = await _selectedAvatarFile!.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      final uri = Uri.parse(ApiConfig.userProfile(widget.userId));
      
      final avatarData = {
        'avatar_base64': base64Image,
      };
      
      debugPrint('[UserProfileEdit] 使用 base64 上傳頭像到: $uri');
      debugPrint('[UserProfileEdit] base64 資料長度: ${base64Image.length} 字符');
      
      final response = await http.patch(
        uri,
        headers: ApiConfig.jsonHeaders,
        body: jsonEncode(avatarData),
      ).timeout(ApiConfig.uploadTimeout);
      
      debugPrint('[UserProfileEdit] base64 頭像上傳回應狀態: ${response.statusCode}');
      debugPrint('[UserProfileEdit] base64 頭像上傳回應內容: ${response.body}');
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final avatarUrl = responseData['avatar_url'] as String?;
        
        if (avatarUrl != null && avatarUrl.isNotEmpty) {
          setState(() {
            _currentAvatarUrl = avatarUrl;
            _selectedAvatarFile = null;
            _avatarImageProvider = NetworkImage(avatarUrl);
          });
          
          debugPrint('[UserProfileEdit] base64 頭像上傳成功，URL: $avatarUrl');
          return avatarUrl;
        } else {
          // 即使沒有返回 URL，也清除選擇的檔案，因為伺服器已經接收了資料
          setState(() {
            _selectedAvatarFile = null;
            // 保持使用本地圖片預覽，直到重新載入用戶資料
          });
          
          debugPrint('[UserProfileEdit] base64 頭像上傳成功，但未返回 URL。伺服器可能需要時間處理。');
          debugPrint('[UserProfileEdit] 伺服器回應: ${response.body}');
          return 'success_no_url';
        }
      } else {
        debugPrint('[UserProfileEdit] base64 頭像上傳失敗: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[UserProfileEdit] base64 頭像上傳錯誤: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingProfile) {
      return Scaffold(
        appBar: AppBar(title: const Text('編輯用戶資料')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('編輯用戶資料'),
        actions: [
          IconButton(
            onPressed: _isLoadingProfile ? null : () {
              setState(() {
                _isLoadingProfile = true;
              });
              _testServerConnection();
              _loadUserProfile();
            },
            icon: const Icon(Icons.refresh),
            tooltip: '重新載入資料',
          ),
          TextButton(
            onPressed: _isLoading ? null : _saveProfile,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('儲存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 用戶 ID 顯示
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text('用戶 ID: ', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(widget.userId),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 頭貼選擇區域
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          '頭貼',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _pickAvatar,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 60,
                                backgroundImage: _avatarImageProvider,
                                child: _avatarImageProvider == null
                                    ? const Icon(Icons.person, size: 60, color: Colors.grey)
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedAvatarFile != null 
                              ? '已選擇新頭貼' 
                              : '點擊更換頭貼',
                          style: TextStyle(
                            color: _selectedAvatarFile != null 
                                ? Colors.green 
                                : Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 暱稱
                TextFormField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(
                    labelText: '暱稱',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.account_circle),
                  ),
                  maxLength: 20,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '請輸入暱稱';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 性別
                const Text('性別', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('男性'),
                        value: 'male',
                        groupValue: _selectedGender,
                        onChanged: (value) => setState(() => _selectedGender = value!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('女性'),
                        value: 'female',
                        groupValue: _selectedGender,
                        onChanged: (value) => setState(() => _selectedGender = value!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('其他'),
                        value: 'other',
                        groupValue: _selectedGender,
                        onChanged: (value) => setState(() => _selectedGender = value!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 年齡
                TextFormField(
                  controller: _ageController,
                  decoration: const InputDecoration(
                    labelText: '年齡',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.cake),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value != null && value.trim().isNotEmpty) {
                      final age = int.tryParse(value.trim());
                      if (age == null || age < 1 || age > 120) {
                        return '請輸入有效的年齡 (1-120)';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 居住地
                TextFormField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: '居住地',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
                const SizedBox(height: 24),

                // 興趣
                const Text('興趣', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('選擇您的興趣愛好:', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: _availableHobbies.map((hobby) {
                    final isSelected = _selectedHobbyIds.contains(hobby['id']);
                    return FilterChip(
                      label: Text(hobby['name']),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedHobbyIds.add(hobby['id']);
                          } else {
                            _selectedHobbyIds.remove(hobby['id']);
                          }
                        });
                      },
                      backgroundColor: Colors.grey[200],
                      selectedColor: Colors.blue[100],
                      checkmarkColor: Colors.blue[800],
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // 儲存按鈕
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            '儲存所有資料',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
