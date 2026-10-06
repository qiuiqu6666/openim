import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'dart:convert';

/// Notification avatars are small PNGs; downloading never delays the banner.
class MessageNotificationAvatarCache {
  MessageNotificationAvatarCache({Future<File> Function(String)? fetch})
      : _fetch = fetch ?? DefaultCacheManager().getSingleFile;

  final Future<File> Function(String) _fetch;
  final Map<String, Future<String?>> _pending = {};

  Future<String?> resolve(String? url) {
    final uri = Uri.tryParse(url ?? '');
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return Future.value();
    }
    final key = uri.toString();
    return _pending.putIfAbsent(
        key,
        () => _load(key).whenComplete(() {
              _pending.remove(key);
            }));
  }

  Future<String?> _load(String url) async {
    try {
      final source = await _fetch(url).timeout(const Duration(seconds: 3));
      final stat = await source.stat();
      if (stat.size > 4 * 1024 * 1024) return null;
      final fingerprint =
          '$url|${source.path}|${stat.modified.microsecondsSinceEpoch}|${stat.size}';
      final file = File('${source.parent.path}/notification-avatar-'
          '${sha256.convert(utf8.encode(fingerprint))}.png');
      if (await file.exists()) return file.path;
      final bytes = await source.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes,
          targetWidth: 128, targetHeight: 128, allowUpscaling: false);
      try {
        final frame = await codec.getNextFrame();
        try {
          final png =
              await frame.image.toByteData(format: ui.ImageByteFormat.png);
          if (png == null) return null;
          await file.writeAsBytes(png.buffer.asUint8List(), flush: false);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      return file.path;
    } catch (_) {
      return null; // Keep the platform icon on invalid or unavailable avatars.
    }
  }
}
