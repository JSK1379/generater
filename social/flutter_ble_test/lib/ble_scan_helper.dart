import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';

class BleScanHelper {
  // 啟動 BLE 掃描，並回傳附近裝置的暱稱與 imageId
  static Stream<BleDeviceInfo> scanNearbyDevices() async* {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    await for (final scanResult in FlutterBluePlus.scanResults.expand((x) => x)) {
      final adv = scanResult.advertisementData;
      final manufacturerData = adv.manufacturerData;
      if (manufacturerData.isNotEmpty) {
        final entry = manufacturerData.entries.first;
        final data = entry.value;
        if (data.length >= 6) {
          // 判斷是 imageId 廣播
          if (data[0] == 0x42 && data[1] == 0x4C && data[2] == 0x45 && data[3] == 0x49) {
            final nicknameLen = data[4];
            final nickname = utf8.decode(data.sublist(5, 5 + nicknameLen));
            final imageIdLen = data[5 + nicknameLen];
            final imageId = utf8.decode(data.sublist(6 + nicknameLen, 6 + nicknameLen + imageIdLen));
            yield BleDeviceInfo(
              deviceId: scanResult.device.remoteId.str,
              nickname: nickname,
              imageId: imageId,
              rssi: scanResult.rssi,
            );
          }
        }
      }
    }
    await FlutterBluePlus.stopScan();
  }
}

class BleDeviceInfo {
  final String deviceId;
  final String nickname;
  final String imageId;
  final int rssi;
  BleDeviceInfo({
    required this.deviceId,
    required this.nickname,
    required this.imageId,
    required this.rssi,
  });
}
