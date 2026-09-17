import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'avatar_utils.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'chat_service_singleton.dart'; // 添加這一行

class SettingsBleHelper {

  static final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  /// 模擬收到 BLE 連接請求（for UI 測試用）
  static void simulateIncomingConnection(String nickname, String imageId, String deviceId) {
    debugPrint('[SettingsBleHelper] simulateIncomingConnection called: nickname=$nickname, imageId=$imageId, deviceId=$deviceId');
    
    // 使用 ChatServiceSingleton 直接觸發連接請求
    final chatService = ChatServiceSingleton.instance;
    // 獲取當前用戶 ID
    chatService.getCurrentUserId().then((currentUserId) {
      // 使用公共方法觸發連接請求
      chatService.triggerConnectRequest(deviceId, currentUserId);
    });
  }

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

  static Future<void> advertiseWithImageId({
    required String nickname,
    required String imageId,
    required bool enable,
  }) async {
    if (!enable) {
      await _blePeripheral.stop();
      return;
    }
    final nicknameBytes = utf8.encode(nickname.isEmpty ? 'Unknown' : nickname);
    List<int> imageIdBytes = utf8.encode(imageId);
    int maxTotal = 24;
    int used = 4 + 1 + nicknameBytes.length + 1;
    int imageIdLen = imageIdBytes.length;
    if (used + imageIdLen > maxTotal) {
      int allowed = maxTotal - used;
      if (allowed < 0) allowed = 0;
      if (imageIdBytes.length > allowed) {
        imageIdBytes = imageIdBytes.sublist(0, allowed);
      }
    }
    final List<int> manufacturerData = [0x42, 0x4C, 0x45, 0x49]; // BLEI
    manufacturerData.add(nicknameBytes.length);
    manufacturerData.addAll(nicknameBytes);
    manufacturerData.add(imageIdBytes.length);
    manufacturerData.addAll(imageIdBytes);
    debugPrint('廣播 imageId manufacturerData: \\${manufacturerData.toString()}, 長度: \\${manufacturerData.length}');
    final advertiseData = AdvertiseData(
      localName: nickname,
      manufacturerId: 0x1235,
      manufacturerData: Uint8List.fromList(manufacturerData),
      includeDeviceName: true,
    );
    debugPrint('Start BLE advertise with imageId, localName: $nickname, imageId: $imageId');
    await _blePeripheral.start(advertiseData: advertiseData);
  }

  /// 帶有 userId 的廣播方法
  static Future<void> advertiseWithUserId({
    required String nickname,
    required String userId,
    required String imageId,
    required bool enable,
  }) async {
    if (!enable) {
      await _blePeripheral.stop();
      return;
    }
    
    final nicknameBytes = utf8.encode(nickname.isEmpty ? 'Unknown' : nickname);
    final userIdBytes = utf8.encode(userId);
    List<int> imageIdBytes = utf8.encode(imageId);
    
    // 計算可用空間: 總共24字節 - 頭部(4字節) - nickname長度(1字節) - userId長度(1字節) - imageId長度(1字節)
    int maxTotal = 24;
    int headerSize = 4 + 1 + 1 + 1; // BLEU + nickname_len + userId_len + imageId_len
    int used = headerSize + nicknameBytes.length + userIdBytes.length;
    
    // 如果 imageId 太長，則截斷
    if (used + imageIdBytes.length > maxTotal) {
      int allowed = maxTotal - used;
      if (allowed < 0) allowed = 0;
      if (imageIdBytes.length > allowed) {
        imageIdBytes = imageIdBytes.sublist(0, allowed);
      }
    }
    
    final List<int> manufacturerData = [0x42, 0x4C, 0x45, 0x55]; // BLEU (BLE User)
    manufacturerData.add(nicknameBytes.length);
    manufacturerData.addAll(nicknameBytes);
    manufacturerData.add(userIdBytes.length);
    manufacturerData.addAll(userIdBytes);
    manufacturerData.add(imageIdBytes.length);
    manufacturerData.addAll(imageIdBytes);
    
    debugPrint('[SettingsBleHelper] 廣播 userId manufacturerData: ${manufacturerData.toString()}, 長度: ${manufacturerData.length}');
    debugPrint('[SettingsBleHelper] 廣播內容 - nickname: $nickname, userId: $userId, imageId: $imageId');
    
    final advertiseData = AdvertiseData(
      localName: nickname,
      manufacturerId: 0x1236, // 使用新的 manufacturer ID
      manufacturerData: Uint8List.fromList(manufacturerData),
      includeDeviceName: true,
    );
    
    debugPrint('[SettingsBleHelper] Start BLE advertise with userId, localName: $nickname, userId: $userId, imageId: $imageId');
    await _blePeripheral.start(advertiseData: advertiseData);
  }

}
