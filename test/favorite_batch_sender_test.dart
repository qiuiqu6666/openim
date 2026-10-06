import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_batch_sender.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

import 'support/favorite_test_fakes.dart';

class MemoryBatchStore implements FavoriteBatchStore {
  final Map<String, String> values = {};
  bool failAfterAcceptedSend = false;
  @override
  Future<Map<String, dynamic>?> load(String key) async => values[key] == null
      ? null
      : jsonDecode(values[key]!) as Map<String, dynamic>;
  @override
  Future<void> save(String key, Map<String, dynamic> value) async {
    if (failAfterAcceptedSend && (value['completed'] as int) > 0) {
      throw StateError('disk full');
    }
    values[key] = jsonEncode(value);
  }

  @override
  Future<void> remove(String key) async => values.remove(key);
}

void main() {
  const first = FavoriteTarget(conversationID: 'first', userID: 'recipient-1');
  const second = FavoriteTarget(conversationID: 'second', groupID: 'group-2');
  final items = [favoriteTextItem(id: 'a'), favoriteTextItem(id: 'b')];
  FavoriteSendResult accepted(String id) => FavoriteSendResult.success(
      message: Message(clientMsgID: id, status: MessageStatus.succeeded));

  test('batch resume keeps targets and skips completed destination/item pairs',
      () async {
    final repository = FakeFavoriteRepository(items.first);
    final store = MemoryBatchStore();
    final acceptedIDs = <String>{};
    final sent = <String>[];
    var selects = 0;
    var fail = true;
    Future<FavoriteSendResult> send(item, target, String id) async {
      if (acceptedIDs.contains(id)) return accepted(id);
      if (fail && item.id == 'a' && target.key == second.key) {
        return FavoriteSendResult.failed(errorCode: 'PERMISSION');
      }
      sent.add('${item.id}:${target.conversationID}');
      acceptedIDs.add(id);
      return accepted(id);
    }

    Future<List<FavoriteTarget>?> select() async {
      selects++;
      return [first, second];
    }

    final batch = FavoriteBatchSender(
        repository: repository, sendItem: send, store: store);
    final partial = await batch.send(items, selectTargets: select);
    expect(partial.sentCount, 1);
    expect(partial.totalCount, 4);
    fail = false;
    // Simulate a restarted runtime while preserving its journal.
    final restarted = FavoriteBatchSender(
        repository: repository, sendItem: send, store: store);
    expect(
        (await restarted.send(items, selectTargets: select)).isSuccess, isTrue);
    expect(sent, ['a:first', 'a:second', 'b:first', 'b:second']);
    expect(selects, 1);
    expect(store.values, isEmpty);
    // A new intentional completed batch is a separate action.
    expect(
        (await restarted.send(items, selectTargets: select)).isSuccess, isTrue);
    expect(selects, 2);
    expect(sent.length, 8);
  });

  test('crash after SDK acceptance reuses the already persisted attempt ID',
      () async {
    final repository = FakeFavoriteRepository(items.first);
    final store = MemoryBatchStore()..failAfterAcceptedSend = true;
    final acceptedIDs = <String>{};
    var physicalSends = 0;
    Future<FavoriteSendResult> send(item, target, String id) async {
      if (acceptedIDs.add(id)) physicalSends++;
      return accepted(id);
    }

    final initial = FavoriteBatchSender(
        repository: repository, sendItem: send, store: store);
    expect(
        (await initial.send([items.first], selectTargets: () async => [first]))
            .isSuccess,
        isFalse);
    store.failAfterAcceptedSend = false;
    final restarted = FavoriteBatchSender(
        repository: repository, sendItem: send, store: store);
    expect(
        (await restarted.send([items.first],
                selectTargets: () async =>
                    throw StateError('must retain target')))
            .isSuccess,
        isTrue);
    expect(physicalSends, 1);
  });

  test('cancelled selection and an account switch never submit a message',
      () async {
    final repository = FakeFavoriteRepository(items.first);
    var sends = 0;
    final batch = FavoriteBatchSender(
        repository: repository,
        store: MemoryBatchStore(),
        sendItem: (_, __, id) async {
          sends++;
          return accepted(id);
        });
    expect((await batch.send(items, selectTargets: () async => null)).errorCode,
        'CANCELLED');
    expect(
        (await batch.send(items, selectTargets: () async {
          repository.owner = 'other';
          return [first];
        }))
            .errorCode,
        'SESSION_CHANGED');
    expect(sends, 0);
  });

  test('a definite first rejection releases the outdated revision and target',
      () async {
    final repository = FakeFavoriteRepository(items.first);
    final store = MemoryBatchStore();
    var rejects = true;
    var selects = 0;
    final destinations = <String>[];
    final batch = FavoriteBatchSender(
        repository: repository,
        store: store,
        sendItem: (_, target, id) async {
          destinations.add(target.conversationID);
          if (rejects) {
            return FavoriteSendResult.failed(
                errorCode: 'VERSION_CONFLICT', errorMessage: '收藏已变化');
          }
          return accepted(id);
        });
    final failed = await batch.send(items, selectTargets: () async {
      selects++;
      return [first];
    });
    expect(failed.errorCode, 'BATCH_RESELECT_REQUIRED');
    expect(store.values, isEmpty);
    rejects = false;
    expect(
        (await batch.send(items, selectTargets: () async {
          selects++;
          return [second];
        }))
            .isSuccess,
        isTrue);
    expect(selects, 2);
    expect(destinations, ['first', 'second', 'second']);
  });

  test(
      'explicit cancellation ends a partial batch without sending its remainder',
      () async {
    final repository = FakeFavoriteRepository(items.first);
    final store = MemoryBatchStore();
    final sent = <String>[];
    final batch = FavoriteBatchSender(
        repository: repository,
        store: store,
        sendItem: (item, target, id) async {
          if (target.key == second.key) {
            return FavoriteSendResult.unknown(clientMsgID: id);
          }
          sent.add(item.id);
          return accepted(id);
        });
    final pending =
        await batch.send(items, selectTargets: () async => [first, second]);
    expect(pending.status, FavoriteSendStatus.unknown);
    expect(pending.sentCount, 1);
    expect(store.values, isNotEmpty);
    await batch.cancel(items);
    expect(store.values, isEmpty);
    expect(sent, ['a']);
  });
}
