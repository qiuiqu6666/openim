import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:openim_common/openim_common.dart';

/// A send-time derivative, never a replacement for the full-size attachment.
class ChatTopPicturePreview {
  ChatTopPicturePreview(this.path, this.width, this.height, this.length);
  final String path;
  final int width, height, length;

  Future<void> dispose() async {
    final file = File(path);
    try {
      await file.delete();
      await file.parent.delete();
    } on FileSystemException {
      // A system cache cleanup may have already removed this owned directory.
    }
  }

  // Only one CPU-heavy preparation at a time, including overlapping albums.
  static Future<void> _tail = Future<void>.value();

  static Future<ChatTopPicturePreview?> create(String path,
      {required bool Function() isCancelled}) async {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    await previous;
    try {
      if (isCancelled()) return null;
      final preview =
          await compute(_prepare, path, debugLabel: 'chat top picture preview');
      if (isCancelled()) {
        await preview?.dispose();
        return null;
      }
      return preview;
    } finally {
      released.complete();
    }
  }
}

Future<ChatTopPicturePreview?> _prepare(String path) async {
  Directory? output;
  try {
    final source = File(path);
    // Unsupported/oversized sources retain the established full-image path.
    if (await source.length() > 32 * 1024 * 1024) return null;
    final bytes = await source.readAsBytes();
    final decoder = img.findDecoderForData(bytes);
    if (decoder is img.GifDecoder) return null;
    final info = decoder?.startDecode(bytes);
    if (info == null ||
        info.numFrames != 1 ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width * info.height > 32 * 1024 * 1024) {
      return null;
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) return null;
    final oriented = decoded.exif.imageIfd.hasOrientation &&
            decoded.exif.imageIfd.orientation != 1
        ? img.bakeOrientation(decoded)
        : decoded;
    if (oriented.height <=
        oriented.width * ChatPicturePreviewMetadata.heightRatio) {
      return null;
    }
    final top = img.copyCrop(oriented,
        x: 0,
        y: 0,
        width: oriented.width,
        height:
            (oriented.width * ChatPicturePreviewMetadata.heightRatio).round());
    final width = math.min(top.width, ChatPicturePreviewMetadata.maxWidth);
    final resized = img.copyResize(top,
        width: width, interpolation: img.Interpolation.average);
    resized.textData = null;
    resized.exif = img.ExifData();
    // PNG preserves screenshot text edges and transparency without JPEG noise.
    final encoded = img.encodePng(resized);
    output = await Directory.systemTemp.createTemp('chat-top-preview-');
    final file = File('${output.path}/preview.png');
    await file.writeAsBytes(encoded, flush: true);
    return ChatTopPicturePreview(
        file.path, resized.width, resized.height, encoded.length);
  } catch (_) {
    // A preview failure must not prevent sending the original attachment.
    if (output != null) {
      try {
        final file = File('${output.path}/preview.png');
        if (await file.exists()) await file.delete();
        await output.delete();
      } on FileSystemException {
        // Best-effort cleanup of this worker's uniquely owned output only.
      }
    }
    return null;
  }
}
