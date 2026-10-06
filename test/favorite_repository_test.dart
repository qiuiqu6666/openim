import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

FavoriteItem _item(String id,
        {FavoriteStatus status = FavoriteStatus.ready,
        int version = 1,
        List<FavoriteTag> tags = const [],
        FavoriteKind kind = FavoriteKind.note}) =>
    FavoriteItem(
        id: id,
        kind: kind,
        title: id,
        version: version,
        tags: tags,
        status: status,
        contentRevision: 'r1',
        content: FavoriteContent(kind: kind, blocks: const [
          FavoriteBlock(id: 'b1', type: 'text', text: 'hello')
        ]));

class _Api extends FavoriteApi {
  _Api() : super(baseUrl: 'https://chat.test', tokenProvider: () => 'token');
  Future<FavoritePage> Function(String, String?, FavoriteKind?)? listHook;
  List<FavoriteItem> serverItems = [];
  final createRequests = <String>[];
  bool failNextCreate = false;
  int uploaded = 0;
  int completed = 0;
  String? lastTagID;
  List<String>? patchTags;
  int? patchVersion;
  FavoriteContent? createdContent;
  List<FavoriteTag> serverTags = [];
  bool failTagList = false;
  @override
  Future<FavoriteQuota> getQuota({CancelToken? cancelToken}) async =>
      const FavoriteQuota(supportsFavorites: true, supportsPrepareSend: true);
  @override
  Future<FavoritePage> list(
      {String query = '',
      FavoriteKind? kind,
      String? tagID,
      String? cursor,
      int? baseline,
      int limit = 30,
      CancelToken? cancelToken}) async {
    lastTagID = tagID;
    return listHook != null
        ? listHook!(query, cursor, kind)
        : FavoritePage(items: List.of(serverItems));
  }

  @override
  Future<FavoriteItem> getDetail(String id, {CancelToken? cancelToken}) async =>
      serverItems.firstWhere((item) => item.id == id);
  @override
  Future<FavoriteItem> create(
      {required FavoriteKind kind,
      required FavoriteContent content,
      required String clientRequestID,
      String title = '',
      List<String> uploadIDs = const [],
      List<String> assetIDs = const [],
      CancelToken? cancelToken}) async {
    createRequests.add(clientRequestID);
    createdContent = content;
    if (failNextCreate) {
      failNextCreate = false;
      throw const FavoriteApiException('NETWORK_ERROR', '保存结果待确认',
          isUncertain: true);
    }
    final item = _item('saved', kind: kind);
    serverItems = [item];
    return item;
  }

  @override
  Future<FavoriteItem> update(String id,
      {required int expectedVersion,
      required String clientRequestID,
      String? title,
      FavoriteContent? content,
      List<String>? tagIDs,
      CancelToken? cancelToken}) async {
    patchTags = tagIDs;
    patchVersion = expectedVersion;
    final item = _item(id,
        version: expectedVersion + 1,
        tags: serverTags
            .where((tag) => tagIDs?.contains(tag.id) ?? false)
            .toList());
    serverItems = [item];
    return item;
  }

  @override
  Future<List<FavoriteTag>> listTags({CancelToken? cancelToken}) async =>
      failTagList
          ? throw const FavoriteApiException('NETWORK_ERROR', '标签离线')
          : List.of(serverTags);
  @override
  Future<FavoriteTag> createTag(String name,
      {required String clientRequestID, CancelToken? cancelToken}) async {
    final tag = FavoriteTag(id: 't1', name: name);
    serverTags = [tag];
    return tag;
  }

  @override
  Future<FavoriteTag> updateTag(String id, String name,
      {required int expectedVersion,
      required String clientRequestID,
      CancelToken? cancelToken}) async {
    final old = serverTags.firstWhere((tag) => tag.id == id);
    if (old.version != expectedVersion) {
      throw const FavoriteApiException('VERSION_CONFLICT', '标签已变更');
    }
    final tag = FavoriteTag(id: id, name: name, version: old.version + 1);
    serverTags = [tag];
    return tag;
  }

  @override
  Future<void> deleteTag(String id,
      {required int expectedVersion,
      required String clientRequestID,
      CancelToken? cancelToken}) async {
    serverTags.removeWhere((tag) => tag.id == id);
  }

  @override
  Future<FavoriteUploadSession> initializeUpload(
          {required String fileName,
          required String mimeType,
          required int sizeBytes,
          required String clientRequestID,
          CancelToken? cancelToken}) async =>
      FavoriteUploadSession(
          uploadID: 'u1',
          uploadURL: Uri.parse('https://storage.test/upload'),
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          maxSizeBytes: 100);
  @override
  Future<void> uploadFile(FavoriteUploadSession session, File file,
      {CancelToken? cancelToken, ProgressCallback? onProgress}) async {
    uploaded++;
  }

  @override
  Future<FavoriteAsset> completeUpload(String uploadID,
      {required String clientRequestID, CancelToken? cancelToken}) async {
    completed++;
    return FavoriteAsset(
        id: 'a1',
        coverAssetID: 'cover1',
        mimeType: 'video/mp4',
        sizeBytes: 4,
        sha256: List.filled(64, 'a').join());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('a failed pending write blocks network mutations and releases saving',
      () async {
    final api = _Api();
    final repo = FavoriteRepository(
        api: api,
        userIDProvider: () => 'me',
        cacheWriter: (key, value) async => false);
    addTearDown(repo.dispose);
    await expectLater(
        repo.createNote('private body'),
        throwsA(isA<FavoriteApiException>().having(
            (error) => error.code, 'local failure', 'LOCAL_SAVE_FAILED')));
    expect(api.createRequests, isEmpty);
    expect(repo.saving, isFalse);
    expect(repo.error, contains('设备存储'));
  });
  test(
      'completed media must be durable before create and can retry without another upload',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('favorite-durability-test-');
    final file = File('${directory.path}/original.mp4');
    await file.writeAsBytes([1, 2, 3, 4]);
    addTearDown(() async {
      await file.delete();
      await directory.delete();
    });
    final api = _Api();
    var denyCompleted = true;
    final repo = FavoriteRepository(
        api: api,
        userIDProvider: () => 'me',
        cacheWriter: (key, value) async {
          final json = jsonDecode(value) as Map;
          if (denyCompleted &&
              (json['mediaTasks'] as Map)
                  .values
                  .any((task) => (task as Map)['asset'] is Map)) {
            return false;
          }
          return (await SharedPreferences.getInstance()).setString(key, value);
        });
    addTearDown(repo.dispose);
    await expectLater(
        repo.createMedia(kind: FavoriteKind.video, filePath: file.path),
        throwsA(isA<FavoriteApiException>().having(
            (error) => error.code, 'local failure', 'LOCAL_SAVE_FAILED')));
    expect(api.uploaded, 1);
    expect(api.completed, 1);
    expect(api.createRequests, isEmpty);
    expect(repo.saving, isFalse);
    denyCompleted = false;
    await repo.createMedia(kind: FavoriteKind.video, filePath: file.path);
    expect(api.uploaded, 1);
    expect(api.completed, 1);
    expect(api.createRequests, hasLength(1));
  });
  test(
      'confirmed writes remain successful when only subsequent metadata caching fails',
      () async {
    final api = _Api();
    final repo = FavoriteRepository(
        api: api,
        userIDProvider: () => 'me',
        cacheWriter: (key, value) async {
          final json = jsonDecode(value) as Map;
          if ((json['requests'] as Map).isEmpty) return false;
          return (await SharedPreferences.getInstance()).setString(key, value);
        });
    addTearDown(repo.dispose);
    final item = await repo.createNote('saved');
    expect(item.id, 'saved');
    expect(repo.error, isNull);
    expect(repo.saving, isFalse);
  });
  test('persisted pending request keys are hashes and do not contain note body',
      () async {
    const privateText = 'This note body must never occur in the metadata cache';
    final api = _Api()..failNextCreate = true;
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(
        repo.createNote(privateText), throwsA(isA<FavoriteApiException>()));
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${repo.accountNamespace}:metadata:v1')!;
    expect(raw, isNot(contains(privateText)));
    final requests = (jsonDecode(raw) as Map)['requests'] as Map;
    expect(requests, hasLength(1));
    expect(requests.keys.single, matches(RegExp(r'^[a-f0-9]{64}$')));
    final resumed = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(resumed.dispose);
    await resumed.createNote(privateText);
    expect(api.createRequests.first, api.createRequests.last);
  });
  test(
      'text editor refuses mixed notes instead of discarding their media blocks',
      () async {
    final api = _Api()
      ..serverItems = [
        const FavoriteItem(
            id: 'mixed',
            kind: FavoriteKind.note,
            title: '图文',
            version: 1,
            status: FavoriteStatus.ready,
            content: FavoriteContent(kind: FavoriteKind.note, blocks: [
              FavoriteBlock(id: 'text', type: 'text', text: '说明'),
              FavoriteBlock(id: 'photo', type: 'image', assetID: 'a1')
            ]))
      ];
    final repo = FavoriteRepository(
        api: api, userIDProvider: () => 'me', cacheEnabled: false);
    addTearDown(repo.dispose);
    await expectLater(
        repo.updateNote('mixed', '只改文字'),
        throwsA(isA<FavoriteApiException>().having(
            (error) => error.code, 'unsupported', 'UNSUPPORTED_CONTENT')));
    expect(api.patchVersion, isNull);
    expect(api.serverItems.single.blocks, hasLength(2));
  });
  test('P0 repository blocks tag operations and leaves existing content intact',
      () async {
    final api = _Api()..serverItems = [_item('f1', version: 7)];
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await repo.refresh();
    await repo.refreshTags();
    expect(repo.tagError, contains('暂未开放'));
    await expectLater(
        repo.createTag('工作'), throwsA(isA<FavoriteApiException>()));
    await expectLater(
        repo.updateTags('f1', ['t1']), throwsA(isA<FavoriteApiException>()));
    expect(api.patchVersion, isNull);
    expect(repo.items.single.version, 7);
  });
  test('links preserve explicit URL content and reject executable schemes',
      () async {
    final api = _Api();
    final repo = FavoriteRepository(
        api: api, userIDProvider: () => 'me', cacheEnabled: false);
    addTearDown(repo.dispose);
    expect(() => repo.createLink('javascript:alert(1)'),
        throwsA(isA<FavoriteApiException>()));
    await repo.createLink('https://example.com/path?q=hello', title: '链接');
    expect(api.createdContent!.kind, FavoriteKind.link);
    expect(api.createdContent!.blocks.single.data['url'],
        'https://example.com/path?q=hello');
  });
  test(
      'loading a detail outside a filter does not insert it into query results',
      () async {
    final api = _Api()
      ..serverItems = [_item('other')]
      ..listHook = (query, cursor, kind) =>
          Future.value(FavoritePage(items: [_item('visible')]));
    final repo = FavoriteRepository(
        api: api, userIDProvider: () => 'me', cacheEnabled: false);
    addTearDown(repo.dispose);
    await repo.refresh(query: 'visible');
    await repo.getDetail('other');
    expect(repo.items.map((item) => item.id), ['visible']);
  });
  test('late responses cannot insert another account favorites', () async {
    var user = 'alice';
    final first = Completer<FavoritePage>();
    var calls = 0;
    final api = _Api()
      ..listHook = (query, cursor, kind) {
        calls++;
        return calls == 1
            ? first.future
            : Future.value(FavoritePage(items: [_item('bob-item')]));
      };
    final repo = FavoriteRepository(
        api: api, userIDProvider: () => user, cacheEnabled: false);
    addTearDown(repo.dispose);
    final old = repo.refresh();
    await Future<void>.delayed(Duration.zero);
    final oldScope = repo.sessionScope;
    user = 'bob';
    await repo.refresh();
    first.complete(FavoritePage(items: [_item('alice-private')]));
    await old;
    expect(repo.items.single.id, 'bob-item');
    expect(repo.isSessionCurrent(oldScope), isFalse);
    expect(repo.accountNamespace, contains('bob'));
    expect(repo.sessionScope, isNot(contains('token')));
  });
  test(
      'out of order search response and old pagination cannot replace new query',
      () async {
    final oldPage = Completer<FavoritePage>();
    final api = _Api()
      ..listHook = (query, cursor, kind) => query == 'old'
          ? oldPage.future
          : Future.value(FavoritePage(items: [_item('new-result')]));
    final repo = FavoriteRepository(
        api: api, userIDProvider: () => 'me', cacheEnabled: false);
    addTearDown(repo.dispose);
    final old = repo.refresh(query: 'old', kind: FavoriteKind.image);
    await Future<void>.delayed(Duration.zero);
    await repo.refresh(query: 'new', kind: null);
    oldPage.complete(FavoritePage(items: [_item('old-result')]));
    await old;
    expect(repo.items.single.id, 'new-result');
    expect(repo.query, 'new');
    expect(repo.filterKind, isNull);
  });
  test(
      'uncertain create retries reuse request ID and cloud refresh confirms saved item',
      () async {
    final api = _Api()..failNextCreate = true;
    final repo = FavoriteRepository(
        api: api, userIDProvider: () => 'me', cacheEnabled: false);
    addTearDown(repo.dispose);
    await expectLater(
        repo.createNote('hello'), throwsA(isA<FavoriteApiException>()));
    expect(repo.items, isEmpty);
    expect(repo.error, isNotNull);
    await repo.createNote('hello');
    expect(api.createRequests[0], api.createRequests[1]);
    expect(repo.items.single.id, 'saved');
    expect(repo.saving, isFalse);
    await repo.createNote('hello');
    expect(api.createRequests[2], isNot(api.createRequests[1]));
  });
  test(
      'media create failure retries completed original without uploading again',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('favorite-repository-test-');
    final file = File('${directory.path}/original.mp4');
    await file.writeAsBytes([1, 2, 3, 4]);
    addTearDown(() async {
      await file.delete();
      await directory.delete();
    });
    final api = _Api()..failNextCreate = true;
    final repo = FavoriteRepository(
        api: api, userIDProvider: () => 'me', cacheEnabled: false);
    addTearDown(repo.dispose);
    await expectLater(
        repo.createMedia(kind: FavoriteKind.video, filePath: file.path),
        throwsA(isA<FavoriteApiException>()));
    await repo.createMedia(kind: FavoriteKind.video, filePath: file.path);
    expect(api.uploaded, 1);
    expect(api.completed, 1);
    expect(api.createRequests.first, api.createRequests.last);
  });
  test(
      'restart preserves completed asset and create request after an unknown result',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('favorite-restart-test-');
    final file = File('${directory.path}/original.mp4');
    await file.writeAsBytes([1, 2, 3, 4]);
    addTearDown(() async {
      if (await file.exists()) await file.delete();
      await directory.delete();
    });
    final before = _Api()..failNextCreate = true;
    final first = FavoriteRepository(api: before, userIDProvider: () => 'me');
    await expectLater(
        first.createMedia(kind: FavoriteKind.video, filePath: file.path),
        throwsA(isA<FavoriteApiException>()));
    first.dispose();
    await file.delete();
    final after = _Api();
    final resumed = FavoriteRepository(api: after, userIDProvider: () => 'me');
    addTearDown(resumed.dispose);
    await resumed.createMedia(kind: FavoriteKind.video, filePath: file.path);
    expect(after.uploaded, 0);
    expect(after.completed, 0);
    expect(after.createRequests.single, before.createRequests.single);
  });
  test(
      'cache is isolated by account and service and contains only lightweight metadata',
      () async {
    final api = _Api()..serverItems = [_item('cloud')];
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    await repo.refresh();
    repo.dispose();
    final offline = _Api()
      ..listHook = (query, cursor, kind) =>
          Future.error(const FavoriteApiException('NETWORK_ERROR', '离线'));
    final restored =
        FavoriteRepository(api: offline, userIDProvider: () => 'me');
    addTearDown(restored.dispose);
    await restored.refresh();
    expect(restored.items.single.id, 'cloud');
    expect(restored.items.single.content, isNull);
    expect(restored.isCached, isTrue);
    final other =
        FavoriteRepository(api: offline, userIDProvider: () => 'other');
    addTearDown(other.dispose);
    await other.refresh();
    expect(other.items, isEmpty);
  });
}
