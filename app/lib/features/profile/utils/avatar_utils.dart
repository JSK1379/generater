import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AvatarUtils {
  AvatarUtils._();

  /// Downscales an avatar to 8x8 PNG and returns up to the first 64 bytes for
  /// the legacy BLE avatar payload.
  static Future<Uint8List?> compressAvatarImage(ImageProvider provider) async {
    const configuration = ImageConfiguration(size: Size(80, 80));
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(configuration);

    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) {
          completer.complete(info.image);
        }
        stream.removeListener(listener);
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);

    try {
      final image = await completer.future;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        const Rect.fromLTWH(0, 0, 8, 8),
        Paint(),
      );
      final smallImage = await recorder.endRecording().toImage(8, 8);
      final data = await smallImage.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      final bytes = data.buffer.asUint8List();
      final result = bytes.length > 64 ? bytes.sublist(0, 64) : bytes;
      if (kDebugMode) {
        debugPrint('[AvatarUtils] BLE avatar payload bytes: ${result.length}');
      }
      return result;
    } catch (error) {
      debugPrint('[AvatarUtils] compression failed: $error');
      return null;
    }
  }
}
