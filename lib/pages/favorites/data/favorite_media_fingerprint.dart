import 'dart:io';

import 'package:dio/dio.dart';

import '../../../services/favorite_api.dart';
import '../../../services/media/file_hasher.dart';
import 'favorite_media_upload.dart';

/// One cancellable hash worker per repository, shared by concurrent callers.
class FavoriteMediaFingerprint {
  final _hasher = FileHasher();
  Future<void> _tail = Future<void>.value();
  CancelToken? _activeCancel;

  Future<({int size, String hash})> read(File file,
      {required FavoriteKind kind, required CancelToken cancelToken}) {
    final request = _tail.then((_) async {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final size = await file.length();
      FavoriteMediaUploader.validateFileSize(kind, size);
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      // Do not attach a worker callback to a long-lived account token for
      // every file. The repository cancels this operation on session changes.
      final operation = _activeCancel = CancelToken();
      try {
        final hash = await _hasher.hash(file, cancelToken: operation);
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        // The key's size and digest must describe the same original file.
        if (await file.length() != size) {
          throw const FileSystemException('Original file changed while hashing');
        }
        return (size: size, hash: hash);
      } finally {
        if (identical(_activeCancel, operation)) _activeCancel = null;
        operation.cancel('Fingerprint finished');
      }
    });
    // An invalid file or cancellation must not poison later queued work.
    _tail = request.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return request;
  }

  void cancelActive() => _activeCancel?.cancel('Favorite session changed');

  void dispose() => _hasher.dispose();
}
