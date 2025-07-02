import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'avatar_utils.dart';
import 'dart:convert';
import 'dart:typed_data';

class SettingsBleHelper {

  static void Function(String nickname, String imageId, String deviceId)? _onConnectionRequestCallback;
  static final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();
  static bool _isListening = false;

  /// 註冊收到連接請求時的 callback
  static void setOnConnectionRequestCallback(void Function(String nickname, String imageId, String deviceId) callback) {
    debugPrint('[SettingsBleHelper] setOnConnectionRequestCallback called');
    _onConnectionRequestCallback = callback;
    _startListeningForConnections();
  }

  /// 開始監聽 BLE 連接
  static void _startListeningForConnections() async {
    if (_isListening) return;
    _isListening = true;
    
    debugPrint('[SettingsBleHelper] Started listening for BLE connections');
    
    // 監聽 FlutterBluePlus 的連接狀態變化
    FlutterBluePlus.events.onConnectionStateChanged.listen((event) {
      debugPrint('[SettingsBleHelper] Connection state changed: ${event.device.remoteId.str} -> ${event.connectionState}');
      
      if (event.connectionState == BluetoothConnectionState.connected) {
        // 有裝置連接到我們，觸發連接請求回調
        final deviceName = event.device.platformName.isNotEmpty 
            ? event.device.platformName 
            : 'Unknown Device';
        
        debugPrint('[SettingsBleHelper] Device connected: $deviceName (${event.device.remoteId.str})');
        
        // 觸發連接請求回調
        _onConnectionRequestCallback?.call(
          deviceName,
          '', // imageId - 可能需要從廣播數據中獲取
          event.device.remoteId.str
        );
      }
    });
    
    // 監聽掃描結果，檢查是否有人試圖連接我們
    FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        // 檢查是否有包含連接請求的廣播數據
        final manufacturerData = result.advertisementData.manufacturerData;
        if (manufacturerData.containsKey(0x1234)) {
          final bytes = manufacturerData[0x1234]!;
          if (bytes.length > 4 && 
              bytes[0] == 0x42 && bytes[1] == 0x4C && 
              bytes[2] == 0x45 && bytes[3] == 0x41) {
            
            // 解析暱稱
            final nameLen = bytes[4];
            if (bytes.length >= 5 + nameLen) {
              final nickname = utf8.decode(bytes.sublist(5, 5 + nameLen));
              
              debugPrint('[SettingsBleHelper] Detected potential connection request from: $nickname');
              
              // 這裡可以添加更多邏輯來處理連接請求
            }
          }
        }
      }
    });
  }
  
  /// 定期檢查是否有新的連接（暫時解決方案）
  // ...existing code...

  /// 模擬收到 BLE 連接請求（for UI 測試用）
  static void simulateIncomingConnection(String nickname, String imageId, String deviceId) {
    debugPrint('[SettingsBleHelper] simulateIncomingConnection called: nickname=$nickname, imageId=$imageId, deviceId=$deviceId');
    debugPrint('[SettingsBleHelper] _onConnectionRequestCallback is null: ${_onConnectionRequestCallback == null}');
    _onConnectionRequestCallback?.call(nickname, imageId, deviceId);
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

}
