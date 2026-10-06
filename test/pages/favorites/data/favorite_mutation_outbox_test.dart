import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/favorites/data/favorite_mutation_outbox.dart';

class _Store implements FavoriteMutationOutboxStore {
  final Map<String, String> values = {};
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

FavoriteMutationEntry _entry(String key,
        {String id = 'e8c21cc0-0a61-4cbe-883e-15a1e3e4a593'}) =>
    FavoriteMutationEntry(
      key: key,
      operation: FavoriteMutationOperation.create,
      clientRequestID: id,
      body: {
        'kind': 'note',
        'content': {
          'blocks': [
            {'type': 'text', 'text': 'recover this private draft'}
          ]
        }
      },
    );

void main() {
  test('restart preserves the exact request body and UUID in its own account',
      () async {
    final store = _Store();
    final initial = FavoriteMutationOutbox(store: store);
    await initial.put('service:alice', _entry('note-action'));
    final restarted = FavoriteMutationOutbox(store: store);
    final recovered = (await restarted.list('service:alice')).single;
    expect(recovered.clientRequestID, _entry('note-action').clientRequestID);
    expect(jsonEncode(recovered.body), jsonEncode(_entry('note-action').body));
    expect(await restarted.list('service:bob'), isEmpty);
    expect(await restarted.list('other-service:alice'), isEmpty);
  });

  test('concurrent writes and removals retain other pending operations',
      () async {
    final outbox = FavoriteMutationOutbox(store: _Store());
    await Future.wait([
      outbox.put('alice', _entry('first')),
      outbox.put('alice', _entry('second')),
    ]);
    await Future.wait([
      outbox.remove('alice', 'first'),
      outbox.put('alice', _entry('third')),
    ]);
    expect((await outbox.list('alice')).map((entry) => entry.key),
        ['second', 'third']);
  });

  test('failed durable write blocks the action and allows a later safe retry',
      () async {
    final store = _Store()..canWrite = false;
    final outbox = FavoriteMutationOutbox(store: store);
    await expectLater(
        outbox.put('alice', _entry('pending')), throwsA(isA<StateError>()));
    expect(await outbox.list('alice'), isEmpty);
    store.canWrite = true;
    await outbox.put('alice', _entry('pending'));
    expect((await outbox.list('alice')).single.key, 'pending');
    store.canWrite = false;
    await expectLater(
        outbox.remove('alice', 'pending'), throwsA(isA<StateError>()));
    expect((await outbox.list('alice')).single.key, 'pending');
  });

  test('an existing action cannot silently change its UUID or body', () async {
    final outbox = FavoriteMutationOutbox(store: _Store());
    await outbox.put('alice', _entry('pending'));
    await outbox.put('alice', _entry('pending'));
    await expectLater(
        outbox.put('alice',
            _entry('pending', id: '7a48c9dd-f8e5-401d-b1da-46003f1c2c63')),
        throwsA(isA<FormatException>()));
    expect((await outbox.list('alice')).single.clientRequestID,
        _entry('pending').clientRequestID);
  });

  test('confirmed UUID survives restart after display metadata cleanup fails',
      () async {
    final store = _Store();
    final outbox = FavoriteMutationOutbox(store: store);
    final original = _entry('same-content');
    await outbox.put('alice', original);
    await outbox.complete('alice', original.key, original.clientRequestID);
    final restarted = FavoriteMutationOutbox(store: store);
    expect(await restarted.list('alice'), isEmpty);
    expect((await restarted.readConfirmed('alice'))[original.key],
        original.clientRequestID);
    final next =
        _entry('same-content', id: '7a48c9dd-f8e5-401d-b1da-46003f1c2c63');
    await restarted.put('alice', next);
    await expectLater(
        restarted.complete('alice', original.key, original.clientRequestID),
        throwsA(isA<FormatException>()));
    expect((await restarted.list('alice')).single.clientRequestID,
        next.clientRequestID);
  });

  test('failed acknowledgement preserves body and UUID for safe rechecking',
      () async {
    final store = _Store();
    final outbox = FavoriteMutationOutbox(store: store);
    final entry = _entry('pending');
    await outbox.put('alice', entry);
    store.canWrite = false;
    await expectLater(
        outbox.complete('alice', entry.key, entry.clientRequestID),
        throwsA(isA<StateError>()));
    expect((await outbox.list('alice')).single.clientRequestID,
        entry.clientRequestID);
    expect(await outbox.readConfirmed('alice'), isEmpty);
    store.canWrite = true;
    await outbox.complete('alice', entry.key, entry.clientRequestID);
    expect(await outbox.list('alice'), isEmpty);
    expect(store.values.values.single,
        isNot(contains('recover this private draft')));
  });

  test('tokens and signed transport grants cannot enter persisted operations',
      () async {
    for (final forbidden in ['chatToken', 'token', 'uploadURL', 'downloads']) {
      expect(
          () => FavoriteMutationEntry(
                key: 'bad',
                operation: FavoriteMutationOperation.create,
                clientRequestID: _entry('id').clientRequestID,
                body: {
                  'nested': {forbidden: 'private credential'}
                },
              ),
          throwsA(isA<FormatException>()));
    }
  });
}
