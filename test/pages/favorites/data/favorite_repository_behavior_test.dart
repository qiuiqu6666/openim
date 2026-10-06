import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

FavoriteItem row(String id,
        {int version = 1,
        FavoriteStatus status = FavoriteStatus.ready,
        bool detail = true}) =>
    FavoriteItem(
        id: id,
        kind: FavoriteKind.note,
        title: '$id v$version',
        status: status,
        version: version,
        contentRevision: 'revision-$version',
        content: detail
            ? FavoriteContent(kind: FavoriteKind.note, blocks: [
                FavoriteBlock(id: 'text', type: 'text', text: 'body v$version')
              ])
            : null);

class BehaviorApi extends FavoriteApi {
  BehaviorApi()
      : super(
            baseUrl: 'https://chat.test', tokenProvider: () => 'test-session');
  List<FavoriteItem> rows = [];
  final detailCalls = <String>[];
  final deletes = <int>[];
  Future<FavoriteItem> Function(String)? detailHook;
  Future<FavoriteItem> Function(String)? createHook;

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
          CancelToken? cancelToken}) async =>
      FavoritePage(items: List.of(rows), syncAt: 100);

  @override
  Future<FavoriteItem> getDetail(String id, {CancelToken? cancelToken}) async {
    detailCalls.add(id);
    if (detailHook != null) return detailHook!(id);
    return rows.firstWhere((item) => item.id == id);
  }

  @override
  Future<void> delete(String id,
      {required int expectedVersion,
      required String clientRequestID,
      CancelToken? cancelToken}) async {
    deletes.add(expectedVersion);
    rows.removeWhere((item) => item.id == id);
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
      createHook!(clientRequestID);
}

class BatchBehaviorApi extends BehaviorApi {
  late FavoriteBatchDeleteResult batch;
  @override
  Future<FavoriteBatchDeleteResult> batchDelete(List<FavoriteItem> items,
          {required String clientRequestID, CancelToken? cancelToken}) async =>
      batch;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an explicit delete snapshot does not fetch an already missing detail',
      () async {
    final api = BehaviorApi()
      ..detailHook = ((_) async =>
          throw const FavoriteApiException(20050, 'already deleted'));
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await repo.delete('already-deleted', expectedVersion: 3);
    expect(api.detailCalls, isEmpty);
    expect(api.deletes, [3]);
    expect(repo.pendingRecovery, isEmpty);
  });

  test('version-only batch conflicts fetch their current body exactly once',
      () async {
    final api = BatchBehaviorApi()
      ..rows = [row('note', version: 3)]
      ..batch = const FavoriteBatchDeleteResult(items: [
        FavoriteDeleteResult(
            id: 'note',
            status: FavoriteDeleteStatus.versionConflict,
            version: 5)
      ])
      ..detailHook = ((id) async => row(id, version: 5));
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    final result = await repo.deleteMany([row('note', version: 3)]);
    expect(api.detailCalls, ['note']);
    expect(result.conflicts.single.version, 5);
    expect(result.conflicts.single.currentItem!.text, 'body v5');
    expect(repo.pendingRecovery, isEmpty);
  });

  test('failed conflict hydration keeps confirmed partial results and version',
      () async {
    final api = BatchBehaviorApi()
      ..rows = [row('gone'), row('note', version: 3)]
      ..batch = const FavoriteBatchDeleteResult(items: [
        FavoriteDeleteResult(
            id: 'gone', status: FavoriteDeleteStatus.deleted, version: 2),
        FavoriteDeleteResult(
            id: 'note',
            status: FavoriteDeleteStatus.versionConflict,
            version: 5)
      ])
      ..detailHook = ((_) async => throw const FavoriteApiException(
          'NETWORK_ERROR', 'read unavailable'));
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    final result =
        await repo.deleteMany([row('gone'), row('note', version: 3)]);
    expect(api.detailCalls, ['note']);
    expect(result.items.first.deleted, isTrue);
    expect(result.conflicts.single.version, 5);
    expect(result.conflicts.single.currentItem, isNull);
    expect(repo.pendingRecovery, isEmpty);
    expect(repo.items.single.id, 'note');
  });

  test('a batch conflict with a current body does not perform another read',
      () async {
    final api = BatchBehaviorApi()
      ..batch = FavoriteBatchDeleteResult(items: [
        FavoriteDeleteResult(
            id: 'note',
            status: FavoriteDeleteStatus.versionConflict,
            version: 5,
            currentItem: row('note', version: 5))
      ]);
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    final result = await repo.deleteMany([row('note', version: 3)]);
    expect(api.detailCalls, isEmpty);
    expect(result.conflicts.single.currentItem!.version, 5);
  });

  test('concurrent copies of one mutation cannot run or replace its UUID',
      () async {
    final started = Completer<void>();
    final response = Completer<FavoriteItem>();
    final ids = <String>[];
    final api = BehaviorApi()
      ..createHook = ((id) {
        ids.add(id);
        if (ids.length == 1) {
          started.complete();
          return response.future;
        }
        return Future.value(row('next'));
      });
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    final first = repo.createNote('same');
    await started.future;
    await expectLater(
        repo.createNote('same', clientRequestID: FavoriteApi.newRequestID()),
        throwsA(isA<FavoriteApiException>()
            .having((error) => error.code, 'in flight', 'TASK_BUSY')));
    expect(ids, hasLength(1));
    expect(repo.saving, isTrue);
    response.complete(row('first'));
    await first;
    expect(repo.saving, isFalse);
    await repo.createNote('same');
    expect(ids.last, isNot(ids.first));
  });

  test('late detail readers receive the newer complete body', () async {
    final old = Completer<FavoriteItem>();
    final started = Completer<void>();
    var calls = 0;
    final api = BehaviorApi()
      ..detailHook = ((_) {
        if (calls++ == 0) {
          started.complete();
          return old.future;
        }
        return Future.value(row('note', version: 2));
      });
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    final first = repo.getDetail('note');
    await started.future;
    final current = await repo.getDetail('note');
    old.complete(row('note'));
    expect((await first).text, current.text);
    expect(current.version, 2);
    expect(api.detailCalls, hasLength(2));
  });

  test('newer list metadata causes one bounded current-body fetch', () async {
    final old = Completer<FavoriteItem>();
    final started = Completer<void>();
    var calls = 0;
    final api = BehaviorApi()
      ..rows = [row('note', version: 2, detail: false)]
      ..detailHook = ((_) {
        if (calls++ == 0) {
          started.complete();
          return old.future;
        }
        return Future.value(row('note', version: 2));
      });
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    final first = repo.getDetail('note');
    await started.future;
    await repo.refresh();
    old.complete(row('note'));
    expect((await first).text, 'body v2');
    expect(api.detailCalls, hasLength(2));
  });

  test('a detail response after confirmed deletion cannot reopen its body',
      () async {
    final old = Completer<FavoriteItem>();
    final started = Completer<void>();
    final api = BehaviorApi()
      ..detailHook = ((_) {
        started.complete();
        return old.future;
      });
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    final first = repo.getDetail('note');
    await started.future;
    await repo.delete('note', expectedVersion: 1);
    final rejected = expectLater(
        first,
        throwsA(isA<FavoriteApiException>()
            .having((error) => error.code, 'deleted', 20050)));
    old.complete(row('note'));
    await rejected;
    await expectLater(
        repo.getDetail('note'), throwsA(isA<FavoriteApiException>()));
    expect(api.detailCalls, hasLength(1));
  });

  test('one missing archive does not block the next original becoming ready',
      () {
    fakeAsync((async) {
      final api = BehaviorApi()
        ..rows = [
          row('gone', status: FavoriteStatus.pendingArchive),
          row('ready-next', status: FavoriteStatus.pendingArchive)
        ]
        ..detailHook = ((id) async {
          if (id == 'gone') {
            throw const FavoriteApiException(
                20050, 'removed by another device');
          }
          return row(id, version: 2);
        });
      final repo = FavoriteRepository(
          api: api,
          userIDProvider: () => 'me',
          pollInterval: const Duration(seconds: 1));
      repo.refresh();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(api.detailCalls, ['gone', 'ready-next']);
      expect(repo.items.single.id, 'ready-next');
      expect(repo.items.single.status, FavoriteStatus.ready);
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(api.detailCalls, hasLength(2));
      repo.dispose();
    });
  });

  test('one transient archive failure leaves it retryable and checks other IDs',
      () {
    fakeAsync((async) {
      final api = BehaviorApi()
        ..rows = [
          row('offline', status: FavoriteStatus.pendingArchive),
          row('ready-next', status: FavoriteStatus.pendingArchive)
        ]
        ..detailHook = ((id) async {
          if (id == 'offline') {
            throw const FavoriteApiException('NETWORK_ERROR', 'retry later');
          }
          return row(id, version: 2);
        });
      final repo = FavoriteRepository(
          api: api,
          userIDProvider: () => 'me',
          pollInterval: const Duration(seconds: 1));
      repo.refresh();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(api.detailCalls, ['offline', 'ready-next']);
      expect(repo.items.first.status, FavoriteStatus.pendingArchive);
      expect(repo.items.last.status, FavoriteStatus.ready);
      expect(repo.error, 'retry later');
      api.detailHook = (id) async => row(id, version: 2);
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(repo.items.every((item) => item.status == FavoriteStatus.ready),
          isTrue);
      repo.dispose();
    });
  });
}
