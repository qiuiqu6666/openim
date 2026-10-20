import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:openim_common/media_recognition.dart';

/// A scan owns only its temporary file/socket, never a message attachment.
class MediaImageFile {
  static const maxBytes = 32 * 1024 * 1024;
  Directory? _temporary;
  HttpClient? _client;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  void check() {
    if (_cancelled) throw StateError('cancelled');
  }

  Future<File> resolve(MediaSource source) async {
    check();
    final local = source.file;
    if (local != null && await local.exists()) {
      if (await local.length() > maxBytes) throw StateError('tooLarge');
      check();
      return local;
    }
    if (source.bytes != null) return _write(source.bytes!);
    final url = [source.url, source.previewUrl, source.thumbnail]
        .whereType<String>().firstWhere((value) => value.trim().isNotEmpty,
            orElse: () => '');
    final cached = await DefaultCacheManager().getFileFromCache(url);
    check();
    if (cached != null && await cached.file.exists()) {
      if (await cached.file.length() > maxBytes) throw StateError('tooLarge');
      return cached.file;
    }
    final bytes = await SharedImageDiskCache().read(url);
    check();
    if (bytes != null) return _write(bytes);
    final uri = Uri.parse(url);
    if (!['http', 'https'].contains(uri.scheme)) {
      throw StateError('invalidImage');
    }
    final client =
        _client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok ||
          response.contentLength > maxBytes) {
        throw StateError('imageUnavailable');
      }
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        check();
        if (buffer.length + chunk.length > maxBytes) {
          throw StateError('tooLarge');
        }
        buffer.add(chunk);
      }
      return await _write(buffer.takeBytes());
    } finally {
      client.close(force: true);
    }
  }

  Future<File> _write(Uint8List bytes) async {
    check();
    if (bytes.length > maxBytes) throw StateError('tooLarge');
    _temporary = await Directory.systemTemp.createTemp('media-recognition-');
    check();
    return File('${_temporary!.path}/image').writeAsBytes(bytes);
  }

  Future<void> dispose() async {
    cancel();
    final directory = _temporary;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
