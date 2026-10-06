import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../services/favorite_repository.dart';

/// Private originals are verified before playback. Leases never enter shared
/// image/video caches; this loader owns and removes its unique temporary folder.
class FavoritePreviewLoader {
  FavoritePreviewLoader(
      {Dio? client, Future<Directory> Function()? temporaryRoot})
      : _client = client ?? Dio(),
        _temporaryRoot = temporaryRoot ?? getTemporaryDirectory;
  final Dio _client;
  final Future<Directory> Function() _temporaryRoot;
  final CancelToken _cancel = CancelToken();
  Directory? _directory;
  Future<File>? _operation;
  bool _closed = false;

  Future<File> load(FavoriteRepository repository, FavoriteItem item,
      FavoriteAsset asset, String scope,
      {ProgressCallback? onProgress}) {
    if (_operation != null) return _operation!;
    return _operation = _load(repository, item, asset, scope, onProgress);
  }

  Future<File> _load(FavoriteRepository repository, FavoriteItem item,
      FavoriteAsset asset, String scope, ProgressCallback? onProgress) async {
    void guard() {
      if (_closed || !repository.isSessionCurrent(scope)) {
        throw const FavoriteApiException('SESSION_CHANGED', '登录状态已改变',
            isCancelled: true);
      }
    }

    try {
      guard();
      final access = await repository.assetAccess(item.id, asset.id);
      guard();
      final limit = asset.mimeType.startsWith('video/')
          ? 100 * 1024 * 1024
          : 20 * 1024 * 1024;
      if (access.assetID != asset.id ||
          access.sizeBytes != asset.sizeBytes ||
          access.sizeBytes <= 0 ||
          access.sizeBytes > limit ||
          access.sha256.toLowerCase() != asset.sha256.toLowerCase()) {
        throw const FavoriteApiException('INVALID_PREVIEW', '收藏原件校验失败，请刷新详情');
      }
      if (access.expiresAt == null ||
          !access.expiresAt!.isAfter(DateTime.now().toUtc())) {
        throw const FavoriteApiException(20063, '原件访问已过期，请重试预览');
      }
      final root = await _temporaryRoot();
      guard();
      _directory = await root.createTemp('favorite-preview-');
      guard();
      // Use a fixed name, never a filename or private URL supplied by a server.
      final file = File('${_directory!.path}/original');
      final response = await _client.download(access.url.toString(), file.path,
          cancelToken: _cancel,
          options: Options(
              followRedirects: false,
              headers: const {},
              receiveTimeout: const Duration(seconds: 60)),
          onReceiveProgress: (received, total) {
        if (received > access.sizeBytes || total > access.sizeBytes) {
          _cancel.cancel();
        }
        onProgress?.call(received, access.sizeBytes);
      });
      guard();
      if (response.statusCode != 200 ||
          await file.length() != access.sizeBytes ||
          (await sha256.bind(file.openRead()).first).toString() !=
              access.sha256.toLowerCase()) {
        throw const FavoriteApiException('INVALID_PREVIEW', '收藏原件校验失败，请重试预览');
      }
      guard();
      return file;
    } catch (_) {
      await _removeDirectory();
      rethrow;
    }
  }

  Future<void> _removeDirectory() async {
    final directory = _directory;
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
      _directory = null;
    } on FileSystemException {
      // A native player may still be releasing its file; close retries cleanup.
    }
  }

  Future<void> close() async {
    _closed = true;
    _cancel.cancel();
    _client.close(force: true);
    try {
      await _operation;
    } catch (_) {/* No private transport error logging. */}
    await _removeDirectory();
  }
}
