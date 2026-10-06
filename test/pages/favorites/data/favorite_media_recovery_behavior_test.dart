import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/favorites/data/favorite_media_upload.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'favorite_repository_behavior_test.dart' show BehaviorApi, row;

class UploadApi extends BehaviorApi {
  final initialRequests = <String>[];
  final declarations = <String>[];
  final completeRequests = <String>[];
  final uploadsCompleted = <String>[];
  int puts = 0;
  Object? firstInitError;
  Object? firstCompleteError;

  @override
  Future<FavoriteUploadSession> initializeUpload(
      {required String fileName,
      required String mimeType,
      required int sizeBytes,
      required String clientRequestID,
      CancelToken? cancelToken}) async {
    initialRequests.add(clientRequestID);
    declarations.add(mimeType);
    if (firstInitError != null) {
      final error = firstInitError!;
      firstInitError = null;
      throw error;
    }
    return FavoriteUploadSession(
        uploadID: 'new-upload-${initialRequests.length}',
        uploadURL: Uri.parse('https://storage.test/private-upload'),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        maxSizeBytes: 100);
  }

  @override
  Future<void> uploadFile(FavoriteUploadSession session, File file,
          {CancelToken? cancelToken, ProgressCallback? onProgress}) async =>
      puts++;

  @override
  Future<FavoriteAsset> completeUpload(String uploadID,
      {required String clientRequestID, CancelToken? cancelToken}) async {
    uploadsCompleted.add(uploadID);
    completeRequests.add(clientRequestID);
    if (firstCompleteError != null) {
      final error = firstCompleteError!;
      firstCompleteError = null;
      throw error;
    }
    return FavoriteAsset(
        id: 'asset',
        coverAssetID: 'video-cover',
        mimeType: 'image/png',
        sizeBytes: 4,
        sha256: 'a' * 64);
  }

  @override
  Future<FavoriteItem> create(
          {required FavoriteKind kind,
          required FavoriteContent content,
          required String clientRequestID,
          String title = '',
          List<String> uploadIDs = const [],
          List<String> assetIDs = const [],
          CancelToken? cancelToken}) async =>
      row('created');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<File> original() async {
    final dir = await Directory.systemTemp.createTemp('favorites-upload-');
    final file =
        await File('${dir.path}/original.png').writeAsBytes([1, 2, 3, 4]);
    addTearDown(() async {
      await file.delete();
      await dir.delete();
    });
    return file;
  }

  test('a missing upload reservation renews both identities on the next retry',
      () async {
    final file = await original();
    final api = UploadApi()
      ..firstCompleteError =
          const FavoriteApiException(20056, 'expired upload');
    final task = FavoriteMediaTask()
      ..uploaded = true
      ..uploadID = 'old-upload';
    final ids = {
      'init': FavoriteApi.newRequestID(),
      'complete': FavoriteApi.newRequestID()
    };
    final oldComplete = ids['complete'];
    final checkpoints = <Map<String, dynamic>?>[];
    Future<FavoriteAsset> run() => FavoriteMediaUploader(api).complete(
        task: task,
        file: file,
        fileName: 'original.png',
        mimeType: 'image/png',
        kind: FavoriteKind.image,
        cancel: CancelToken(),
        requestID: (suffix) =>
            ids.putIfAbsent(suffix, FavoriteApi.newRequestID),
        forgetRequest: ids.remove,
        restoreRequest: (suffix, request) => ids[suffix] = request,
        checkpoint: () async => checkpoints.add(task.toCacheJson()),
        guard: () {});
    await expectLater(run(), throwsA(isA<FavoriteApiException>()));
    expect(task.uploadID, isNull);
    expect(task.uploaded, isFalse);
    expect(ids, isEmpty);
    await run();
    expect(api.puts, 1);
    expect(api.uploadsCompleted, ['old-upload', 'new-upload-1']);
    expect(api.completeRequests.last, isNot(oldComplete));
    expect(jsonEncode(checkpoints), isNot(contains('private-upload')));
  });

  for (final failure in [
    const FavoriteApiException('NETWORK_ERROR', 'unknown', isUncertain: true),
    const FavoriteApiException(20056, 'unknown', isUncertain: true),
  ]) {
    test('an uncertain completion ${failure.code} preserves upload and UUID',
        () async {
      final api = UploadApi()..firstCompleteError = failure;
      final task = FavoriteMediaTask()
        ..uploaded = true
        ..uploadID = 'original-upload';
      final ids = {'complete': FavoriteApi.newRequestID()};
      Future<FavoriteAsset> run() => FavoriteMediaUploader(api).complete(
          task: task,
          file: File('unavailable-original'),
          fileName: 'original.png',
          mimeType: 'image/png',
          kind: FavoriteKind.image,
          cancel: CancelToken(),
          requestID: (suffix) =>
              ids.putIfAbsent(suffix, FavoriteApi.newRequestID),
          forgetRequest: ids.remove,
          restoreRequest: (suffix, request) => ids[suffix] = request,
          checkpoint: () async {},
          guard: () {});
      await expectLater(run(), throwsA(isA<FavoriteApiException>()));
      expect(task.uploadID, 'original-upload');
      expect(task.uploaded, isTrue);
      await run();
      expect(api.initialRequests, isEmpty);
      expect(api.completeRequests.first, api.completeRequests.last);
    });
  }

  test('completion reset checkpoint failure restores upload and both UUIDs',
      () async {
    final api = UploadApi()
      ..firstCompleteError = const FavoriteApiException(20056, 'expired');
    final task = FavoriteMediaTask()
      ..uploaded = true
      ..uploadID = 'original-upload';
    final oldIDs = {
      'init': FavoriteApi.newRequestID(),
      'complete': FavoriteApi.newRequestID(),
    };
    final ids = Map<String, String>.from(oldIDs);
    var denyReset = true;
    Future<FavoriteAsset> run() => FavoriteMediaUploader(api).complete(
        task: task,
        file: File('unavailable-original'),
        fileName: 'original.png',
        mimeType: 'image/png',
        kind: FavoriteKind.image,
        cancel: CancelToken(),
        requestID: (suffix) =>
            ids.putIfAbsent(suffix, FavoriteApi.newRequestID),
        forgetRequest: ids.remove,
        restoreRequest: (suffix, request) => ids[suffix] = request,
        checkpoint: () async {
          if (denyReset && task.uploadID == null) {
            throw const FavoriteApiException('LOCAL_SAVE_FAILED', 'storage');
          }
        },
        guard: () {});
    await expectLater(
        run(),
        throwsA(isA<FavoriteApiException>()
            .having((failure) => failure.code, 'code', 'LOCAL_SAVE_FAILED')));
    expect(task.uploadID, 'original-upload');
    expect(task.uploaded, isTrue);
    expect(ids, oldIDs);
    denyReset = false;
    api.firstCompleteError = const FavoriteApiException(20056, 'expired');
    await expectLater(
        run(),
        throwsA(isA<FavoriteApiException>()
            .having((failure) => failure.code, 'code', 20056)
            .having(
                (failure) => failure.message, 'message', contains('上传记录已失效'))));
    expect(api.completeRequests, [oldIDs['complete'], oldIDs['complete']]);
    expect(api.puts, 0);
    expect(task.uploadID, isNull);
    expect(ids, isEmpty);
  });

  test('a corrected MIME declaration never reuses a different init body UUID',
      () async {
    final file = await original();
    final api = UploadApi()
      ..firstInitError = const FavoriteApiException('NETWORK_ERROR', 'unknown',
          isUncertain: true);
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(
        repo.createMedia(
            kind: FavoriteKind.image,
            filePath: file.path,
            mimeType: 'application/octet-stream'),
        throwsA(isA<FavoriteApiException>()));
    await repo.createMedia(
        kind: FavoriteKind.image, filePath: file.path, mimeType: 'image/png');
    expect(api.declarations, ['application/octet-stream', 'image/png']);
    expect(api.initialRequests.first, isNot(api.initialRequests.last));
  });

  test('cached video metadata without its cover rechecks the same completion',
      () async {
    final api = UploadApi();
    final task = FavoriteMediaTask()
      ..uploaded = true
      ..uploadID = 'original-upload'
      ..asset = FavoriteAsset(
          id: 'asset', mimeType: 'video/mp4', sizeBytes: 4, sha256: 'a' * 64);
    final completeID = FavoriteApi.newRequestID();
    final asset = await FavoriteMediaUploader(api).complete(
        task: task,
        file: File('unavailable-original'),
        fileName: 'video.mp4',
        mimeType: 'video/mp4',
        kind: FavoriteKind.video,
        cancel: CancelToken(),
        requestID: (_) => completeID,
        forgetRequest: (_) => fail('uncertain identity must survive'),
        restoreRequest: (_, __) => fail('no identity reset was attempted'),
        checkpoint: () async {},
        guard: () {});
    expect(asset.coverAssetID, 'video-cover');
    expect(api.initialRequests, isEmpty);
    expect(api.completeRequests, [completeID]);
  });

  test(
      'an old invalid outbox body retires its UUID before a corrected new action',
      () async {
    const text = 'same text';
    final key = sha256
        .convert(utf8.encode('note:${jsonEncode({'title': '', 'text': text})}'))
        .toString();
    final oldID = FavoriteApi.newRequestID();
    final outbox = FavoriteMutationOutbox();
    await outbox.put(
        'favorites:https://chat.test:me',
        FavoriteMutationEntry(
            key: key,
            operation: FavoriteMutationOperation.create,
            clientRequestID: oldID,
            body: {
              'clientRequestID': oldID,
              'origin': 'userCreated',
              'kind': 'note',
              'title': '',
              'content': {
                'blocks': [
                  {'type': 'text', 'text': text}
                ]
              }
            }));
    final api = BodyCheckingApi();
    final repo = FavoriteRepository(
        api: api, outbox: outbox, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await repo.replayPendingMutations();
    expect(api.ids, [oldID]);
    expect(api.blocks.first.containsKey('id'), isFalse);
    expect(repo.pendingRecovery, isEmpty);
    await repo.createNote(text);
    expect(api.ids.last, isNot(oldID));
    expect(api.blocks.last['id'], 'b1');
  });
}

class BodyCheckingApi extends BehaviorApi {
  final ids = <String>[];
  final blocks = <Map<String, dynamic>>[];
  @override
  Future<FavoriteItem> create(
      {required FavoriteKind kind,
      required FavoriteContent content,
      required String clientRequestID,
      String title = '',
      List<String> uploadIDs = const [],
      List<String> assetIDs = const [],
      CancelToken? cancelToken}) async {
    ids.add(clientRequestID);
    final block = content.blocks.single.toJson();
    blocks.add(block);
    if (!block.containsKey('id')) {
      throw const FavoriteApiException(1001, 'block is invalid');
    }
    return row('created');
  }
}
