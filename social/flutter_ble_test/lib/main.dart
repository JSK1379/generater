import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'avatar_page.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

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
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
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

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('BLE 掃描 + 裝置列表')),
    body: Column(children: [
      if (_connectedDevice != null)
        Text('已連接：${_connectedDevice!.platformName.isNotEmpty ? _connectedDevice!.platformName : _connectedDevice!.remoteId.str}')
      else
        Text('藍牙狀態：${_btState?.name.toUpperCase() ?? 'UNKNOWN'}'),
      if (_btState != BluetoothAdapterState.on)
        ElevatedButton(
          onPressed: () async {
            await FlutterBluePlus.turnOn();
          },
          child: const Text('開啟藍牙'),
        )
      else
        ElevatedButton(
          onPressed: _isScanning ? null : _startScan,
          child: Text(_isScanning ? '掃描中…' : '開始掃描'),
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
          child: _scanResults.isEmpty
            ? const Center(child: Text('尚未掃描到任何裝置。'))
            : ListView.builder(
                itemCount: _scanResults.where((r) => r.advertisementData.advName.isNotEmpty).length,
                itemBuilder: (_, i) {
                  final filteredResults = _scanResults.where((r) => r.advertisementData.advName.isNotEmpty).toList();
                  final r = filteredResults[i];
                  final name = r.advertisementData.advName;
                  return ListTile(
                    leading: const Icon(Icons.bluetooth),
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

  @override
  void dispose() {
    _blePeripheral.stop();
    _nicknameController.dispose();
    super.dispose();
  }

  void _toggleAdvertise(bool value) async {
    if (value) {
      await _blePeripheral.start(
        advertiseData: AdvertiseData(
          includeDeviceName: true,
          localName: _nicknameController.text.isNotEmpty
              ? _nicknameController.text
              : null, // BLE Complete Local Name
        ),
        advertiseResponseData: AdvertiseData(
          includeDeviceName: true,
          localName: _nicknameController.text.isNotEmpty
              ? _nicknameController.text
              : null, // BLE Scan Response Data
        ),
      );
    } else {
      await _blePeripheral.stop();
    }
    setState(() => _isAdvertising = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設置')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
          ],
        ),
      ),
    );
  }
}
