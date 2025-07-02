import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'chat_service.dart';
import 'chat_page.dart';

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
  List<BluetoothService> _services = [];
  final Set<int> _expandedIndexes = {};

  @override
  void initState() {
    super.initState();
    _requestPermissions().then((_) {
      FlutterBluePlus.adapterState.listen((s) {
        setState(() {
          _btState = s;
          if (s != BluetoothAdapterState.on) {
            _scanResults = [];
          }
        });
      });
      FlutterBluePlus.onScanResults.listen((r) {
        for (final result in r) {
          final name = result.advertisementData.advName;
          if (name.isNotEmpty) {
            debugPrint('ScanResult: id=[1m[22m\u001b[1m[22m${result.device.remoteId.str}\u001b[0m, name="$name", rssi=${result.rssi}, manufacturerData=${result.advertisementData.manufacturerData}');
          }
        }
        setState(() => _scanResults = r);
      });
    });
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    if (statuses[Permission.bluetoothScan] != PermissionStatus.granted ||
        statuses[Permission.bluetoothConnect] != PermissionStatus.granted ||
        statuses[Permission.locationWhenInUse] != PermissionStatus.granted) {
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
    setState(() => _isScanning = true);
    await FlutterBluePlus.startScan();
    Future.delayed(const Duration(seconds: 1), () async {
      if (mounted && _isScanning) {
        await _stopScan();
      }
    });
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    setState(() => _isScanning = false);
  }

  Future<void> _connect(BluetoothDevice device) async {
    // 取得連接方的資訊
    final scanResult = _scanResults.firstWhere((result) => result.device.remoteId == device.remoteId);
    final connectionInfo = _extractDeviceInfo(scanResult);

    // 彈出對話框讓用戶決定是否接受連接
    final shouldConnect = await _showConnectionDialog(connectionInfo);
    if (!shouldConnect) {
      return;
    }

    if (!mounted) return;
    // 用戶確認要連接，開啟聊天室
    final chatService = ChatService();
    final currentUserId = await chatService.getCurrentUserId();
    final otherUserId = connectionInfo['deviceId']!; // 使用對方的裝置 ID 作為用戶 ID
    final roomId = chatService.generateRoomId(currentUserId, otherUserId);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          roomId: roomId,
          roomName: '與 ${connectionInfo['nickname']} 的聊天',
          currentUser: currentUserId,
          chatService: chatService,
        ),
      ),
    );

    await device.connect();
    setState(() => _connectedDevice = device);
    _services = await device.discoverServices();
    setState(() {});
  }
  
  Map<String, String> _extractDeviceInfo(ScanResult scanResult) {
    String nickname = '未知裝置';
    String imageId = '';
    
    final manufacturerData = scanResult.advertisementData.manufacturerData;
    if (manufacturerData.containsKey(0x1234)) {
      final bytes = manufacturerData[0x1234]!;
      if (bytes.length > 5 && bytes[0] == 0x42 && bytes[1] == 0x4C && bytes[2] == 0x45 && bytes[3] == 0x41) {
        final nameLen = bytes[4];
        if (bytes.length >= 5 + nameLen) {
          nickname = utf8.decode(bytes.sublist(5, 5 + nameLen));
        }
      }
    }
    if (manufacturerData.containsKey(0x1235)) {
      final bytes = manufacturerData[0x1235]!;
      if (bytes.length > 5 && bytes[0] == 0x42 && bytes[1] == 0x4C && bytes[2] == 0x45 && bytes[3] == 0x49) {
        final nameLen = bytes[4];
        if (bytes.length >= 6 + nameLen) {
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
      'deviceId': scanResult.device.remoteId.str,
      'rssi': '${scanResult.rssi} dBm'
    };
  }
  
  Future<bool> _showConnectionDialog(Map<String, String> deviceInfo) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('收到連接請求'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('暱稱: ${deviceInfo['nickname']}'),
            Text('裝置ID: ${deviceInfo['deviceId']}'),
            Text('信號強度: ${deviceInfo['rssi']}'),
            if (deviceInfo['imageId']!.isNotEmpty)
              Text('圖片ID: ${deviceInfo['imageId']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('拒絕'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('接受'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _disconnect() async {
    await _connectedDevice?.disconnect();
    setState(() {
      _connectedDevice = null;
      _services = [];
    });
  }

  Future<void> _readCharacteristic(BluetoothCharacteristic c) async {
    var value = await c.read();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('讀取值: $value')),
    );
  }

  Future<void> _writeCharacteristic(BluetoothCharacteristic c) async {
    await c.write([0x01]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已寫入 0x01')),
    );
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
            const Divider(),
            const Text('服務與特徵值：'),
            ..._services.expand((s) => s.characteristics.map((c) => ListTile(
              title: Text('UUID: ${c.uuid}'),
              subtitle: Text('屬性: ${c.properties}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.properties.read)
                    IconButton(
                      icon: const Icon(Icons.download),
                      onPressed: () => _readCharacteristic(c),
                    ),
                  if (c.properties.write)
                    IconButton(
                      icon: const Icon(Icons.upload),
                      onPressed: () => _writeCharacteristic(c),
                    ),
                ],
              ),
            ))),
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
                  if (mdata.containsKey(0x1234)) {
                    final bytes = mdata[0x1234]!;
                    if (bytes.length > 5 &&
                        bytes[0] == 0x42 && bytes[1] == 0x4C && bytes[2] == 0x45 && bytes[3] == 0x41) {
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
                  if (mdata.containsKey(0x1234)) {
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
                        setState(() {
                          if (isExpanded) {
                            _expandedIndexes.remove(i);
                          } else {
                            _expandedIndexes.add(i);
                          }
                        });
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
