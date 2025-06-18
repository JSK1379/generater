import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MaterialApp(home: BleScanBody()));
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

  @override
  void initState() {
    super.initState();
    _requestPermissions().then((_) {
      FlutterBluePlus.adapterState.listen((s) {
        setState(() => _btState = s);
      });
      FlutterBluePlus.onScanResults.listen((r) {
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

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('BLE 掃描 + 裝置列表')),
    body: Column(children: [
      Text('藍牙: ${_btState?.name.toUpperCase() ?? 'UNKNOWN'}'),
      ElevatedButton(
        onPressed: _isScanning ? null : _startScan,
        child: Text(_isScanning ? '掃描中…' : '開始掃描'),
      ),
      Expanded(
        child: _scanResults.isEmpty
          ? const Center(child: Text('尚未掃描到任何裝置。'))
          : ListView.builder(
              itemCount: _scanResults.length,
              itemBuilder: (_, i) {
                final r = _scanResults[i];
                final name = r.device.name.isNotEmpty
                  ? r.device.name : r.device.id.id;
                return ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(name),
                  subtitle: Text('RSSI: ${r.rssi} dBm'),
                );
              },
            ),
      ),
    ]),
  );
}
