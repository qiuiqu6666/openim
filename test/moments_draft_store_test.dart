import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/moments_draft_store.dart';
import 'package:openim/services/moments_repository.dart';

class _Api extends MomentsApi {
  _Api() : super(baseUrl: 'https://moments.example');
  final requests = <Map<String, dynamic>>[];
  final uploads = <String>[];
  bool timeout = false;
  Object? queryError;
  Object? uploadError;
  MomentsWriteResult result = const MomentsWriteResult(status: 'NOT_FOUND');
  Completer<MomentPost>? createGate;
  Completer<MomentMedia>? uploadGate;
  CancelToken? uploadCancellation;
  int queryCalls = 0;
  static const post = MomentPost(
      momentId: 'real-post',
      author: MomentUser(userId: 'me'),
      text: 'hello',
      canDelete: true,
      version: 1);
  @override
  Future<MomentsCapabilities> capabilities() async => const MomentsCapabilities(
      enabled: true, readEnabled: true, publishEnabled: true);
  @override
  Future<MomentPost> createPost(
      {required String clientRequestID,
      String text = '',
      List<String> mediaIds = const [],
      String visibility = 'FRIENDS',
      List<String> audienceUserIds = const []}) async {
    requests.add({
      'clientRequestID': clientRequestID,
      'text': text,
      'mediaIds': List.of(mediaIds),
      'visibility': visibility,
      'audienceUserIds': List.of(audienceUserIds)
    });
    if (createGate != null) return createGate!.future;
    if (timeout) throw const MomentsException('timeout', unknownResult: true);
    return post;
  }

  @override
  Future<MomentsWriteResult> queryPublishResult(String clientRequestID) async {
    queryCalls++;
    if (queryError != null) throw queryError!;
    return result;
  }

  @override
  Future<MomentPost> detail(String momentId) async =>
      throw const MomentsException('Unavailable', permissionDenied: true);
  @override
  Future<MomentMedia> uploadMedia(
      {required String filePath,
      required String clientMediaId,
      String type = 'IMAGE',
      String? fileName,
      ProgressCallback? onProgress,
      CancelToken? cancelToken}) async {
    uploads.add(clientMediaId);
    uploadCancellation = cancelToken;
    expect(await File(filePath).exists(), isTrue);
    onProgress?.call(1, 2);
    if (uploadError != null) throw uploadError!;
    if (uploadGate != null) {
      return Future.any([
        uploadGate!.future,
        cancelToken!.whenCancel
            .then<MomentMedia>((_) => throw const MomentsException('cancelled'))
      ]);
    }
    onProgress?.call(2, 2);
    return MomentMedia(mediaId: 'server-$clientMediaId');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory workspace;
  late _Api api;
  late MomentsRepository repository;
  late MomentsDraftStore store;
  Map<String, dynamic>? persisted;
  var owner = 'me';
  var environment = 'https://moments.example';
  var failWrites = false;
  Future<void> write(Map<String, dynamic>? value) async {
    if (failWrites) throw StateError('Disk is full');
    persisted = value == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  }

  MomentsDraftStore makeStore() => MomentsDraftStore(
      repository: repository,
      read: () async => persisted,
      write: write,
      directory: () async => Directory('${workspace.path}/drafts'),
      compress: (file) async => file);
  Future<File> image([String name = 'photo']) async =>
      File('${workspace.path}/$name.png').writeAsBytes([1, 2, 3, 4]);
  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('moments-publish-test-');
    persisted = null;
    owner = 'me';
    environment = 'https://moments.example';
    failWrites = false;
    api = _Api();
    repository = MomentsRepository(
        api: api,
        subscribeToSdk: false,
        userIdProvider: () => owner,
        environmentProvider: () => environment,
        friendLoader: () async => const []);
    store = makeStore();
    await store.load();
  });
  tearDown(() async {
    store.dispose();
    repository.dispose();
    await workspace.delete(recursive: true);
  });

  test('draft keys isolate account and service; persistence includes no token',
      () async {
    store.updateText('private draft');
    await store.save();
    final key = store.cacheKey;
    expect(persisted!['owner'], 'me');
    expect(persisted!.keys, isNot(contains('token')));
    owner = 'other';
    final other = makeStore();
    expect(other.cacheKey, isNot(key));
    other.dispose();
    owner = 'me';
    environment = 'https://other.example';
    final node = makeStore();
    expect(node.cacheKey, isNot(key));
    node.dispose();
    expect(store.sessionCurrent, isFalse);
  });
  test(
      'retained media survive selection-file deletion and publish in edited order',
      () async {
    final first = await image('first');
    final second = await image('second');
    await store.addFiles([first, second]);
    final firstId = store.media.first.clientMediaId;
    final secondId = store.media.last.clientMediaId;
    await store.moveMedia(secondId, 0);
    await first.delete();
    await second.delete();
    await store.updateVisibility(const MomentsVisibilitySelection(
        mode: 'PARTIAL', audienceUserIds: ['friend']));
    final created = await store.publish();
    expect(created?.momentId, 'real-post');
    expect(api.uploads, [secondId, firstId]);
    expect(api.requests.single['mediaIds'],
        ['server-$secondId', 'server-$firstId']);
    expect(api.requests.single['audienceUserIds'], ['friend']);
    expect(persisted, isNull);
    expect(store.media, isEmpty);
  });
  test(
      'unknown submission freezes content and restores the same key and media IDs',
      () async {
    await store.addFiles([await image()]);
    store.updateText('original payload');
    api.timeout = true;
    await store.publish();
    final original = Map<String, dynamic>.from(api.requests.single);
    final savedMediaId = store.media.single.mediaId;
    expect(store.stage, MomentsPublishStage.submitUnknown);
    store.updateText('changed content');
    expect(store.text, 'original payload');
    expect(() => store.discard(), throwsStateError);
    store.dispose();
    store = makeStore();
    await store.load();
    expect(store.job!.clientRequestID, original['clientRequestID']);
    expect(store.media.single.mediaId, savedMediaId);
    api.timeout = false;
    await store.publish();
    expect(api.queryCalls, 1);
    expect(api.requests, [original, original]);
    expect(api.uploads, hasLength(1));
  });
  test('a failed result query stays uncertain and cannot unlock editing',
      () async {
    store.updateText('hello');
    api.timeout = true;
    await store.publish();
    api.queryError = const MomentsException('read timeout');
    await store.publish();
    expect(store.stage, MomentsPublishStage.submitUnknown);
    await store.resumeEditing();
    expect(store.job, isNotNull);
    expect(api.requests, hasLength(1));
  });
  test('processing result never sends a second create request', () async {
    store.updateText('hello');
    api.timeout = true;
    await store.publish();
    api.result = const MomentsWriteResult(status: 'PROCESSING');
    await store.publish();
    expect(api.requests, hasLength(1));
    expect(store.resultUncertain, isTrue);
  });
  test(
      'confirmed creation with unavailable detail completes without inventing a post',
      () async {
    store.updateText('hello');
    api.timeout = true;
    await store.publish();
    api.result =
        const MomentsWriteResult(status: 'SUCCEEDED', resourceId: 'real-post');
    final post = await store.publish();
    expect(post, isNull);
    expect(store.confirmedMomentId, 'real-post');
    expect(store.job, isNull);
    expect(repository.postsById, isEmpty);
    expect(api.requests, hasLength(1));
    expect(persisted, isNull);
  });
  test(
      'publish task is durably saved before sending; local failure prevents transmission',
      () async {
    store.updateText('hello');
    failWrites = true;
    await store.publish();
    expect(api.requests, isEmpty);
    expect(store.job, isNotNull);
    final originalKey = store.job!.clientRequestID;
    failWrites = false;
    await store.save();
    await store.publish();
    expect(api.requests.single['clientRequestID'], originalKey);
  });
  test('upload failure retains all attachments and stable client media IDs',
      () async {
    await store.addFiles([await image('first'), await image('second')]);
    final ids = store.media.map((m) => m.clientMediaId).toList();
    api.uploadError = const MomentsException('upload refused');
    await store.publish();
    expect(store.stage, MomentsPublishStage.uploadFailed);
    expect(api.requests, isEmpty);
    expect(store.media.map((m) => m.clientMediaId), ids);
    api.uploadError = null;
    await store.publish();
    expect(api.uploads.take(2), [ids.first, ids.first]);
    expect(api.requests.single['mediaIds'], hasLength(2));
  });
  test('cancel before commit waits for upload and preserves an editable draft',
      () async {
    await store.addFiles([await image()]);
    api.uploadGate = Completer<MomentMedia>();
    final work = store.publish();
    while (api.uploadCancellation == null) {
      await Future<void>.delayed(Duration.zero);
    }
    await store.resumeEditing();
    await work;
    expect(api.uploadCancellation!.isCancelled, isTrue);
    expect(api.requests, isEmpty);
    expect(store.job, isNull);
    expect(store.media, hasLength(1));
  });
  test(
      'late create response from another account cannot merge or clear its old pending record',
      () async {
    store.updateText('hello');
    api.createGate = Completer<MomentPost>();
    final work = store.publish();
    while (api.requests.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    owner = 'other';
    api.createGate!.complete(_Api.post);
    await work;
    expect(repository.postsById, isEmpty);
    expect(persisted!['owner'], 'me');
    expect((persisted!['job'] as Map)['submitted'], isTrue);
  });
  test('corrupt recovered task cannot overwrite its durable evidence',
      () async {
    store.updateText('hello');
    await store.save();
    persisted!['job'] = {'clientRequestID': 'stable', 'submitted': true};
    store.dispose();
    store = makeStore();
    await store.load();
    expect(store.recoveryFailed, isTrue);
    await expectLater(store.save(), throwsStateError);
    expect((persisted!['job'] as Map)['clientRequestID'], 'stable');
  });
  test(
      'failed recovery exposes no partial draft and prevents discard or publish',
      () async {
    store.updateText('durable original');
    await store.save();
    persisted!['job'] = {'clientRequestID': 'stable', 'submitted': true};
    final evidence = jsonEncode(persisted);
    store.dispose();
    store = makeStore();
    await store.load();
    expect(store.text, isEmpty);
    expect(store.media, isEmpty);
    expect(store.job, isNull);
    store.updateText('replacement');
    await expectLater(store.discard(), throwsStateError);
    await expectLater(store.publish(), throwsStateError);
    await store.retryRecovery();
    expect(store.recoveryFailed, isTrue);
    expect(jsonEncode(persisted), evidence);
    expect(api.requests, isEmpty);
  });
  test('retry re-reads once and preserves a restored unknown publish request',
      () async {
    store.updateText('original payload');
    api.timeout = true;
    await store.publish();
    final key = store.job!.clientRequestID;
    store.dispose();
    var reads = 0;
    final gate = Completer<Map<String, dynamic>?>();
    store = MomentsDraftStore(
        repository: repository,
        read: () {
          ++reads;
          if (reads == 1) {
            return Future.error(StateError('temporary read error'));
          }
          return gate.future;
        },
        write: write);
    await store.load();
    expect(store.recoveryFailed, isTrue);
    final first = store.retryRecovery();
    final second = store.retryRecovery();
    expect(identical(first, second), isTrue);
    expect(store.loaded, isFalse);
    gate.complete(persisted);
    await first;
    expect(reads, 2);
    expect(store.recoveryFailed, isFalse);
    expect(store.persistenceError, isNull);
    expect(store.text, 'original payload');
    expect(store.job!.clientRequestID, key);
    expect(store.stage, MomentsPublishStage.submitUnknown);
    expect(store.resultUncertain, isTrue);
    api.result = const MomentsWriteResult(status: 'SUCCEEDED', post: _Api.post);
    await store.publish();
    expect(api.requests, hasLength(1));
    expect(api.queryCalls, 1);
  });
  test('a late recovery read cannot hydrate a page from a different account',
      () async {
    store.updateText('old account text');
    await store.save();
    store.dispose();
    var reads = 0;
    final gate = Completer<Map<String, dynamic>?>();
    store = MomentsDraftStore(
        repository: repository,
        read: () async {
          if (++reads == 1) throw StateError('read error');
          return gate.future;
        },
        write: write);
    await store.load();
    final retry = store.retryRecovery();
    owner = 'other';
    gate.complete(persisted);
    await retry;
    expect(store.text, isEmpty);
    expect(store.job, isNull);
    expect(store.sessionCurrent, isFalse);
    expect(persisted!['owner'], 'me');
  });
  test(
      'selection stops at nine images without dropping a failed upload silently',
      () async {
    final files = <File>[];
    for (var i = 0; i < 10; i++) {
      files.add(await image('image-$i'));
    }
    await store.addFiles(files);
    expect(store.media, hasLength(9));
    await File(store.media[4].path).delete();
    await store.publish();
    expect(store.stage, MomentsPublishStage.uploadFailed);
    expect(store.media, hasLength(9));
    expect(api.requests, isEmpty);
  });
}
