import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

FavoriteItem record(String id,
        {int version = 1, int at = 10, bool detail = true}) =>
    FavoriteItem(
        id: id,
        kind: FavoriteKind.note,
        title: id,
        version: version,
        status: FavoriteStatus.ready,
        contentRevision: 'r$version',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
        content: detail
            ? const FavoriteContent(
                kind: FavoriteKind.note,
                blocks: [FavoriteBlock(id: 'b1', type: 'text', text: 'text')])
            : null);
FavoriteChange upsert(FavoriteItem item) => FavoriteChange(
    id: item.id,
    version: item.version,
    operation: 'upsert',
    updatedAt: item.updatedAt!.millisecondsSinceEpoch,
    item: item);

class Cloud extends FavoriteApi {
  Cloud() : super(baseUrl: 'https://chat.test', tokenProvider: () => 'token');
  FavoriteQuota capabilities =
      const FavoriteQuota(supportsFavorites: true, supportsPrepareSend: true);
  Future<FavoriteQuota> Function()? quotaHook;
  Future<FavoritePage> Function(String?, int?)? listHook;
  Future<FavoriteChangesPage> Function(int)? changesHook;
  final watermarks = <int>[];
  final creates = <String>[];
  List<FavoriteItem> rows = [];
  int listCalls = 0;
  int quotaCalls = 0;
  int updateCalls = 0;
  bool failCreate = false;
  bool conflictUpdate = false;
  bool uncertainUpdate = false;
  int? createErrorCode;
  Future<FavoriteItem> Function(String)? createHook;
  @override
  Future<FavoriteQuota> getQuota({CancelToken? cancelToken}) async {
    quotaCalls++;
    return quotaHook == null ? capabilities : quotaHook!();
  }

  @override
  Future<FavoritePage> list(
      {String query = '',
      FavoriteKind? kind,
      String? tagID,
      String? cursor,
      int? baseline,
      int limit = 30,
      CancelToken? cancelToken}) async {
    listCalls++;
    return listHook == null
        ? FavoritePage(items: List.of(rows), syncAt: 900)
        : listHook!(cursor, baseline);
  }

  @override
  Future<FavoriteItem> getDetail(String id, {CancelToken? cancelToken}) async =>
      rows.firstWhere((item) => item.id == id);
  @override
  Future<FavoriteChangesPage> changes(
      {required int updatedAfter,
      int limit = 100,
      CancelToken? cancelToken}) async {
    watermarks.add(updatedAfter);
    return changesHook == null
        ? FavoriteChangesPage(events: [], syncAt: updatedAfter + 100)
        : changesHook!(updatedAfter);
  }

  @override
  Future<FavoriteItem> create(
      {required FavoriteKind kind,
      required FavoriteContent content,
      required String clientRequestID,
      String title = '',
      List<String> uploadIDs = const [],
      List<String> assetIDs = const [],
      CancelToken? cancelToken}) async {
    creates.add(clientRequestID);
    if (createHook != null) return createHook!(clientRequestID);
    if (createErrorCode != null) {
      final code = createErrorCode!;
      createErrorCode = null;
      throw FavoriteApiException(code, '请求对应收藏已删除');
    }
    if (failCreate) {
      failCreate = false;
      throw const FavoriteApiException('NETWORK_ERROR', '结果待确认',
          isUncertain: true);
    }
    final item = record('saved');
    rows = [item];
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
    updateCalls++;
    if (uncertainUpdate) {
      uncertainUpdate = false;
      throw const FavoriteApiException('NETWORK_ERROR', '编辑结果待确认',
          isUncertain: true);
    }
    if (conflictUpdate) {
      throw FavoriteApiException(20061, '版本冲突',
          currentItem: record(id, version: 9));
    }
    final item = record(id, version: expectedVersion + 1);
    rows = [item];
    return item;
  }

  @override
  Future<void> delete(String id,
      {required int expectedVersion,
      required String clientRequestID,
      CancelToken? cancelToken}) async {}
}

class FaultStore implements FavoriteMutationOutboxStore {
  final values = <String, String>{};
  bool failRead = false;
  bool failWrite = false;
  bool failComplete = false;
  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('disk');
    return values[key];
  }

  @override
  Future<bool> write(String key, String value) async {
    final json = jsonDecode(value) as Map;
    if (failWrite ||
        (failComplete &&
            (json['pending'] as List).isEmpty &&
            (json['confirmed'] as Map).isNotEmpty)) {
      return false;
    }
    values[key] = value;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('unknown and either false capability block cloud list and creation',
      () async {
    final api = Cloud()
      ..rows = [record('private')]
      ..capabilities = const FavoriteQuota(
          supportsFavorites: true, supportsPrepareSend: false);
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    expect(repo.available, isFalse);
    expect(repo.items, isEmpty);
    await repo.refresh();
    expect(repo.available, isFalse);
    expect(api.listCalls, 0);
    await expectLater(
        repo.createNote('note'), throwsA(isA<FavoriteApiException>()));
    expect(api.creates, isEmpty);
    api.capabilities =
        const FavoriteQuota(supportsFavorites: true, supportsPrepareSend: true);
    await repo.ensureCapabilities(force: true);
    await repo.refresh();
    expect(repo.available, isTrue);
    expect(repo.items.single.id, 'private');
  });

  test(
      'quota failures fail closed and late account responses cannot reopen capabilities',
      () async {
    final first = Completer<FavoriteQuota>();
    final api = Cloud()..quotaHook = (() => first.future);
    var user = 'alice';
    final repo = FavoriteRepository(api: api, userIDProvider: () => user);
    addTearDown(repo.dispose);
    final loading = repo.ensureCapabilities();
    await Future<void>.delayed(Duration.zero);
    user = 'bob';
    expect(repo.available, isFalse);
    first.complete(const FavoriteQuota(
        supportsFavorites: true, supportsPrepareSend: true));
    await expectLater(
        loading,
        throwsA(isA<FavoriteApiException>()
            .having((e) => e.isCancelled, 'old session', true)));
    expect(repo.quota, isNull);
    api.quotaHook =
        () async => throw const FavoriteApiException('NETWORK_ERROR', '无法读取能力');
    await expectLater(
        repo.ensureCapabilities(), throwsA(isA<FavoriteApiException>()));
    expect(repo.capabilityError, '无法读取能力');
    expect(repo.available, isFalse);
    api.quotaHook = null;
    await repo.ensureCapabilities(force: true);
    expect(repo.available, isTrue);
    expect(repo.capabilityError, isNull);
  });

  test('all later list pages retain the exact first-page syncAt baseline',
      () async {
    final received = <int?>[];
    final api = Cloud()
      ..listHook = ((cursor, baseline) async {
        received.add(baseline);
        return cursor == null
            ? FavoritePage(
                items: [record('a')], nextCursor: 'next', syncAt: 789)
            : FavoritePage(items: [record('b')], syncAt: 789);
      });
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await repo.refresh();
    await repo.loadMore();
    expect(received, [null, 789]);
    expect(repo.items.map((item) => item.id), ['a', 'b']);
  });

  test(
      'full same-millisecond delta group continues and persists server watermark',
      () async {
    final rows =
        List.generate(101, (index) => record('f$index', detail: false));
    final api = Cloud()
      ..rows = rows
      ..changesHook = ((after) async => after == 0
          ? FavoriteChangesPage(events: rows.map(upsert).toList(), syncAt: 10)
          : const FavoriteChangesPage(events: [], syncAt: 20));
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await repo.syncChanges();
    expect(api.watermarks, [0, 10]);
    expect(repo.syncAt, 20);
    final prefs = await SharedPreferences.getInstance();
    final cache =
        jsonDecode(prefs.getString('${repo.accountNamespace}:metadata:v1')!)
            as Map;
    expect(cache['sync']['syncAt'], 20);
    expect(cache['sync']['items'], hasLength(101));
    expect(repo.syncError, isNull);
  });

  test('server tombstones and versions reject late stale pages and details',
      () async {
    final api = Cloud()
      ..rows = [record('f1', version: 5)]
      ..changesHook = ((after) async => FavoriteChangesPage(events: [
            const FavoriteChange(
                id: 'f1', version: 6, operation: 'delete', updatedAt: 100)
          ], syncAt: 200));
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await repo.refresh();
    await repo.getDetail('f1');
    await repo.syncChanges();
    expect(repo.items, isEmpty);
    await expectLater(
        repo.getDetail('f1'), throwsA(isA<FavoriteApiException>()));
    await repo.refresh();
    expect(repo.items, isEmpty);
  });

  test(
      'idempotent delete success cannot resurrect a later stale original version',
      () async {
    final api = Cloud()..rows = [record('deleted', version: 3)];
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await repo.refresh();
    await repo.delete('deleted', expectedVersion: 3);
    api.rows = [record('deleted', version: 6)];
    await expectLater(
        repo.getDetail('deleted'), throwsA(isA<FavoriteApiException>()));
    await repo.refresh();
    expect(repo.items, isEmpty);
  });

  test(
      '20064 clears old filtered display cache and retains exact pending create for replay',
      () async {
    final api = Cloud()
      ..rows = [record('old')]
      ..changesHook =
          ((after) async => const FavoriteChangesPage(events: [], syncAt: 500));
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await repo.refresh();
    await repo.syncChanges();
    api.failCreate = true;
    await expectLater(repo.createNote('pending original body'),
        throwsA(isA<FavoriteApiException>()));
    final originalID = api.creates.single;
    await repo.refresh(query: 'keyword');
    api.rows = [];
    api.changesHook = ((after) async {
      if (after == 500) throw const FavoriteApiException(20064, '过期');
      return const FavoriteChangesPage(events: [], syncAt: 600);
    });
    await repo.syncChanges();
    expect(api.watermarks, [0, 500, 0]);
    expect(api.creates.last, originalID);
    expect(repo.pendingRecovery, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    final cache =
        jsonDecode(prefs.getString('${repo.accountNamespace}:metadata:v1')!)
            as Map;
    expect(
        (cache['items'] as List).any((item) => item['id'] == 'old'), isFalse);
    final restarted = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(restarted.dispose);
    await restarted.ensureCapabilities();
    expect(restarted.items.any((item) => item.id == 'old'), isFalse);
  });

  test('watermark is not advanced when strict sync cache commit fails',
      () async {
    final api = Cloud()
      ..changesHook = ((after) async =>
          FavoriteChangesPage(events: [upsert(record('f'))], syncAt: 20));
    var fail = true;
    final repo = FavoriteRepository(
        api: api,
        userIDProvider: () => 'me',
        cacheWriter: (key, value) async {
          if (fail) return false;
          return (await SharedPreferences.getInstance()).setString(key, value);
        });
    addTearDown(repo.dispose);
    await expectLater(repo.syncChanges(), throwsA(isA<FavoriteApiException>()));
    expect(repo.syncAt, 0);
    expect(repo.syncError, contains('设备存储'));
    fail = false;
    await repo.syncChanges();
    expect(api.watermarks, [0, 0]);
    expect(repo.syncAt, 20);
  });

  test(
      'outbox write failure blocks request and a failed read can recover on retry',
      () async {
    final api = Cloud();
    final store = FaultStore()..failRead = true;
    final repo = FavoriteRepository(
        api: api,
        userIDProvider: () => 'me',
        outbox: FavoriteMutationOutbox(store: store));
    addTearDown(repo.dispose);
    await expectLater(
        repo.createNote('private'), throwsA(isA<FavoriteApiException>()));
    store.failRead = false;
    store.failWrite = true;
    await expectLater(
        repo.createNote('private'), throwsA(isA<FavoriteApiException>()));
    expect(api.creates, isEmpty);
    expect(repo.saving, isFalse);
    store.failWrite = false;
    await repo.createNote('private');
    expect(api.creates, hasLength(1));
  });

  test(
      'confirmed cleanup failure retains body and UUID until safe replay completes',
      () async {
    final api = Cloud();
    final store = FaultStore()..failComplete = true;
    final repo = FavoriteRepository(
        api: api,
        userIDProvider: () => 'me',
        outbox: FavoriteMutationOutbox(store: store));
    addTearDown(repo.dispose);
    await repo.createNote('confirmed');
    expect(repo.pendingRecovery, hasLength(1));
    expect(repo.replayError, isNotNull);
    store.failComplete = false;
    await repo.replayPendingMutations();
    expect(api.creates, hasLength(2));
    expect(api.creates.first, api.creates.last);
    expect(repo.pendingRecovery, isEmpty);
  });

  test(
      'unknown notes replay after restart with exact text and UUID; no SDK task is created',
      () async {
    final api = Cloud()..failCreate = true;
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(repo.createNote('body after restart'),
        throwsA(isA<FavoriteApiException>()));
    final id = api.creates.single;
    final restarted = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(restarted.dispose);
    await restarted.syncChanges();
    expect(api.creates.last, id);
    expect(restarted.pendingRecovery, isEmpty);
  });

  test(
      'version conflict preserves recovery body and never silently retries a newer version',
      () async {
    final api = Cloud()
      ..rows = [record('note', version: 3)]
      ..conflictUpdate = true;
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(
        repo.updateNote('note', 'my private edit', expectedVersion: 3),
        throwsA(isA<FavoriteApiException>()));
    expect(repo.pendingRecovery.single.body['content']['blocks'][0]['text'],
        'my private edit');
    expect(repo.replayError, contains('版本冲突'));
    await repo.replayPendingMutations();
    expect(api.updateCalls, 1);
  });

  test(
      'active pending writes are skipped until their original request concludes',
      () async {
    final waiting = Completer<FavoriteItem>();
    final started = Completer<void>();
    final api = Cloud()
      ..createHook = ((request) {
        started.complete();
        return waiting.future;
      });
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    final saving = repo.createNote('active');
    await started.future;
    expect(repo.pendingRecovery, hasLength(1));
    await repo.replayPendingMutations();
    expect(api.creates, hasLength(1));
    waiting.complete(record('saved'));
    await saving;
    expect(repo.pendingRecovery, isEmpty);
  });

  test('20067 terminates an old UUID even if subsequent metadata cleanup fails',
      () async {
    final api = Cloud()..createErrorCode = 20067;
    final repo = FavoriteRepository(
        api: api,
        userIDProvider: () => 'me',
        cacheWriter: (key, value) async {
          final payload = jsonDecode(value) as Map;
          if ((payload['requests'] as Map).isEmpty) return false;
          return (await SharedPreferences.getInstance()).setString(key, value);
        });
    addTearDown(repo.dispose);
    await expectLater(
        repo.createNote('again'), throwsA(isA<FavoriteApiException>()));
    final oldID = api.creates.single;
    expect(repo.pendingRecovery, isEmpty);
    final restarted = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(restarted.dispose);
    await restarted.createNote('again');
    expect(api.creates.last, isNot(oldID));
  });

  test(
      'reviewed replacement only clears conclusive conflict drafts, preserving unknown edits',
      () async {
    final api = Cloud()
      ..rows = [record('note', version: 3)]
      ..conflictUpdate = true;
    final repo = FavoriteRepository(api: api, userIDProvider: () => 'me');
    addTearDown(repo.dispose);
    await expectLater(
        repo.updateNote('note', 'conflicting edit', expectedVersion: 3),
        throwsA(isA<FavoriteApiException>()));
    await repo.resolveConflictingEdits('note', throughVersion: 2);
    expect(repo.pendingRecovery, hasLength(1));
    api.conflictUpdate = false;
    api.uncertainUpdate = true;
    await expectLater(
        repo.updateNote('note', 'unknown edit', expectedVersion: 2),
        throwsA(isA<FavoriteApiException>()));
    await repo.updateNote('note', 'reviewed replacement', expectedVersion: 9);
    await repo.resolveConflictingEdits('note', throughVersion: 8);
    expect(repo.pendingRecovery, hasLength(1));
    expect(repo.pendingRecovery.single.body['expectedVersion'], 2);
    expect(repo.pendingRecovery.single.body['content']['blocks'][0]['text'],
        'unknown edit');
  });
}
