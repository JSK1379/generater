import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleScanHelper {
  BleScanHelper._();

  /// Scans for Near Ride BLEI advertisements and yields validated payloads.
  static Stream<BleDeviceInfo> scanNearbyDevices() async* {
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    try {
      await for (final result
          in FlutterBluePlus.scanResults.expand((items) => items)) {
        for (final data in result.advertisementData.manufacturerData.values) {
          final parsed = _parseImageIdPayload(
            data,
            deviceId: result.device.remoteId.str,
            rssi: result.rssi,
          );
          if (parsed != null) {
            yield parsed;
            break;
          }
        }
      }
    } finally {
      await FlutterBluePlus.stopScan();
    }
  }

  static BleDeviceInfo? _parseImageIdPayload(
    List<int> data, {
    required String deviceId,
    required int rssi,
  }) {
    // BLEI + nickname length + nickname + imageId length + imageId.
    if (data.length < 6 ||
        data[0] != 0x42 ||
        data[1] != 0x4C ||
        data[2] != 0x45 ||
        data[3] != 0x49) {
      return null;
    }

    final nicknameLength = data[4];
    final nicknameStart = 5;
    final nicknameEnd = nicknameStart + nicknameLength;
    if (nicknameEnd >= data.length) return null;

    final imageIdLength = data[nicknameEnd];
    final imageIdStart = nicknameEnd + 1;
    final imageIdEnd = imageIdStart + imageIdLength;
    if (imageIdEnd > data.length) return null;

    try {
      return BleDeviceInfo(
        deviceId: deviceId,
        nickname: utf8.decode(data.sublist(nicknameStart, nicknameEnd)),
        imageId: utf8.decode(data.sublist(imageIdStart, imageIdEnd)),
        rssi: rssi,
      );
    } on FormatException {
      return null;
    }
  }
}

class BleDeviceInfo {
  const BleDeviceInfo({
    required this.deviceId,
    required this.nickname,
    required this.imageId,
    required this.rssi,
  });

  final String deviceId;
  final String nickname;
  final String imageId;
  final int rssi;
}
