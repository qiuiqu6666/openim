import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../utils/media/native_media_file.dart';

/// Reuse downloaded chat videos when the viewer is opened again.
class VideoMediaCache {
  VideoMediaCache._();

  static final CacheManager _manager = DefaultCacheManager();

  static Future<File?> cachedFile(String url) async {
    try {
      final info = await _manager.getFileFromCache(url);
      if (info != null && await info.file.exists()) {
        return info.file;
      }
    } catch (_) {
      // Streaming still works if the cache is unavailable.
    }
    return null;
  }

  /// iOS can reject streaming when an object server has incorrect media
  /// headers or no byte-range support. A complete local file avoids that.
  static Future<File> downloadForPlayback(String url,
      {Map<String, String> headers = const {}, bool refresh = false}) async {
    // Header-bearing requests must not reuse another account's cached source.
    final entries = headers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final key = headers.isEmpty
        ? url
        : 'video-auth:${sha256.convert(utf8.encode(jsonEncode([
                url,
                for (final entry in entries) [entry.key, entry.value],
              ])))}';
    final file = refresh
        ? (await _manager.downloadFile(url,
                key: key, authHeaders: headers, force: true))
            .file
        : await _manager.getSingleFile(url, key: key, headers: headers);
    if (await file.length() == 0) throw StateError('Empty video');
    return NativeMediaFile.prepare(file);
  }
}
