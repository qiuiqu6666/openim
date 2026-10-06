import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _request = '4e564e5a-dfac-4ad8-a2a8-c75ef6207773';
const _otherRequest = '568765b8-670f-4a6a-a87a-68e9d8a0f173';
const _ack = FavoriteArchiveRetryAck(
    jobID: 'job_1', status: FavoriteStatus.pendingArchive);

FavoriteItem _item(FavoriteStatus status) => FavoriteItem(
    id: 'fav_1',
    kind: FavoriteKind.image,
    title: '',
    version: status == FavoriteStatus.failed ? 2 : 3,
    status: status);

class _Store implements FavoriteMutationOutboxStore {
  final values = <String, String>{};
  bool canWrite = true;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<bool> write(String key, String value) async {
    if (!canWrite) return false;
    values[key] = value;
    return true;
  }
}

class _Api extends FavoriteApi {
  _Api()
      : super(baseUrl: 'https://chat.test', tokenProvider: () => 'test-token');
  FavoriteItem current = _item(FavoriteStatus.failed);
  final retryIDs = <String>[];
  int reads = 0;
  Future<FavoriteItem> Function()? onDetail;
  Future<FavoriteArchiveRetryAck> Function()? onRetry;
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
      FavoritePage(items: [current], syncAt: 100);
  @override
  Future<FavoriteItem> getDetail(String id, {CancelToken? cancelToken}) async {
    reads++;
    return onDetail == null ? current : await onDetail!();
  }

  @override
  Future<FavoriteArchiveRetryAck> retryArchive(String id,
      {required String clientRequestID, CancelToken? cancelToken}) async {
    retryIDs.add(clientRequestID);
    current = _item(FavoriteStatus.pendingArchive);
    return onRetry == null ? _ack : await onRetry!();
  }
}

FavoriteRepository _repository(_Api api, _Store store,
        {String? Function()? userIDProvider}) =>
    FavoriteRepository(
        api: api,
        outbox: FavoriteMutationOutbox(store: store),
        userIDProvider: userIDProvider ?? (() => 'alice'),
        pollInterval: const Duration(days: 1));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('deployed retry response contains a job acknowledgement and no item',
      () async {
    var response = <String, dynamic>{
      'jobID': 'job_1',
      'status': 'pending_archive'
    };
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        requests.add(request);
        handler.resolve(Response(
            requestOptions: request,
            statusCode: 200,
            data: {'errCode': 0, 'data': response}));
      }));
    final api = FavoriteApi(
        client: dio,
        baseUrl: 'https://chat.test',
        tokenProvider: () => 'private-test-token');
    final ack = await api.retryArchive('fav_1', clientRequestID: _request);
    expect(ack.jobID, 'job_1');
    expect(ack.status, FavoriteStatus.pendingArchive);
    expect(requests.single.uri.path, '/chat/favorites/fav_1/retry-archive');
    expect(requests.single.data, {'clientRequestID': _request});
    response = {'jobID': '', 'status': 'pending_archive'};
    await expectLater(api.retryArchive('fav_1', clientRequestID: _request),
        throwsFormatException);
    response = {'jobID': 'job_1', 'status': 'ready'};
    await expectLater(api.retryArchive('fav_1', clientRequestID: _request),
        throwsFormatException);
  });

  test('an acknowledged POST with a failed GET resumes by GET after restart',
      () async {
    final store = _Store();
    final api = _Api();
    api.onDetail = () async {
      if (api.reads == 2) {
        throw const FavoriteApiException('NETWORK_ERROR', 'offline');
      }
      return api.current;
    };
    final first = _repository(api, store);
    await expectLater(first.retryArchive('fav_1', clientRequestID: _request),
        throwsA(isA<FavoriteApiException>()));
    expect(api.retryIDs, [_request]);
    final pending = first.pendingRecovery.single;
    expect(pending.clientRequestID, _request);
    expect(pending.archiveRetryAck!.jobID, 'job_1');
    expect(jsonEncode(pending.body), jsonEncode({'clientRequestID': _request}));
    first.dispose();
    final restarted = _repository(api, store);
    addTearDown(restarted.dispose);
    await restarted.replayPendingMutations();
    expect(api.retryIDs, [_request]);
    expect(api.reads, 3);
    expect(restarted.pendingRecovery, isEmpty);
    expect(restarted.items.single.status, FavoriteStatus.pendingArchive);
  });

  test('receipt persistence failure keeps in-memory proof and original UUID',
      () async {
    final store = _Store();
    final api = _Api()
      ..onRetry = (() async {
        store.canWrite = false;
        return _ack;
      });
    final repository = _repository(api, store);
    addTearDown(repository.dispose);
    await expectLater(
        repository.retryArchive('fav_1', clientRequestID: _request),
        throwsA(isA<FavoriteApiException>().having(
            (error) => error.code,
            'specific receipt persistence failure',
            'ARCHIVE_RETRY_ACK_SAVE_FAILED')));
    expect(repository.pendingRecovery.single.clientRequestID, _request);
    expect(repository.pendingRecovery.single.archiveRetryAck!.jobID, 'job_1');
    store.canWrite = true;
    final confirmed = await repository.retryArchive('fav_1');
    expect(confirmed.status, FavoriteStatus.pendingArchive);
    expect(api.retryIDs, [_request]);
    expect(repository.pendingRecovery, isEmpty);
  });

  test('restart without a saved receipt checks pending status without POST',
      () async {
    final store = _Store();
    final api = _Api()
      ..onRetry = (() async {
        store.canWrite = false;
        return _ack;
      });
    final original = _repository(api, store);
    await expectLater(original.retryArchive('fav_1', clientRequestID: _request),
        throwsA(isA<FavoriteApiException>()));
    final namespace = original.accountNamespace;
    original.dispose();
    store.canWrite = true;
    expect(
        (await FavoriteMutationOutbox(store: store).list(namespace))
            .single
            .archiveRetryAck,
        isNull);
    final restarted = _repository(api, store);
    addTearDown(restarted.dispose);
    final item = await restarted.retryArchive('fav_1');
    expect(item.status, FavoriteStatus.pendingArchive);
    expect(api.retryIDs, [_request]);
    expect(restarted.pendingRecovery, isEmpty);
  });

  test('an old-server status race is reconciled by one detail read', () async {
    final api = _Api()
      ..onRetry =
          (() async => throw const FavoriteApiException(20057, 'changed'));
    final repository = _repository(api, _Store());
    addTearDown(repository.dispose);
    final item =
        await repository.retryArchive('fav_1', clientRequestID: _request);
    expect(item.status, FavoriteStatus.pendingArchive);
    expect(api.retryIDs, [_request]);
    expect(api.reads, 2);
    expect(repository.pendingRecovery, isEmpty);
  });

  test('a failed read after a status race preserves the unresolved request',
      () async {
    final api = _Api()
      ..onRetry =
          (() async => throw const FavoriteApiException(20057, 'changed'));
    api.onDetail = () async {
      if (api.reads == 2) {
        throw const FavoriteApiException('NETWORK_ERROR', 'offline');
      }
      return api.current;
    };
    final repository = _repository(api, _Store());
    addTearDown(repository.dispose);
    await expectLater(
        repository.retryArchive('fav_1', clientRequestID: _request),
        throwsA(isA<FavoriteApiException>().having(
            (error) => error.code,
            'readonly recovery remains pending',
            'ARCHIVE_RETRY_NEEDS_RECHECK')));
    expect(repository.pendingRecovery.single.clientRequestID, _request);
    await repository.retryArchive('fav_1');
    expect(api.retryIDs, [_request]);
  });

  test('a cancelled numeric error does not discard the unresolved UUID',
      () async {
    final api = _Api()
      ..onRetry = (() async => throw const FavoriteApiException(
          20056, 'cancelled response',
          isCancelled: true));
    final repository = _repository(api, _Store());
    addTearDown(repository.dispose);
    await expectLater(
        repository.retryArchive('fav_1', clientRequestID: _request),
        throwsA(isA<FavoriteApiException>()));
    expect(repository.pendingRecovery.single.clientRequestID, _request);
    expect(repository.pendingRecovery.single.archiveRetryAck, isNull);
    await repository.retryArchive('fav_1');
    expect(api.retryIDs, [_request]);
  });

  test('switching accounts during preflight prevents retry POST', () async {
    final gate = Completer<FavoriteItem>();
    final api = _Api()..onDetail = (() => gate.future);
    var userID = 'alice';
    final repository = _repository(api, _Store(), userIDProvider: () => userID);
    addTearDown(repository.dispose);
    final operation =
        repository.retryArchive('fav_1', clientRequestID: _request);
    while (api.reads == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    userID = 'bob';
    expect(repository.available, isFalse);
    gate.complete(_item(FavoriteStatus.failed));
    await expectLater(
        operation,
        throwsA(isA<FavoriteApiException>().having((error) => error.code,
            'guard before retry POST', 'SESSION_CHANGED')));
    expect(api.retryIDs, isEmpty);
  });

  test('a late acknowledgement cannot enter another account', () async {
    final gate = Completer<FavoriteArchiveRetryAck>();
    final api = _Api()..onRetry = (() => gate.future);
    final store = _Store();
    var userID = 'alice';
    final repository = _repository(api, store, userIDProvider: () => userID);
    addTearDown(repository.dispose);
    final operation =
        repository.retryArchive('fav_1', clientRequestID: _request);
    while (api.retryIDs.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final namespace = repository.accountNamespace;
    userID = 'bob';
    expect(repository.available, isFalse);
    gate.complete(_ack);
    await expectLater(
        operation,
        throwsA(isA<FavoriteApiException>().having(
            (error) => error.code, 'account guard', 'SESSION_CHANGED')));
    final outbox = FavoriteMutationOutbox(store: store);
    expect((await outbox.list(namespace)).single.archiveRetryAck, isNull);
    expect(await outbox.list(repository.accountNamespace), isEmpty);
  });

  test('durable receipt is account isolated and cannot change request identity',
      () async {
    final store = _Store();
    final outbox = FavoriteMutationOutbox(store: store);
    final entry = FavoriteMutationEntry(
        key: 'retry',
        operation: FavoriteMutationOperation.retryArchive,
        clientRequestID: _request,
        itemID: 'fav_1',
        body: {'clientRequestID': _request});
    await outbox.put('alice', entry);
    await outbox.acknowledgeArchiveRetry('alice', entry.key, _request, _ack);
    final restarted = FavoriteMutationOutbox(store: store);
    final restored = (await restarted.list('alice')).single;
    expect(restored.archiveRetryAck!.jobID, 'job_1');
    expect(restored.body, entry.body);
    expect(await restarted.list('bob'), isEmpty);
    await expectLater(
        restarted.acknowledgeArchiveRetry(
            'alice', entry.key, _otherRequest, _ack),
        throwsFormatException);
    await expectLater(
        restarted.acknowledgeArchiveRetry(
            'alice',
            entry.key,
            _request,
            const FavoriteArchiveRetryAck(
                jobID: 'another', status: FavoriteStatus.pendingArchive)),
        throwsFormatException);
    expect(
        (await restarted.list('alice')).single.archiveRetryAck!.jobID, 'job_1');
  });
}
