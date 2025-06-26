import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class AvatarUtils {
  /// 將 ImageProvider 壓縮成 8x8 PNG 並回傳前 12 bytes
  static Future<Uint8List?> compressAvatarImage(ImageProvider provider) async {
    const config = ImageConfiguration(size: Size(80, 80));
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(config);
    void listener(ImageInfo info, bool _) {
      completer.complete(info.image);
      stream.removeListener(ImageStreamListener(listener));
    }
    stream.addListener(ImageStreamListener(listener));
    final image = await completer.future;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      const Rect.fromLTWH(0, 0, 8, 8),
      paint,
    );
    final smallImage = await recorder.endRecording().toImage(8, 8);
    final byteData = await smallImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      final bytes = byteData.buffer.asUint8List();
      debugPrint('compressAvatarImage: bytes.length = \\${bytes.length}, bytes = \\${bytes.sublist(0, bytes.length > 24 ? 24 : bytes.length)}');
      return bytes.length > 12 ? bytes.sublist(0, 12) : bytes;
    }
    debugPrint('compressAvatarImage: byteData is null');
    return null;
  }
}
