import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'chat_service_singleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BleScanBody extends StatefulWidget {
  const BleScanBody({super.key});
  @override
  State<BleScanBody> createState() => _BleScanBodyState();
}

class _BleScanBodyState extends State<BleScanBody> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  BluetoothAdapterState? _btState;
  BluetoothDevice? _connectedDevice;
  final Set<int> _expandedIndexes = {};
  String _currentUserId = ''; // 新增當前用戶 ID 變數

  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId(); // 載入當前用戶 ID
    // 添加連接回應監聽器
    ChatServiceSingleton.instance.addConnectResponseListener(_onConnectResponse);
    _requestPermissions().then((_) {
      _adapterStateSubscription = FlutterBluePlus.adapterState.listen((s) {
        if (mounted) {
          setState(() {
            _btState = s;
            if (s != BluetoothAdapterState.on) {
              _scanResults = [];
            }
          });
        }
      });
      FlutterBluePlus.onScanResults.listen((r) {
        if (mounted) setState(() => _scanResults = r);
      });
    });
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    _scanResultsSubscription?.cancel();
    _connectedDevice?.disconnect();
    // 移除連接回應監聽器
    ChatServiceSingleton.instance.removeConnectResponseListener(_onConnectResponse);
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    // 分別請求每一個權限
    var bluetoothScanStatus = await Permission.bluetoothScan.request();
    var bluetoothConnectStatus = await Permission.bluetoothConnect.request();
    var locationStatus = await Permission.locationWhenInUse.request();
    
    // 檢查是否所有權限都被允許
    if (bluetoothScanStatus != PermissionStatus.granted ||
        bluetoothConnectStatus != PermissionStatus.granted ||
        locationStatus != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請授權所有藍牙權限才能使用藍牙功能')),
        );
      }
      return;
    }
    // 權限允許後自動重啟 app
    // Future.delayed(const Duration(milliseconds: 300), () {
    //   runApp(const MyApp());
    // });
  }

  Future<void> _startScan() async {
    if (mounted) {
      setState(() => _isScanning = true);
    }
    await FlutterBluePlus.startScan();
    Future.delayed(const Duration(seconds: 1), () async {
      if (mounted && _isScanning) {
        await _stopScan();
      }
    });
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    if (mounted) {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    // 取得連接方的資訊
    final scanResult = _scanResults.firstWhere((result) => result.device.remoteId == device.remoteId);
    final connectionInfo = _extractDeviceInfo(scanResult);

    // 顯示提示窗，詢問用戶是否要連接
    final shouldConnect = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('是否要連接對方？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('暱稱: ${connectionInfo['nickname']}'),
            if (connectionInfo['userId']!.isNotEmpty)
              Text('用戶ID: ${connectionInfo['userId']}')
            else
              Text('裝置ID: ${connectionInfo['deviceId']}'),
            Text('信號強度: ${connectionInfo['rssi']}'),
            if (connectionInfo['imageId']!.isNotEmpty)
              Text('圖片ID: ${connectionInfo['imageId']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('連接'),
          ),
        ],
      ),
    );
    if (shouldConnect != true) {
      // 用戶取消連接
      return;
    }

    if (!mounted) return;
    final chatService = ChatServiceSingleton.instance;
    final currentUserId = await chatService.getCurrentUserId();
    // 優先使用 userId，如果沒有則回退到 deviceId
    final otherUserId = connectionInfo['userId']!.isNotEmpty 
        ? connectionInfo['userId']! 
        : connectionInfo['deviceId']!;
    // final roomId = chatService.generateRoomId(currentUserId, otherUserId); // 已移除未使用變數

    // 儲存聊天室歷史（僅在成功建立聊天室時再儲存）

    // 發送連線請求，使用 userId
    chatService.sendConnectRequest(currentUserId, otherUserId);
    debugPrint('[BLE] Sent connect_request from: $currentUserId to: $otherUserId (原裝置ID: ${connectionInfo['deviceId']})');

    // 等待 connect_response 由監聽器處理自動進聊天室或顯示被拒絕提示
    // 這裡不再直接進聊天室
  }
  
  Map<String, String> _extractDeviceInfo(ScanResult scanResult) {
    String nickname = '未知裝置';
    String imageId = '';
    String userId = '';
    
    final manufacturerData = scanResult.advertisementData.manufacturerData;
    
    // 優先檢查包含 userId 的廣播 (0x1236, BLEU)
    if (manufacturerData.containsKey(0x1236)) {
      final bytes = manufacturerData[0x1236]!;
      if (bytes.length > 7 && bytes[0] == 0x42 && bytes[1] == 0x4C && bytes[2] == 0x45 && bytes[3] == 0x55) {
        // BLEU 格式: [BLEU][nickname_len][nickname][userId_len][userId][imageId_len][imageId]
        final nameLen = bytes[4];
        if (bytes.length >= 5 + nameLen + 1) {
          nickname = utf8.decode(bytes.sublist(5, 5 + nameLen));
          final userIdLen = bytes[5 + nameLen];
          if (bytes.length >= 6 + nameLen + userIdLen) {
            userId = utf8.decode(bytes.sublist(6 + nameLen, 6 + nameLen + userIdLen));
            // 檢查是否有 imageId
            if (bytes.length >= 7 + nameLen + userIdLen) {
              final imageIdLen = bytes[6 + nameLen + userIdLen];
              if (imageIdLen > 0 && bytes.length >= 7 + nameLen + userIdLen + imageIdLen) {
                imageId = utf8.decode(bytes.sublist(7 + nameLen + userIdLen, 7 + nameLen + userIdLen + imageIdLen));
              }
            }
          }
        }
        debugPrint('[BLE] 解析到帶 userId 的廣播 - nickname: $nickname, userId: $userId, imageId: $imageId');
      }
    }
    // 如果沒有找到 userId 廣播，回退到舊格式
    else if (manufacturerData.containsKey(0x1234)) {
      final bytes = manufacturerData[0x1234]!;
      if (bytes.length > 5 && bytes[0] == 0x42 && bytes[1] == 0x4C && bytes[2] == 0x45 && bytes[3] == 0x41) {
        final nameLen = bytes[4];
        if (bytes.length >= 5 + nameLen) {
          nickname = utf8.decode(bytes.sublist(5, 5 + nameLen));
        }
      }
    }
    else if (manufacturerData.containsKey(0x1235)) {
      final bytes = manufacturerData[0x1235]!;
      if (bytes.length > 5 && bytes[0] == 0x42 && bytes[1] == 0x4C && bytes[2] == 0x45 && bytes[3] == 0x49) {
        final nameLen = bytes[4];
        if (bytes.length >= 6 + nameLen) {
          nickname = utf8.decode(bytes.sublist(5, 5 + nameLen));
          final imageIdLen = bytes[5 + nameLen];
          if (imageIdLen > 0 && bytes.length >= 6 + nameLen + imageIdLen) {
            imageId = utf8.decode(bytes.sublist(6 + nameLen, 6 + nameLen + imageIdLen));
          }
        }
      }
    }
    
    return {
      'nickname': nickname,
      'imageId': imageId,
      'userId': userId,
      'deviceId': scanResult.device.remoteId.str,
      'rssi': '${scanResult.rssi} dBm'
    };
  }
  
  Future<void> _disconnect() async {
    await _connectedDevice?.disconnect();
    if (mounted) {
      setState(() {
        _connectedDevice = null;
      });
    }
  }

  Widget _buildAvatarFromManufacturer(Map<int, List<int>> manufacturerData) {
    if (manufacturerData.containsKey(0x1234)) {
      final bytes = manufacturerData[0x1234]!;
      if (bytes.length > 6 &&
          bytes[0] == 0x42 && bytes[1] == 0x4C && bytes[2] == 0x45 && bytes[3] == 0x41) {
        final nameLen = bytes[4];
        if (bytes.length >= 6 + nameLen) {
          final avatarLen = bytes[5 + nameLen];
          if (avatarLen > 0 && bytes.length >= 6 + nameLen + avatarLen) {
            final avatarBytes = bytes.sublist(6 + nameLen, 6 + nameLen + avatarLen);
            try {
              return CircleAvatar(radius: 20, backgroundImage: MemoryImage(Uint8List.fromList(avatarBytes)));
            } catch (e) {
              return const CircleAvatar(radius: 20, child: Icon(Icons.error));
            }
          }
        }
      }
    }
    return const CircleAvatar(radius: 20, child: Icon(Icons.person));
  }

  // ...已移除未使用的 _saveChatRoomHistory 方法...

  // 載入當前用戶 ID
  Future<void> _loadCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'unknown_user';
    if (!mounted) return;
    setState(() {
      _currentUserId = userId;
    });
  }

  // 處理連接回應
  void _onConnectResponse(String from, String to, bool accept) {
    if (!mounted) return;
    // 只處理回應給自己的消息（我是接收方）
    if (to != _currentUserId) return;

    if (accept) {
      // 不再自動跳轉聊天室，由 joined_room 事件處理
      // roomId 將由伺服器產生，並通過 joined_room 事件傳遞
    } else {
      // 如果被拒絕，顯示提示
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('你好像被拒絕了;;', style: TextStyle(fontSize: 16)),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('BLE 掃描 + 裝置列表')),
    body: Column(children: [
      if (_connectedDevice != null)
        Text('已連接：${_connectedDevice!.platformName.isNotEmpty ? _connectedDevice!.platformName : _connectedDevice!.remoteId.str}')
      else
        ElevatedButton(
          onPressed: () async {
            if (_isScanning) {
              await _stopScan();
            } else {
              if (_btState != BluetoothAdapterState.on) {
                await _requestPermissions();
                if (_btState != BluetoothAdapterState.on) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('請先開啟藍牙才能掃描')),
                    );
                  }
                  return;
                }
              }
              await _startScan();
            }
          },
          child: Text(_isScanning ? '停止掃描' : '開始掃描'),
        ),
      if (_connectedDevice != null)
        Column(
          children: [
            ElevatedButton(
              onPressed: _disconnect,
              child: const Text('重新配對'),
            ),
          ],
        )
      else
        Expanded(
          child: _scanResults.where((r) => r.advertisementData.advName.isNotEmpty || r.device.platformName.isNotEmpty).isEmpty
            ? const Center(child: Text('沒有人在這個地方QQ'))
            : ListView.builder(
                itemCount: _scanResults.where((r) => r.advertisementData.advName.isNotEmpty || r.device.platformName.isNotEmpty).length,
                itemBuilder: (_, i) {
                  final filteredResults = _scanResults.where((r) => r.advertisementData.advName.isNotEmpty || r.device.platformName.isNotEmpty).toList();
                  final r = filteredResults[i];
                  String? nicknameFromManufacturer;
                  final mdata = r.advertisementData.manufacturerData;
                  // 先解析 0x1236 (userId 格式)
                  if (mdata.containsKey(0x1236)) {
                    final bytes = mdata[0x1236]!;
                    if (bytes.length > 7 && bytes[0] == 0x42 && bytes[1] == 0x4C && bytes[2] == 0x45 && bytes[3] == 0x55) {
                      try {
                        final nameLen = bytes[4];
                        if (bytes.length >= 5 + nameLen) {
                          final nameBytes = bytes.sublist(5, 5 + nameLen);
                          nicknameFromManufacturer = utf8.decode(nameBytes, allowMalformed: true);
                        }
                      } catch (_) {}
                    }
                  }
                  // fallback 舊格式 0x1234
                  if ((nicknameFromManufacturer == null || nicknameFromManufacturer.isEmpty) && mdata.containsKey(0x1234)) {
                    final bytes = mdata[0x1234]!;
                    if (bytes.length > 5 && bytes[0] == 0x42 && bytes[1] == 0x4C && bytes[2] == 0x45 && bytes[3] == 0x41) {
                      try {
                        final nameLen = bytes[4];
                        if (bytes.length >= 6 + nameLen) {
                          final nameBytes = bytes.sublist(5, 5 + nameLen);
                          nicknameFromManufacturer = utf8.decode(nameBytes, allowMalformed: true);
                        }
                      } catch (_) {}
                    }
                  }
                  final name = nicknameFromManufacturer?.isNotEmpty == true
                      ? nicknameFromManufacturer!
                      : (r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName);
                  bool isSameApp = false;
                  if (mdata.containsKey(0x1236)) {
                    final bytes = mdata[0x1236]!;
                    if (bytes.length >= 4 && bytes[0] == 0x42 && bytes[1] == 0x4C && bytes[2] == 0x45 && bytes[3] == 0x55) {
                      isSameApp = true;
                    }
                  } else if (mdata.containsKey(0x1234)) {
                    final bytes = mdata[0x1234]!;
                    if (bytes.length >= 4 && bytes[0] == 0x42 && bytes[1] == 0x4C && bytes[2] == 0x45 && bytes[3] == 0x41) {
                      isSameApp = true;
                    }
                  }
                  final displayName = isSameApp ? '★$name' : name;
                  final isExpanded = _expandedIndexes.contains(i);
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        if (mounted) {
                          setState(() {
                            if (isExpanded) {
                              _expandedIndexes.remove(i);
                            } else {
                              _expandedIndexes.add(i);
                            }
                          });
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _buildAvatarFromManufacturer(r.advertisementData.manufacturerData),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () => _connect(r.device),
                                  child: const Text('連接'),
                                ),
                                Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                              ],
                            ),
                            AnimatedCrossFade(
                              firstChild: const SizedBox.shrink(),
                              secondChild: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Complete Local Name:',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : '(無)'),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'ID:',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(r.device.remoteId.str),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'RSSI:',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text('${r.rssi} dBm'),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Manufacturer:',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(r.advertisementData.manufacturerData.isNotEmpty ? r.advertisementData.manufacturerData.toString() : '無'),
                                  if (r.advertisementData.manufacturerData.containsKey(0x1234))
                                    Builder(
                                      builder: (_) {
                                        final bytes = r.advertisementData.manufacturerData[0x1234]!;
                                        if (bytes.length > 5 &&
                                            bytes[0] == 0x42 && bytes[1] == 0x4C && bytes[2] == 0x45 && bytes[3] == 0x41) {
                                          try {
                                            final nameLen = bytes[4];
                                            if (bytes.length >= 6 + nameLen) {
                                              // final nameBytes = bytes.sublist(5, 5 + nameLen);
                                            }
                                          } catch (_) {}
                                        }
                                        return Text('暱稱(解碼): ${(nicknameFromManufacturer != null && nicknameFromManufacturer.isNotEmpty) ? nicknameFromManufacturer : "(無)"}', style: const TextStyle(color: Colors.blue));
                                      },
                                    ),
                                ],
                              ),
                              crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 250),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
        ),
    ]),
  );
}
