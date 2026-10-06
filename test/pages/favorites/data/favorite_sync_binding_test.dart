import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/favorites/data/favorite_sync_binding.dart';

void main() {
  test('only favoriteChanged hints trigger a coalesced authoritative sync', () {
    fakeAsync((clock) {
      final events = StreamController<String>(sync: true);
      var requests = 0;
      final binding = FavoriteSyncBinding(
        synchronize: () async => requests++,
        sessionScope: () => 'alice',
        isSessionCurrent: (scope) => scope == 'alice',
        notifications: events.stream,
        pollInterval: null,
        observeLifecycle: false,
      );
      events.add('invalid json');
      events.add('{"key":"moments"}');
      clock.elapse(const Duration(seconds: 1));
      expect(requests, 0);
      // No body is trusted: even an alleged record triggers only a GET sync.
      events.add('{"key":"favoriteChanged","data":{"id":"forged"}}');
      events.add('{"key":"favoriteChanged"}');
      clock.elapse(const Duration(milliseconds: 200));
      clock.flushMicrotasks();
      expect(requests, 1);
      binding.dispose();
      events.close();
    });
  });

  test('events arriving during a sync produce exactly one follow-up', () {
    fakeAsync((clock) {
      var requests = 0;
      final pending = Completer<void>();
      final binding = FavoriteSyncBinding(
        synchronize: () {
          requests++;
          return requests == 1 ? pending.future : Future<void>.value();
        },
        sessionScope: () => 'alice',
        isSessionCurrent: (scope) => scope == 'alice',
        pollInterval: null,
        observeLifecycle: false,
      );
      binding.requestSync();
      clock.elapse(const Duration(milliseconds: 200));
      expect(requests, 1);
      binding.requestSync();
      binding.requestSync();
      pending.complete();
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 200));
      clock.flushMicrotasks();
      expect(requests, 2);
      binding.dispose();
    });
  });

  test('background waits for resume and reconnect compensates missed hints',
      () {
    fakeAsync((clock) {
      final reconnects = StreamController<void>(sync: true);
      var requests = 0;
      final binding = FavoriteSyncBinding(
        synchronize: () async => requests++,
        sessionScope: () => 'alice',
        isSessionCurrent: (scope) => scope == 'alice',
        reconnected: reconnects.stream,
        pollInterval: const Duration(minutes: 1),
        observeLifecycle: false,
      );
      binding.didChangeAppLifecycleState(AppLifecycleState.paused);
      reconnects.add(null);
      clock.elapse(const Duration(minutes: 2));
      expect(requests, 0);
      binding.didChangeAppLifecycleState(AppLifecycleState.resumed);
      clock.elapse(const Duration(milliseconds: 200));
      clock.flushMicrotasks();
      expect(requests, 1);
      clock.elapse(const Duration(minutes: 1));
      clock.flushMicrotasks();
      expect(requests, 2);
      binding.dispose();
      reconnects.close();
      clock.elapse(const Duration(minutes: 2));
      expect(requests, 2);
    });
  });

  test('old scheduled account work and disposed listeners do not synchronize',
      () {
    fakeAsync((clock) {
      final events = StreamController<String>(sync: true);
      var owner = 'alice';
      var requests = 0;
      final binding = FavoriteSyncBinding(
        synchronize: () async => requests++,
        sessionScope: () => owner,
        isSessionCurrent: (scope) => scope == owner,
        notifications: events.stream,
        pollInterval: null,
        observeLifecycle: false,
      );
      events.add('{"key":"favoriteChanged"}');
      owner = 'bob';
      clock.elapse(const Duration(milliseconds: 200));
      expect(requests, 0);
      binding.dispose();
      events.add('{"key":"favoriteChanged"}');
      clock.elapse(const Duration(seconds: 1));
      expect(requests, 0);
      events.close();
    });
  });
}
