import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/favorite_batch_sender.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

import '../../../support/favorite_test_fakes.dart';

class _Store implements FavoriteBatchStore {
  Map<String, dynamic>? saved;
  int writes = 0;
  @override
  Future<Map<String, dynamic>?> load(String key) async => saved;
  @override
  Future<void> save(String key, Map<String, dynamic> value) async {
    writes++;
    saved = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> remove(String key) async => saved = null;
}

void main() {
  const target = FavoriteTarget(conversationID: 'chat', userID: 'recipient');

  test('unknown or disabled capability never opens target selection or submits',
      () async {
    final repository = FakeFavoriteRepository(favoriteTextItem())
      ..favoritesAvailable = false;
    addTearDown(repository.dispose);
    final store = _Store();
    var selections = 0;
    var sends = 0;
    final batch = FavoriteBatchSender(
      repository: repository,
      store: store,
      sendItem: (_, __, ___) async {
        sends++;
        throw StateError('must not submit');
      },
    );
    final result =
        await batch.send([repository.detail], selectTargets: () async {
      selections++;
      return [target];
    });
    expect(result.errorCode, 'FAVORITES_UNAVAILABLE');
    expect(selections, 0);
    expect(sends, 0);
    expect(store.writes, 0);
  });

  test('capability withdrawal stops remaining pairs and retains batch progress',
      () async {
    final repository = FakeFavoriteRepository(favoriteTextItem(id: 'a'));
    addTearDown(repository.dispose);
    final store = _Store();
    var sends = 0;
    final batch = FavoriteBatchSender(
      repository: repository,
      store: store,
      sendItem: (_, __, id) async {
        sends++;
        repository.favoritesAvailable = false;
        return FavoriteSendResult.success(
            message: Message(clientMsgID: id, status: MessageStatus.succeeded));
      },
    );
    final result = await batch.send(
        [repository.detail, favoriteTextItem(id: 'b')],
        selectTargets: () async => [target]);
    expect(result.errorCode, 'FAVORITES_UNAVAILABLE');
    expect(result.sentCount, 1);
    expect(sends, 1);
    expect(store.saved!['completed'], 1);
  });
}
