import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'avatar_page.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: MainTabPage(),
    );
  }
}

class MainTabPage extends StatefulWidget {
  const MainTabPage({super.key});
  @override
  State<MainTabPage> createState() => _MainTabPageState();
}

class _MainTabPageState extends State<MainTabPage> {
  int _currentIndex = 0;
  final List<Widget> _pages = const [
    BleScanBody(),
    AvatarPage(),
    SettingsPage(),
  ];
  final List<BottomNavigationBarItem> _items = const [
    BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: '藍牙'),
    BottomNavigationBarItem(icon: Icon(Icons.face), label: 'Avatar'),
    BottomNavigationBarItem(icon: Icon(Icons.settings), label: '設置'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        items: _items,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

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
          debugPrint('ScanResult: id=[1m${result.device.remoteId.str}[22m, name="${result.advertisementData.advName}", rssi=${result.rssi}, manufacturerData=${result.advertisementData.manufacturerData}');
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

    // 檢查權限是否都已授權
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
    Future.delayed(const Duration(milliseconds: 300), () {
      // 重新啟動 app
      runApp(const MyApp());
    });
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    await FlutterBluePlus.startScan(); // 不設 timeout，持續掃描
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    setState(() => _isScanning = false);
  }

  Future<void> _connect(BluetoothDevice device) async {
    await device.connect();
    setState(() => _connectedDevice = device);
    _services = await device.discoverServices();
    setState(() {});
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
    // 寫入固定值範例，可根據需求修改
    await c.write([0x01]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已寫入 0x01')),
    );
  }

  Widget _buildAvatarFromManufacturer(Map<int, List<int>> manufacturerData) {
    if (manufacturerData.containsKey(0x1234)) {
      final bytes = Uint8List.fromList(manufacturerData[0x1234]!);
      if (bytes.length > 4 &&
          bytes[0] == 0x42 && bytes[1] == 0x4C && bytes[2] == 0x45 && bytes[3] == 0x41) {
        // magic bytes 符合才顯示頭像
        final avatarBytes = bytes.sublist(4);
        return CircleAvatar(radius: 20, backgroundImage: MemoryImage(avatarBytes));
      }
    }
    return const Icon(Icons.bluetooth);
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
              // 檢查藍牙狀態
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
          child: _scanResults.where((r) => r.advertisementData.advName.isNotEmpty).isEmpty
            ? const Center(child: Text('沒有人在這個地方QQ'))
            : ListView.builder(
                itemCount: _scanResults.where((r) => r.advertisementData.advName.isNotEmpty).length,
                itemBuilder: (_, i) {
                  final filteredResults = _scanResults.where((r) => r.advertisementData.advName.isNotEmpty).toList();
                  final r = filteredResults[i];
                  final name = r.advertisementData.advName;
                  return ListTile(
                    leading: _buildAvatarFromManufacturer(r.advertisementData.manufacturerData),
                    title: Text(name),
                    subtitle: Text(
                      'RSSI: ${r.rssi} dBm\n'
                      'ID: ${r.device.remoteId.str}\n'
                      'Manufacturer: '
                      '${r.advertisementData.manufacturerData.isNotEmpty ? r.advertisementData.manufacturerData : "無"}'
                    ),
                    trailing: ElevatedButton(
                      onPressed: () => _connect(r.device),
                      child: const Text('連接'),
                    ),
                  );
                },
              ),
        ),
    ]),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _nicknameController = TextEditingController();
  bool _isAdvertising = false;
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();
  Uint8List? _avatarThumbnailBytes; // 新增縮圖 bytes

  ImageProvider? get _avatarImage {
    return AvatarPage.currentAvatarImage ?? const AssetImage('assets/avatar_placeholder.png');
  }

  @override
  void initState() {
    super.initState();
    _prepareAvatarThumbnail();
  }

  Future<void> _prepareAvatarThumbnail() async {
    // 取得頭像縮圖 bytes，8x8 PNG
    final provider = _avatarImage;
    if (provider == null) return;
    final config = ImageConfiguration(size: const Size(80, 80));
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(config);
    void listener(ImageInfo info, bool _) {
      completer.complete(info.image);
      stream.removeListener(ImageStreamListener(listener));
    }
    stream.addListener(ImageStreamListener(listener));
    final image = await completer.future;
    final thumbnail = await image.toByteData(format: ui.ImageByteFormat.png);
    if (thumbnail != null) {
      // 只取前 20 bytes 當縮圖（實際應壓縮到 8x8，但這裡簡化）
      setState(() {
        _avatarThumbnailBytes = thumbnail.buffer.asUint8List().sublist(0, 20);
      });
    }
  }

  @override
  void dispose() {
    _blePeripheral.stop();
    _nicknameController.dispose();
    super.dispose();
  }

  void _toggleAdvertise(bool value) async {
    if (value) {
      await _prepareAvatarThumbnail();
      // magic bytes: [0x42, 0x4C, 0x45, 0x41] = 'BLEA'
      Uint8List? advData;
      if (_avatarThumbnailBytes != null) {
        advData = Uint8List(4 + _avatarThumbnailBytes!.length);
        advData.setAll(0, [0x42, 0x4C, 0x45, 0x41]);
        advData.setAll(4, _avatarThumbnailBytes!);
      }
      await _blePeripheral.start(
        advertiseData: AdvertiseData(
          includeDeviceName: true,
          localName: _nicknameController.text.isNotEmpty
              ? _nicknameController.text
              : null,
          manufacturerId: 0x1234, // 自訂廠商 ID
          manufacturerData: advData,
        ),
        advertiseResponseData: AdvertiseData(
          includeDeviceName: true,
          localName: _nicknameController.text.isNotEmpty
              ? _nicknameController.text
              : null,
        ),
      );
    } else {
      await _blePeripheral.stop();
    }
    setState(() => _isAdvertising = value);
  }

  TimeOfDay? _commuteStartMorning;
  TimeOfDay? _commuteEndMorning;
  TimeOfDay? _commuteStartEvening;
  TimeOfDay? _commuteEndEvening;

  Future<void> _pickTime(BuildContext context, TimeOfDay? initial, void Function(TimeOfDay) onPicked) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設置')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              reverse: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        if (_avatarImage != null) {
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              backgroundColor: Colors.transparent,
                              child: InteractiveViewer(
                                child: CircleAvatar(
                                  radius: 180,
                                  backgroundImage: _avatarImage,
                                ),
                              ),
                            ),
                          );
                        }
                      },
                      child: CircleAvatar(
                        radius: 80,
                        backgroundImage: _avatarImage,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('暱稱', style: TextStyle(fontSize: 16)),
                  TextField(
                    controller: _nicknameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '請輸入暱稱',
                    ),
                    onChanged: (v) {
                      if (_isAdvertising) {
                        _toggleAdvertise(false);
                        Future.delayed(const Duration(milliseconds: 300), () {
                          _toggleAdvertise(true);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('開啟被偵測 (BLE 廣播)', style: TextStyle(fontSize: 16)),
                      Switch(
                        value: _isAdvertising,
                        onChanged: (v) => _toggleAdvertise(v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('通勤時段設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('上班：'),
                      TextButton(
                        onPressed: () => _pickTime(context, _commuteStartMorning, (t) => setState(() => _commuteStartMorning = t)),
                        child: Text(_commuteStartMorning == null ? '開始時間' : _commuteStartMorning!.format(context)),
                      ),
                      const Text('~'),
                      TextButton(
                        onPressed: () => _pickTime(context, _commuteEndMorning, (t) => setState(() => _commuteEndMorning = t)),
                        child: Text(_commuteEndMorning == null ? '結束時間' : _commuteEndMorning!.format(context)),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('下班：'),
                      TextButton(
                        onPressed: () => _pickTime(context, _commuteStartEvening, (t) => setState(() => _commuteStartEvening = t)),
                        child: Text(_commuteStartEvening == null ? '開始時間' : _commuteStartEvening!.format(context)),
                      ),
                      const Text('~'),
                      TextButton(
                        onPressed: () => _pickTime(context, _commuteEndEvening, (t) => setState(() => _commuteEndEvening = t)),
                        child: Text(_commuteEndEvening == null ? '結束時間' : _commuteEndEvening!.format(context)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
      resizeToAvoidBottomInset: true,
    );
  }
}
