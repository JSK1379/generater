import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:near_ride/features/chat/services/chat_service_singleton.dart';
import 'package:near_ride/features/profile/utils/avatar_utils.dart';

/// Near Ride BLE advertising helper.
///
/// Legacy payload markers are preserved:
/// BLEA = avatar bytes, BLEI = image id, BLEU = user id + image id.
class SettingsBleHelper {
  SettingsBleHelper._();

  static const int _maxPayloadBytes = 24;
  static final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  static void simulateIncomingConnection(
    String nickname,
    String imageId,
    String deviceId,
  ) {
    final chatService = ChatServiceSingleton.instance;
    chatService.getCurrentUserId().then((currentUserId) {
      chatService.triggerConnectRequest(deviceId, currentUserId);
    });
  }

  static Future<void> advertiseWithAvatar({
    required String nickname,
    required ImageProvider? avatarImageProvider,
    required bool enable,
  }) async {
    if (!enable) {
      await _peripheral.stop();
      return;
    }

    final nicknameBytes = _fitUtf8(
      nickname.isEmpty ? 'Unknown' : nickname,
      12,
    );
    var avatarBytes = avatarImageProvider == null
        ? <int>[]
        : (await AvatarUtils.compressAvatarImage(avatarImageProvider))?.toList() ??
            <int>[];

    final used = 4 + 1 + nicknameBytes.length + 1;
    final available = _availableBytes(used);
    avatarBytes = avatarBytes.take(available).toList();

    await _start(
      nickname: nickname,
      manufacturerId: 0x1234,
      bytes: <int>[
        0x42, 0x4C, 0x45, 0x41,
        nicknameBytes.length,
        ...nicknameBytes,
        avatarBytes.length,
        ...avatarBytes,
      ],
    );
  }

  static Future<void> advertiseWithImageId({
    required String nickname,
    required String imageId,
    required bool enable,
  }) async {
    if (!enable) {
      await _peripheral.stop();
      return;
    }

    final nicknameBytes = _fitUtf8(
      nickname.isEmpty ? 'Unknown' : nickname,
      12,
    );
    final used = 4 + 1 + nicknameBytes.length + 1;
    final imageBytes = _fitUtf8(imageId, _availableBytes(used));

    await _start(
      nickname: nickname,
      manufacturerId: 0x1235,
      bytes: <int>[
        0x42, 0x4C, 0x45, 0x49,
        nicknameBytes.length,
        ...nicknameBytes,
        imageBytes.length,
        ...imageBytes,
      ],
    );
  }

  static Future<void> advertiseWithUserId({
    required String nickname,
    required String userId,
    required String imageId,
    required bool enable,
  }) async {
    if (!enable) {
      await _peripheral.stop();
      return;
    }

    final nicknameBytes = _fitUtf8(
      nickname.isEmpty ? 'Unknown' : nickname,
      8,
    );
    final userBytes = _fitUtf8(userId, 8);
    final used = 4 + 1 + nicknameBytes.length + 1 + userBytes.length + 1;
    final imageBytes = _fitUtf8(imageId, _availableBytes(used));

    await _start(
      nickname: nickname,
      manufacturerId: 0x1236,
      bytes: <int>[
        0x42, 0x4C, 0x45, 0x55,
        nicknameBytes.length,
        ...nicknameBytes,
        userBytes.length,
        ...userBytes,
        imageBytes.length,
        ...imageBytes,
      ],
    );
  }

  static int _availableBytes(int used) {
    final remaining = _maxPayloadBytes - used;
    return remaining > 0 ? remaining : 0;
  }

  static Future<void> _start({
    required String nickname,
    required int manufacturerId,
    required List<int> bytes,
  }) async {
    assert(bytes.length <= _maxPayloadBytes);
    if (kDebugMode) {
      debugPrint('[BLE] advertising $manufacturerId payload=${bytes.length} bytes');
    }
    await _peripheral.start(
      advertiseData: AdvertiseData(
        localName: nickname,
        manufacturerId: manufacturerId,
        manufacturerData: Uint8List.fromList(bytes),
        includeDeviceName: true,
      ),
    );
  }

  static List<int> _fitUtf8(String value, int maxBytes) {
    if (maxBytes <= 0 || value.isEmpty) return <int>[];
    final result = <int>[];
    for (final rune in value.runes) {
      final bytes = utf8.encode(String.fromCharCode(rune));
      if (result.length + bytes.length > maxBytes) break;
      result.addAll(bytes);
    }
    return result;
  }
}
