import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../native_media_file.dart';

enum VideoGalleryResult {
  success,
  permissionDenied,
  downloadFailed,
  invalidVideo,
  failed,
  timedOut,
  canceled,
  unsupported,
  writing,
}

/// One preview owns one save operation. Downloads stream to an isolated file;
/// only a completed, nonempty video is handed to the native gallery API.
class VideoGallerySaver {
  VideoGallerySaver({
    Dio? client,
    Future<bool> Function()? requestPermission,
    Future<dynamic> Function(String path)? saveFile,
    Future<Directory> Function()? tempDirectory,
    this.timeout = const Duration(minutes: 5),
    this.nativeTimeout = const Duration(seconds: 90),
  })  : _client = client ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 30))),
        _requestPermission = requestPermission ?? _permission,
        _saveFile =
            saveFile ?? ((path) => ImageGallerySaverPlus.saveFile(path)),
        _tempDirectory = tempDirectory ?? getTemporaryDirectory;

  final Dio _client;
  final Future<bool> Function() _requestPermission;
  final Future<dynamic> Function(String) _saveFile;
  final Future<Directory> Function() _tempDirectory;
  final Duration timeout, nativeTimeout;
  Future<VideoGalleryResult>? _pending;
  CancelToken? _cancel;
  bool _disposed = false;
  static bool _nativeWriting = false;

  Future<VideoGalleryResult> save({
    File? file,
    String? url,
    Uint8List? bytes,
    required bool Function() isCurrent,
    CancelToken? cancelToken,
    VoidCallback? onWriting,
    void Function(int count, int total)? onProgress,
  }) {
    if (_disposed) return Future.value(VideoGalleryResult.canceled);
    if (_pending != null) return _pending!;
    if (_nativeWriting) return Future.value(VideoGalleryResult.writing);
    final token = _cancel = cancelToken ?? CancelToken();
    bool current() => !_disposed && !token.isCancelled && isCurrent();
    late final Future<VideoGalleryResult> work;
    work = _run(file, url, bytes, token, current, onProgress, onWriting)
        .timeout(timeout, onTimeout: () {
      token.cancel();
      return VideoGalleryResult.timedOut;
    }).whenComplete(() {
      if (identical(_pending, work)) _pending = null;
    });
    return _pending = work;
  }

  Future<VideoGalleryResult> _run(
      File? file,
      String? url,
      Uint8List? bytes,
      CancelToken token,
      bool Function() current,
      void Function(int, int)? progress,
      VoidCallback? onWriting) async {
    Directory? staging;
    var nativeOwnsFile = false;
    try {
      if (!current()) return VideoGalleryResult.canceled;
      if (!await _requestPermission()) {
        return VideoGalleryResult.permissionDenied;
      }
      if (!current()) return VideoGalleryResult.canceled;
      staging = await (await _tempDirectory()).createTemp('video-save-');
      if (!current()) return VideoGalleryResult.canceled;
      File? source;
      if (file != null && await file.exists() && await file.length() > 0) {
        source = file;
      } else if (bytes != null && bytes.isNotEmpty) {
        source = await File('${staging.path}/source').writeAsBytes(bytes);
      } else {
        final uri = Uri.tryParse(url ?? '');
        if (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          return VideoGalleryResult.downloadFailed;
        }
        source = File('${staging.path}/source');
        // Do not derive a filename from a signed URL or rely on count==total:
        // chunked responses legitimately report an unknown total length.
        await _client.download(url!, source.path, cancelToken: token,
            onReceiveProgress: (count, total) {
          if (current()) progress?.call(count, total);
        });
      }
      if (!current()) return VideoGalleryResult.canceled;
      final input = await source.open();
      late final List<int> header;
      try {
        header = await input.read(64);
      } finally {
        await input.close();
      }
      final ext = NativeMediaFile.extensionForHeader(header) ??
          switch (lookupMimeType('', headerBytes: header)) {
            'video/webm' => 'webm',
            'video/x-msvideo' => 'avi',
            'video/mpeg' => 'mpeg',
            _ => null,
          };
      if (!const {'mp4', 'mov', 'webm', 'avi', 'mpeg'}.contains(ext)) {
        return VideoGalleryResult.invalidVideo;
      }
      final output = await source.copy('${staging.path}/video.$ext');
      if (!current()) return VideoGalleryResult.canceled;
      if (_nativeWriting) return VideoGalleryResult.writing;
      onWriting?.call();
      // Keep the staging file until native writing actually completes, even
      // when our UI times out or the preview closes in the meantime.
      final ownedDirectory = staging;
      _nativeWriting = true;
      final native =
          Future.sync(() => _saveFile(output.path)).whenComplete(() async {
        _nativeWriting = false;
        await _cleanup(ownedDirectory);
      });
      nativeOwnsFile = true;
      final result = await native.timeout(nativeTimeout);
      if (!current()) return VideoGalleryResult.canceled;
      return result is Map && result['isSuccess'] == true
          ? VideoGalleryResult.success
          : VideoGalleryResult.failed;
    } on TimeoutException {
      return VideoGalleryResult.timedOut;
    } on DioException catch (error) {
      return error.type == DioExceptionType.cancel
          ? VideoGalleryResult.canceled
          : VideoGalleryResult.downloadFailed;
    } on UnsupportedError {
      return VideoGalleryResult.unsupported;
    } catch (_) {
      return VideoGalleryResult.failed;
    } finally {
      if (!nativeOwnsFile) await _cleanup(staging);
    }
  }

  static Future<void> _cleanup(Directory? directory) async {
    if (directory == null) return;
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
  }

  static Future<bool> _permission() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return (await Permission.photosAddOnly.request()).isGranted;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      if ((await DeviceInfoPlugin().androidInfo).version.sdkInt >= 29) {
        return true;
      }
      return (await Permission.storage.request()).isGranted;
    }
    throw UnsupportedError('Video gallery');
  }

  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    _client.close(force: true);
  }
}
