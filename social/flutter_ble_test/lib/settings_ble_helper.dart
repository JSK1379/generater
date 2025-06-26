import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter/material.dart';
import 'avatar_utils.dart';
import 'dart:convert';
import 'dart:typed_data';

class SettingsBleHelper {
  static final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  static Future<void> advertiseWithAvatar({
    required String nickname,
    required ImageProvider? avatarImageProvider,
    required bool enable,
  }) async {
    if (!enable) {
      await _blePeripheral.stop();
      return;
    }
    final nicknameBytes = utf8.encode(nickname.isEmpty ? 'Unknown' : nickname);
    Uint8List? avatarBytes;
    if (avatarImageProvider != null) {
      avatarBytes = await AvatarUtils.compressAvatarImage(avatarImageProvider);
    }
    debugPrint('avatarBytes: $avatarBytes, length: \\${avatarBytes?.length}');
    int maxTotal = 24;
    int used = 4 + 1 + nicknameBytes.length + 1;
    int avatarLen = avatarBytes != null ? avatarBytes.length : 0;
    if (used + avatarLen > maxTotal) {
      int allowed = maxTotal - used;
      if (allowed < 0) allowed = 0;
      if (avatarBytes != null && avatarBytes.length > allowed) {
        avatarBytes = avatarBytes.sublist(0, allowed);
      }
    }
    final List<int> manufacturerData = [0x42, 0x4C, 0x45, 0x41];
    manufacturerData.add(nicknameBytes.length);
    manufacturerData.addAll(nicknameBytes);
    if (avatarBytes != null && avatarBytes.isNotEmpty) {
      manufacturerData.add(avatarBytes.length);
      manufacturerData.addAll(avatarBytes);
    } else {
      manufacturerData.add(0);
    }
    debugPrint('廣播 manufacturerData: \\${manufacturerData.toString()}, 長度: \\${manufacturerData.length}');
    final advertiseData = AdvertiseData(
      localName: nickname,
      manufacturerId: 0x1234,
      manufacturerData: Uint8List.fromList(manufacturerData),
      includeDeviceName: true,
    );
    debugPrint('Start BLE advertise, localName: $nickname');
    await _blePeripheral.start(advertiseData: advertiseData);
  }
}
