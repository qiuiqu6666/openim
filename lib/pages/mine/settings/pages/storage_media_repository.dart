import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum StorageMediaType { image, video, file }

class StorageMediaItem {
  const StorageMediaItem({
    required this.id,
    required this.message,
    required this.conversationID,
    required this.conversationName,
    required this.conversationFaceURL,
    required this.type,
    required this.bytes,
    required this.time,
    required this.localPaths,
    required this.cachedURLs,
    this.previewPath,
    this.fileName,
  });

  final String id;
  final Message message;
  final String conversationID;
  final String conversationName;
  final String? conversationFaceURL;
  final StorageMediaType type;
  final int bytes;
  final DateTime time;
  final List<String> localPaths;
  final List<String> cachedURLs;
  final String? previewPath;
  final String? fileName;
}

/// Reads only files owned by this app. Message records and public files are
/// never removed by the storage cleaner.
class StorageMediaRepository {
  StorageMediaRepository(
      {CacheManager? cacheManager, List<Directory>? ownedRoots})
      : _cacheManager = cacheManager ?? DefaultCacheManager(),
        _overrideRoots = ownedRoots;

  final CacheManager _cacheManager;
  final List<Directory>? _overrideRoots;
  late final Future<List<String>> _roots = _ownedRoots();

  Future<List<String>> _ownedRoots() async {
    final roots = _overrideRoots ??
        [
          await getApplicationCacheDirectory(),
          await getTemporaryDirectory(),
          Directory(p.join(Config.cachePath, 'outgoing_media')),
        ];
    return Future.wait(roots.map((root) async {
      try {
        return p.normalize(await root.resolveSymbolicLinks());
      } catch (_) {
        return p.normalize(root.absolute.path);
      }
    }));
  }

  Future<bool> _isOwnedFile(String path) async {
    if (path.isEmpty || !p.isAbsolute(path)) return false;
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final resolved = p.normalize(await file.resolveSymbolicLinks());
      return (await _roots).any((root) => p.isWithin(root, resolved));
    } catch (_) {
      return false;
    }
  }

  Future<StorageMediaItem?> resolve(
    Message message,
    SearchResultItems conversation,
  ) async {
    final type = switch (message.contentType) {
      MessageType.picture => StorageMediaType.image,
      MessageType.video => StorageMediaType.video,
      MessageType.file => StorageMediaType.file,
      _ => null,
    };
    if (type == null || message.clientMsgID == null) return null;
    final originalURL = switch (type) {
      StorageMediaType.image => message.pictureElem?.sourcePicture?.url ??
          message.pictureElem?.bigPicture?.url,
      StorageMediaType.video => message.videoElem?.videoUrl,
      StorageMediaType.file => message.fileElem?.sourceUrl,
    };
    final uri = Uri.tryParse(originalURL ?? '');
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      // A pending/local-only attachment may have no recoverable remote copy.
      return null;
    }

    final paths = <String>{};
    final urls = <String>{};
    final directPaths = <String?>[
      message.pictureElem?.sourcePath,
      message.videoElem?.videoPath,
      message.videoElem?.snapshotPath,
      message.fileElem?.filePath,
      if (type == StorageMediaType.file)
        await IMUtils.cachedChatFilePath(message),
    ];
    for (final path in directPaths) {
      if (path != null && await _isOwnedFile(path)) paths.add(path);
    }

    final remoteURLs = <String?>[
      message.pictureElem?.sourcePicture?.url,
      message.pictureElem?.bigPicture?.url,
      message.pictureElem?.snapshotPicture?.url,
      message.videoElem?.videoUrl,
      message.videoElem?.snapshotUrl,
      message.fileElem?.sourceUrl,
    ];
    for (final url in remoteURLs) {
      if (url == null || url.isEmpty) continue;
      try {
        final info = await _cacheManager.getFileFromCache(url);
        if (info != null && await _isOwnedFile(info.file.path)) {
          paths.add(info.file.path);
          urls.add(url);
        }
      } catch (_) {
        // A stale cache entry does not make the whole scan fail.
      }
    }
    if (paths.isEmpty) return null;

    var bytes = 0;
    for (final path in paths) {
      try {
        bytes += await File(path).length();
      } catch (_) {}
    }
    final preview = type == StorageMediaType.file
        ? null
        : type == StorageMediaType.video
            ? (paths.contains(message.videoElem?.snapshotPath)
                ? message.videoElem?.snapshotPath
                : await _cachedPath(message.videoElem?.snapshotUrl))
            : (paths.contains(message.pictureElem?.sourcePath)
                ? message.pictureElem?.sourcePath
                : await _cachedPath(
                        message.pictureElem?.snapshotPicture?.url) ??
                    await _cachedPath(message.pictureElem?.bigPicture?.url));
    return StorageMediaItem(
      id: message.clientMsgID!,
      message: message,
      conversationID: conversation.conversationID ?? '',
      conversationName: conversation.showName ?? '',
      conversationFaceURL: conversation.faceURL,
      type: type,
      bytes: bytes,
      time: DateTime.fromMillisecondsSinceEpoch(message.sendTime ?? 0),
      localPaths: paths.toList(),
      cachedURLs: urls.toList(),
      previewPath: preview,
      fileName: message.fileElem?.fileName,
    );
  }

  Future<String?> _cachedPath(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final file = (await _cacheManager.getFileFromCache(url))?.file;
      if (file != null && await _isOwnedFile(file.path)) return file.path;
    } catch (_) {}
    return null;
  }

  Future<void> removeLocalFiles(Iterable<StorageMediaItem> items) async {
    final urls = items.expand((item) => item.cachedURLs).toSet();
    final paths = items.expand((item) => item.localPaths).toSet();
    for (final url in urls) {
      await _cacheManager.removeFile(url);
    }
    for (final path in paths) {
      if (await _isOwnedFile(path)) {
        await File(path).delete();
      }
    }
  }
}
