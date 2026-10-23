import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Fixed send-time renditions; no device-dependent resize/cache keys.
class ChatPictureRendition {
  ChatPictureRendition(
      this.path, this.width, this.height, this.length, this.type);
  final String path, type;
  final int width, height, length;
}

class ChatPictureRenditions {
  ChatPictureRenditions(this.directory, this.thumbnail, this.preview);
  final String directory;
  final ChatPictureRendition thumbnail, preview;

  Future<void> dispose() async {
    for (final item in [thumbnail, preview]) {
      final file = File(item.path);
      if (await file.exists()) await file.delete();
    }
    final dir = Directory(directory);
    if (await dir.exists()) await dir.delete();
  }

  static Future<void> _tail = Future<void>.value();
  static Future<ChatPictureRenditions?> create(String path,
      {bool Function()? isCancelled}) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      if (isCancelled?.call() == true) return null;
      final result =
          await compute(_create, path, debugLabel: 'chat picture renditions');
      if (isCancelled?.call() == true) {
        await result?.dispose();
        return null;
      }
      return result;
    } finally {
      done.complete();
    }
  }
}

Future<ChatPictureRenditions?> _create(String path) async {
  Directory? directory;
  try {
    final file = File(path);
    if (await file.length() > 32 * 1024 * 1024) return null;
    final bytes = await file.readAsBytes();
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width * info.height > 32 * 1024 * 1024) {
      return null;
    }
    // Animated sources keep their original; previews show only the first frame.
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) return null;
    final source = img.bakeOrientation(decoded);
    directory = await Directory.systemTemp.createTemp('chat-renditions-');
    Future<ChatPictureRendition> render(int bound) async {
      final scale =
          math.min(1.0, bound / math.max(source.width, source.height));
      final image = img.copyResize(source,
          width: math.max(1, (source.width * scale).round()),
          height: math.max(1, (source.height * scale).round()),
          interpolation: img.Interpolation.average);
      image.exif = img.ExifData();
      image.textData = null;
      final alpha = image.hasAlpha;
      final data =
          alpha ? img.encodePng(image) : img.encodeJpg(image, quality: 80);
      final output = File('${directory!.path}/$bound.${alpha ? 'png' : 'jpg'}');
      await output.writeAsBytes(data, flush: true);
      return ChatPictureRendition(output.path, image.width, image.height,
          data.length, alpha ? 'image/png' : 'image/jpeg');
    }

    final thumbnail = await render(640);
    final preview = await render(1600);
    return ChatPictureRenditions(directory.path, thumbnail, preview);
  } catch (_) {
    // Only files within this worker's newly-created directory are cleaned up.
    if (directory != null) {
      await for (final file in directory.list()) {
        if (file is File) await file.delete();
      }
      await directory.delete();
    }
    return null;
  }
}
