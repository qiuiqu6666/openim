import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Reuse downloaded chat videos when the viewer is opened again.
class VideoMediaCache {
  VideoMediaCache._();

  static final CacheManager _manager = DefaultCacheManager();
  static final Map<String, Future<void>> _downloads = {};
  static final Map<String, File> _hotFiles = {};

  static Future<File?> cachedFile(String url) async {
    try {
      final hot = _hotFiles[url];
      if (hot != null && await hot.exists()) return hot;
      final info = await _manager.getFileFromCache(url);
      if (info != null && await info.file.exists()) {
        _hotFiles[url] = info.file;
        return info.file;
      }
    } catch (_) {
      // Streaming still works if the cache is unavailable.
    }
    return null;
  }

  static Future<void> remember(String url) =>
      _downloads.putIfAbsent(url, () async {
        try {
          final info = await _manager.downloadFile(url);
          _hotFiles[url] = info.file;
        } catch (_) {
          // Playback uses the network source when the download fails.
        } finally {
          _downloads.remove(url);
        }
      });
}
