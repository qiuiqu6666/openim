import 'dart:io';
import 'package:dio/dio.dart';
import '../../../services/favorite_api.dart';

class FavoriteMediaTask {
  String? uploadID;
  FavoriteUploadSession? session;
  FavoriteAsset? asset;
  bool uploaded = false;

  Map<String, dynamic>? toCacheJson() => uploadID == null
      ? null
      : {
          'uploadID': uploadID,
          'uploaded': uploaded,
          if (asset != null) 'asset': asset!.toJson()
        };

  factory FavoriteMediaTask.fromJson(Map<String, dynamic> json) {
    if (json['uploadID'] is! String ||
        (json['uploadID'] as String).isEmpty ||
        (json['uploaded'] != null && json['uploaded'] is! bool)) {
      throw const FormatException('Invalid favorite media checkpoint');
    }
    return FavoriteMediaTask()
      ..uploadID = json['uploadID'] as String
      ..asset = json['asset'] == null
          ? null
          : FavoriteAsset.fromJson(favoriteJsonMap(json['asset']))
      ..uploaded = json['uploaded'] as bool? ?? json['asset'] != null;
  }
  FavoriteMediaTask();
}

/// Upload checkpoints persist only upload/asset identities and state. Signed
/// URLs stay in memory. A lost complete response replays the original upload ID.
class FavoriteMediaUploader {
  const FavoriteMediaUploader(this.api);
  final FavoriteApi api;
  Future<FavoriteAsset> complete(
      {required FavoriteMediaTask task,
      required File file,
      required String fileName,
      required String mimeType,
      required FavoriteKind kind,
      required CancelToken cancel,
      required String Function(String) requestID,
      required void Function(String) forgetRequest,
      required void Function(String, String) restoreRequest,
      required Future<void> Function() checkpoint,
      required void Function() guard,
      ProgressCallback? onProgress}) async {
    if (task.asset != null &&
        (kind != FavoriteKind.video || task.asset!.coverAssetID != null)) {
      return task.asset!;
    }
    // Older clients may have cached an incomplete video DTO. Recheck complete
    // with the same upload and UUID instead of remaining stuck on that DTO.
    if (task.asset != null) {
      task.asset = null;
      await checkpoint();
      guard();
    }
    if (!task.uploaded || task.uploadID == null) {
      int size;
      try {
        size = await file.length();
      } on FileSystemException {
        guard();
        throw const FavoriteApiException(20056, '本地原文件不可用，请重新选择图片或文件');
      }
      guard();
      final max = kind == FavoriteKind.image || kind == FavoriteKind.audio
          ? 20 * 1024 * 1024
          : 100 * 1024 * 1024;
      if (size > max || size <= 0) {
        throw const FavoriteApiException(20058, '文件超过大小限制');
      }
      Future<FavoriteUploadSession> start() async {
        final request = requestID('init');
        await checkpoint();
        guard();
        return api.initializeUpload(
            fileName: fileName,
            mimeType: mimeType,
            sizeBytes: size,
            clientRequestID: request,
            cancelToken: cancel);
      }

      task.session ??= await start();
      guard();
      if (task.session!.expiresAt.isBefore(DateTime.now().toUtc())) {
        forgetRequest('init');
        forgetRequest('complete');
        task.session = null;
        task.uploaded = false;
        task.uploadID = null;
        task.session = await start();
        guard();
      }
      task.uploadID = task.session!.uploadID;
      await checkpoint();
      guard();
      await api.uploadFile(task.session!, file,
          cancelToken: cancel, onProgress: onProgress);
      guard();
      task.uploaded = true;
    }
    final request = requestID('complete');
    await checkpoint();
    guard();
    try {
      task.asset = await api.completeUpload(task.uploadID!,
          clientRequestID: request, cancelToken: cancel);
    } on FavoriteApiException catch (failure) {
      guard();
      if (failure.code == 20056 &&
          !failure.isUncertain &&
          !failure.isCancelled) {
        // A conclusively missing/expired reservation cannot ever complete.
        // Preserve uncertain completions; renew only after this rejection.
        final initRequest = requestID('init');
        final oldSession = task.session;
        final oldUploadID = task.uploadID;
        final oldAsset = task.asset;
        final oldUploaded = task.uploaded;
        task
          ..asset = null
          ..session = null
          ..uploadID = null
          ..uploaded = false;
        forgetRequest('init');
        forgetRequest('complete');
        try {
          await checkpoint();
        } catch (_) {
          guard();
          task
            ..asset = oldAsset
            ..session = oldSession
            ..uploadID = oldUploadID
            ..uploaded = oldUploaded;
          restoreRequest('init', initRequest);
          restoreRequest('complete', request);
          rethrow;
        }
        guard();
        throw const FavoriteApiException(20056, '上传记录已失效，请重新选择图片或文件后重试');
      }
      rethrow;
    }
    guard();
    // This exact asset/body must be durable before favorites.create.
    await checkpoint();
    guard();
    return task.asset!;
  }
}
