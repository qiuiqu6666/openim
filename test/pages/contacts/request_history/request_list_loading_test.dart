import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/request_history/data/request_history_store.dart';
import 'package:openim/pages/contacts/request_history/data/request_list_cache.dart';
import 'package:openim/pages/contacts/request_history/data/request_load_coordinator.dart';

void main() {
  test('snapshots are bounded, cloned, expire and are scoped to the session',
      () {
    var now = DateTime(2026);
    final cache = RequestListCache(now: () => now);
    final rows = List.generate(150, (i) => <String, dynamic>{'id': i});
    cache.save('a', 'token', RequestHistoryKind.friend, rows);
    List<Map<String, dynamic>> read(String account, String token) =>
        cache.read(account, token, RequestHistoryKind.friend, (row) => row);
    rows.first['id'] = -1;
    final snapshot = read('a', 'token');
    expect(snapshot, hasLength(100));
    expect(snapshot.first['id'], 0);
    snapshot.first['id'] = -2;
    expect(read('a', 'token').first['id'], 0);
    now = now.add(RequestListCache.lifetime);
    expect(read('a', 'token'), isEmpty);
    cache.save('a', 'token', RequestHistoryKind.friend, rows);
    expect(read('b', 'token'), isEmpty);
    expect(read('a', 'token'), isEmpty);
    cache.save('a', 'token', RequestHistoryKind.friend, rows);
    expect(read('a', 'new-token'), isEmpty);
  });

  test('coalesces duplicate loads and one trailing refresh', () async {
    final coordinator = RequestLoadCoordinator();
    final pending = Completer<void>();
    var calls = 0;
    Future<void> read() async {
      calls++;
      if (calls == 1) await pending.future;
    }

    final first = coordinator.run(read);
    expect(identical(first, coordinator.run(read)), isTrue);
    for (var i = 0; i < 10; i++) {
      coordinator.run(read, refreshAfter: true);
    }
    expect(calls, 1);
    pending.complete();
    await first;
    expect(calls, 2);
    coordinator.close();
    await coordinator.run(read);
    expect(calls, 2);
  });

  test('closing cancels a queued refresh and failures can retry', () async {
    final coordinator = RequestLoadCoordinator();
    await expectLater(coordinator.run(() async => throw StateError('offline')),
        throwsStateError);
    final pending = Completer<void>();
    final read = coordinator.run(() => pending.future);
    var repeated = false;
    coordinator.run(() async {
      repeated = true;
    }, refreshAfter: true);
    coordinator.close();
    pending.complete();
    await read;
    expect(repeated, isFalse);
  });
}
