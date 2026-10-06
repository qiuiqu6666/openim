import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'favorite_models.dart';

class FavoriteBuildException implements Exception {
  const FavoriteBuildException(this.code, this.message,
      {this.retryable = false});
  final String code;
  final String message;
  final bool retryable;
  @override
  String toString() => message;
}

class FavoriteBuiltMessage {
  const FavoriteBuiltMessage(
      {required this.message,
      required this.blockID,
      this.localPaths = const []});
  final Message message;
  final String blockID;
  final List<String> localPaths;
}

abstract class FavoriteMessageFactory {
  Future<Message> text(String text);
  Future<Message> image(String path);
  Future<Message> audio(String path, int durationSeconds);
  Future<Message> video(
      String path, String mimeType, int durationSeconds, String snapshotPath);
  Future<Message> file(String path, String fileName);
}

class OpenIMFavoriteMessageFactory implements FavoriteMessageFactory {
  MessageManager get _manager => OpenIM.iMManager.messageManager;
  @override
  Future<Message> text(String text) => _manager.createTextMessage(text: text);
  @override
  Future<Message> image(String path) =>
      _manager.createImageMessageFromFullPath(imagePath: path);
  @override
  Future<Message> audio(String path, int durationSeconds) =>
      _manager.createSoundMessageFromFullPath(
          soundPath: path, duration: durationSeconds);
  @override
  Future<Message> video(String path, String mimeType, int durationSeconds,
          String snapshotPath) =>
      _manager.createVideoMessageFromFullPath(
          videoPath: path,
          videoType: mimeType,
          duration: durationSeconds,
          snapshotPath: snapshotPath);
  @override
  Future<Message> file(String path, String fileName) => _manager
      .createFileMessageFromFullPath(filePath: path, fileName: fileName);
}

abstract class FavoriteMediaDownloader {
  Future<void> download(FavoriteDownload grant, File destination,
      {required int maxBytes,
      required bool Function() isActive,
      void Function(int received, int total)? onProgress});
}

/// A separate HTTP client intentionally sends no business/IM token to storage.
class DioFavoriteMediaDownloader implements FavoriteMediaDownloader {
  DioFavoriteMediaDownloader({Dio? dio, DateTime Function()? clock})
      : _dio = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 60))),
        _clock = clock ?? DateTime.now;
  final Dio _dio;
  final DateTime Function() _clock;
  @override
  Future<void> download(FavoriteDownload grant, File destination,
      {required int maxBytes,
      required bool Function() isActive,
      void Function(int received, int total)? onProgress}) async {
    final uri = grant.url;
    if (grant.expiresAt?.isAfter(_clock()) == false) {
      throw const FavoriteBuildException('PREPARE_EXPIRED', '附件下载授权已过期，请重新准备',
          retryable: true);
    }
    if (!['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        grant.sizeBytes <= 0 ||
        grant.sizeBytes > maxBytes) {
      throw const FavoriteBuildException('MEDIA_INVALID', '附件下载参数无效');
    }
    final cancellation = CancelToken();
    IOSink? sink;
    try {
      if (!isActive()) {
        throw const FavoriteBuildException('SESSION_CHANGED', '登录状态已变化');
      }
      final response = await _dio.get<ResponseBody>(uri.toString(),
          cancelToken: cancellation,
          options: Options(
              responseType: ResponseType.stream, followRedirects: false));
      final body = response.data;
      if (body == null || response.statusCode != 200) {
        throw const FavoriteBuildException('DOWNLOAD_FAILED', '无法下载收藏原件',
            retryable: true);
      }
      await destination.parent.create(recursive: true);
      sink = destination.openWrite();
      var received = 0;
      await for (final chunk in body.stream) {
        if (!isActive()) {
          cancellation.cancel();
          throw const FavoriteBuildException('SESSION_CHANGED', '登录状态已变化');
        }
        received += chunk.length;
        if (received > maxBytes || received > grant.sizeBytes) {
          cancellation.cancel();
          throw const FavoriteBuildException('MEDIA_TOO_LARGE', '附件超过允许的大小');
        }
        sink.add(chunk);
        // Keep the write buffer bounded even for large video/file downloads.
        await sink.flush();
        onProgress?.call(received, grant.sizeBytes);
      }
      await sink.close();
      sink = null;
      if (received != grant.sizeBytes) {
        throw const FavoriteBuildException('MEDIA_INVALID', '附件不完整，请重新下载',
            retryable: true);
      }
    } on DioException {
      throw const FavoriteBuildException('DOWNLOAD_FAILED', '收藏原件下载失败，请重试',
          retryable: true);
    } finally {
      await sink?.close();
    }
  }
}

/// Rebuilds primitive messages from an authorized snapshot, never from old IM JSON.
class FavoriteMessageBuilder {
  FavoriteMessageBuilder(
      {FavoriteMessageFactory? messageFactory,
      FavoriteMediaDownloader? downloader,
      Future<Directory> Function()? directoryProvider,
      DateTime Function()? clock,
      this.maxTotalBytes = 200 * 1024 * 1024,
      this.maxMediaBytes = 100 * 1024 * 1024,
      this.maxBlocks = 100})
      : _factory = messageFactory ?? OpenIMFavoriteMessageFactory(),
        _downloader = downloader ?? DioFavoriteMediaDownloader(),
        _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory,
        _clock = clock ?? DateTime.now;
  final FavoriteMessageFactory _factory;
  final FavoriteMediaDownloader _downloader;
  final Future<Directory> Function() _directoryProvider;
  final DateTime Function() _clock;
  final int maxTotalBytes;
  final int maxMediaBytes;
  final int maxBlocks;

  Future<List<FavoriteBuiltMessage>> build(FavoritePreparedSend prepared,
      {required List<FavoriteAsset> assets,
      required String sendAttemptID,
      String namespace = '',
      bool Function()? isActive,
      void Function(String stage, int completed, int total)?
          onProgress}) async {
    final active = isActive ?? () => true;
    void guard() {
      if (!active()) {
        throw const FavoriteBuildException('SESSION_CHANGED', '登录状态已变化');
      }
      if (!prepared.expiresAt.isAfter(_clock())) {
        throw const FavoriteBuildException('PREPARE_EXPIRED', '发送准备已过期，请重试',
            retryable: true);
      }
    }

    guard();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(sendAttemptID)) {
      throw const FavoriteBuildException('MEDIA_INVALID', '发送任务无效');
    }
    const supportedKinds = {
      FavoriteKind.text,
      FavoriteKind.image,
      FavoriteKind.video,
      FavoriteKind.audio,
      FavoriteKind.file,
      FavoriteKind.note,
      FavoriteKind.link
    };
    if (!supportedKinds.contains(prepared.sendContent.kind)) {
      throw const FavoriteBuildException('UNSUPPORTED_CONTENT', '该收藏类型暂不支持发送');
    }
    final blocks = prepared.sendContent.blocks;
    if (blocks.isEmpty || blocks.length > maxBlocks) {
      throw const FavoriteBuildException('UNSUPPORTED_CONTENT', '收藏内容数量超出限制');
    }
    const supported = {'text', 'image', 'video', 'audio', 'file', 'link'};
    if (blocks.any((block) => !supported.contains(block.type))) {
      throw const FavoriteBuildException('UNSUPPORTED_CONTENT', '该收藏类型暂不支持发送');
    }
    final assetMap = {for (final asset in assets) asset.id: asset};
    final downloads = {
      for (final grant in prepared.downloads) grant.assetID: grant
    };
    final root = await _directoryProvider();
    guard();
    final scope = sha256.convert(utf8.encode(namespace)).toString();
    final directory =
        Directory(p.join(root.path, 'favorite-send', scope, sendAttemptID));
    final localFiles = <String, String>{};
    var bytes = 0;
    Future<String> resolve(String? assetID, {bool imageOnly = false}) async {
      guard();
      final asset = assetMap[assetID];
      final grant = downloads[assetID];
      if (asset == null ||
          grant == null ||
          asset.sizeBytes != grant.sizeBytes ||
          asset.sha256.toLowerCase() != grant.sha256.toLowerCase() ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(grant.sha256) ||
          imageOnly && !asset.mimeType.startsWith('image/')) {
        throw const FavoriteBuildException('ASSET_MISSING', '缺少完整的收藏原件或封面');
      }
      void guardGrant() {
        guard();
        if (grant.expiresAt?.isAfter(_clock()) == false) {
          throw const FavoriteBuildException(
              'PREPARE_EXPIRED', '附件下载授权已过期，请重新准备',
              retryable: true);
        }
      }

      guardGrant();
      if (localFiles.containsKey(assetID)) return localFiles[assetID]!;
      final limit = asset.mimeType.startsWith('image/') ||
              asset.mimeType.startsWith('audio/')
          ? 20 * 1024 * 1024
          : maxMediaBytes;
      bytes += grant.sizeBytes;
      if (grant.sizeBytes <= 0 ||
          grant.sizeBytes > limit ||
          bytes > maxTotalBytes) {
        throw const FavoriteBuildException('MEDIA_TOO_LARGE', '附件超过允许的大小');
      }
      final file = File(
          p.join(directory.path, '${const Uuid().v4()}.${_extension(asset)}'));
      localFiles[assetID!] = file.path;
      await _downloader.download(grant, file,
          maxBytes: limit,
          isActive: active,
          onProgress: (received, total) =>
              onProgress?.call('downloading', received, total));
      guardGrant();
      if (!await file.exists() ||
          await file.length() != grant.sizeBytes ||
          (await sha256.bind(file.openRead()).first).toString().toLowerCase() !=
              grant.sha256.toLowerCase()) {
        throw const FavoriteBuildException('MEDIA_INVALID', '附件校验失败，请重新下载',
            retryable: true);
      }
      return file.path;
    }

    final built = <FavoriteBuiltMessage>[];
    try {
      for (final block in blocks) {
        guard();
        onProgress?.call('building', built.length, blocks.length);
        final paths = <String>[];
        late Message message;
        switch (block.type) {
          case 'text':
            final text = block.text ?? block.data['text']?.toString() ?? '';
            _validateText(text);
            message = await _factory.text(text);
          case 'link':
            final url = block.data['url']?.toString() ?? block.text ?? '';
            final uri = Uri.tryParse(url);
            if (uri == null ||
                !['http', 'https'].contains(uri.scheme) ||
                uri.host.isEmpty) {
              throw const FavoriteBuildException('MEDIA_INVALID', '网页链接无效');
            }
            _validateText(url);
            message = await _factory.text(url);
          case 'image':
            final path = await resolve(block.assetID, imageOnly: true);
            paths.add(path);
            message = await _factory.image(path);
          case 'audio':
            final asset = assetMap[block.assetID];
            if (asset == null || !asset.mimeType.startsWith('audio/')) {
              throw const FavoriteBuildException('MEDIA_INVALID', '语音原件无效');
            }
            final path = await resolve(block.assetID);
            paths.add(path);
            message = await _factory.audio(path, _duration(asset, block));
          case 'video':
            final asset = assetMap[block.assetID];
            if (asset == null || !asset.mimeType.startsWith('video/')) {
              throw const FavoriteBuildException('MEDIA_INVALID', '视频原件无效');
            }
            final path = await resolve(block.assetID);
            final explicitCover = block.data['coverAssetID']?.toString() ??
                block.data['snapshotAssetID']?.toString();
            final coverCandidates = assets
                .where((value) =>
                    ['snapshot', 'cover', 'thumbnail'].contains(value.role))
                .toList();
            final coverID = explicitCover ??
                (blocks.where((value) => value.type == 'video').length == 1 &&
                        coverCandidates.length == 1
                    ? coverCandidates.single.id
                    : null);
            final cover = await resolve(coverID, imageOnly: true);
            paths.addAll([path, cover]);
            message = await _factory.video(
                path, asset.mimeType, _duration(asset, block), cover);
          case 'file':
            final path = await resolve(block.assetID);
            paths.add(path);
            final fileName = block.data['fileName']?.toString() ??
                assetMap[block.assetID]?.fileName ??
                '文件';
            message = await _factory.file(
                path, p.basename(fileName.replaceAll('\\', '/')));
          default:
            throw const FavoriteBuildException(
                'UNSUPPORTED_CONTENT', '该收藏类型暂不支持发送');
        }
        guard();
        if (message.clientMsgID?.isNotEmpty != true) {
          throw const FavoriteBuildException('MESSAGE_BUILD_FAILED', '无法创建新消息');
        }
        built.add(FavoriteBuiltMessage(
            message: message,
            blockID: block.id,
            localPaths: List.unmodifiable(paths)));
      }
      return List.unmodifiable(built);
    } catch (_) {
      // Nothing has been sent at this point; failed/unknown submitted messages
      // are retained by the coordinator instead of using this cleanup path.
      for (final path in localFiles.values) {
        try {
          if (await File(path).exists()) await File(path).delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  static void _validateText(String text) {
    if (text.trim().isEmpty || utf8.encode(text).length > 64 * 1024) {
      throw const FavoriteBuildException('MEDIA_INVALID', '文字为空或超过发送限制');
    }
  }

  static int _duration(FavoriteAsset asset, FavoriteBlock block) {
    final milliseconds = asset.durationMs ??
        int.tryParse(block.data['durationMs']?.toString() ?? '');
    if (milliseconds == null || milliseconds <= 0) {
      throw const FavoriteBuildException('MEDIA_INVALID', '缺少真实的音视频时长');
    }
    return (milliseconds / 1000).ceil();
  }

  static String _extension(FavoriteAsset asset) {
    const known = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/gif': 'gif',
      'image/webp': 'webp',
      'video/mp4': 'mp4',
      'video/quicktime': 'mov',
      'audio/mp4': 'm4a',
      'audio/mpeg': 'mp3',
      'audio/wav': 'wav',
      'audio/x-wav': 'wav',
      'audio/ogg': 'ogg',
      'application/pdf': 'pdf'
    };
    final extension =
        p.extension(asset.fileName ?? '').replaceFirst('.', '').toLowerCase();
    return known[asset.mimeType] ??
        (RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension) ? extension : 'bin');
  }
}
