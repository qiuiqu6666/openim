import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:mime/mime.dart';

/// AVFoundation uses the local extension; generic HTTP caches may save M4A or
/// MP4 data as .bin. Keep originals intact and let the shared cache own copies.
class NativeMediaFile {
  NativeMediaFile._();

  static final Map<String, Future<File>> _pending = {};

  static Future<File> prepare(File file) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return file;
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file || stat.size == 0) return file;
      final input = await file.open();
      late final List<int> header;
      try {
        header = await input.read(64);
      } finally {
        await input.close();
      }
      final extension = extensionForHeader(header);
      if (extension == null ||
          file.path.toLowerCase().endsWith('.$extension')) {
        return file;
      }
      final fingerprint = jsonEncode([
        file.absolute.path,
        stat.size,
        stat.modified.microsecondsSinceEpoch,
        extension,
      ]);
      final key = 'native-media-v1:${sha256.convert(utf8.encode(fingerprint))}';
      return await _pending.putIfAbsent(key, () async {
        try {
          final cache = DefaultCacheManager();
          final cached = await cache.getFileFromCache(key);
          if (cached != null && await cached.file.length() == stat.size) {
            return cached.file;
          }
          return await cache.putFileStream(key, file.openRead(),
              fileExtension: extension);
        } finally {
          _pending.remove(key);
        }
      });
    } catch (_) {
      // A cache/copy failure must not prevent a usable original from playing.
      return file;
    }
  }

  static String? extensionForHeader(List<int> header) {
    if (header.length >= 12 &&
        ascii.decode(header.sublist(4, 8), allowInvalid: true) == 'ftyp') {
      final brand = ascii.decode(header.sublist(8, 12), allowInvalid: true);
      if (brand == 'M4A ' || brand == 'M4B ') return 'm4a';
      if (brand == 'qt  ') return 'mov';
      if (const {'isom', 'iso2', 'iso5', 'iso6', 'mp41', 'mp42', 'avc1', 'M4V '}
          .contains(brand)) {
        return 'mp4';
      }
    }
    // Sniff content only. A URL suffix must not turn an HTML error or an
    // unknown/unsupported container into a supposed audio/video file.
    return switch (lookupMimeType('', headerBytes: header)) {
      'audio/mpeg' => 'mp3',
      'audio/aac' => 'aac',
      'audio/x-wav' || 'audio/wav' => 'wav',
      'audio/mp4' => 'm4a',
      'video/mp4' => 'mp4',
      'video/quicktime' => 'mov',
      _ => null,
    };
  }
}
