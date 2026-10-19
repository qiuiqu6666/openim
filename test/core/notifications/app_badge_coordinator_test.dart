import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/notifications/app_badge_coordinator.dart';

void main() {
  test('continuous updates send latest once a second without delaying launcher',
      () {
    fakeAsync((time) {
      final remote = <int>[];
      final local = <int>[];
      final badge = AppBadgeCoordinator(
        updateRemote: (n) async => remote.add(n),
        isSystemSupported: () async => true,
        updateSystem: (n) async => local.add(n),
        onError: (e) => fail('$e'),
        now: () => DateTime(2026).add(time.elapsed),
      )..beginSession('a');
      badge.setCount(1);
      time.elapse(Duration.zero);
      for (var n = 2; n <= 31; n++) {
        time.elapse(const Duration(milliseconds: 100));
        badge.setCount(n);
        time.elapse(Duration.zero);
      }
      expect(remote, [1, 10, 20, 30]);
      expect(local.last, 31);
      badge.setCount(0);
      badge.onForeground();
      time.elapse(const Duration(seconds: 1));
      expect(remote, [1, 10, 20, 30, 0]);
      badge.setCount(0);
      time.elapse(const Duration(seconds: 10));
      expect(remote.length, 5);
      badge.close();
    });
  });

  test('slow request is serialized and trailing value restores A after B', () {
    fakeAsync((time) {
      final remote = <int>[];
      final pending = <Completer<void>>[];
      final badge = AppBadgeCoordinator(
        updateRemote: (n) {
          remote.add(n);
          final c = Completer<void>();
          pending.add(c);
          return c.future;
        },
        isSystemSupported: () async => false,
        updateSystem: (_) async {},
        onError: (e) => fail('$e'),
        now: () => DateTime(2026).add(time.elapsed),
      )..beginSession('a');
      badge.setCount(1);
      time.elapse(Duration.zero);
      pending[0].complete();
      time.flushMicrotasks();
      badge.setCount(2);
      time.elapse(const Duration(seconds: 1));
      badge.setCount(1);
      time.elapse(const Duration(seconds: 3));
      expect(remote, [1, 2]);
      pending[1].complete();
      time.elapse(Duration.zero);
      expect(remote, [1, 2, 1]);
      pending[2].complete();
      time.flushMicrotasks();
      badge.close();
    });
  });

  test('failures wait for observation and cooldown, retry only latest', () {
    fakeAsync((time) {
      final remote = <int>[];
      var errors = 0;
      final badge = AppBadgeCoordinator(
        updateRemote: (n) async {
          remote.add(n);
          if (remote.length == 1) throw StateError('offline');
        },
        isSystemSupported: () async => false,
        updateSystem: (_) async {},
        onError: (_) => errors++,
        now: () => DateTime(2026).add(time.elapsed),
      )..beginSession('a');
      badge.setCount(1);
      time.elapse(Duration.zero);
      badge.setCount(2);
      badge.onForeground();
      time.elapse(const Duration(seconds: 4));
      expect(remote, [1]);
      badge.setCount(3);
      time.elapse(const Duration(seconds: 1));
      expect(remote, [1, 3]);
      expect(errors, 1);
      time.elapse(const Duration(seconds: 30));
      expect(remote.length, 2);
      badge.close();
    });
  });

  test(
      'logout cancels trailing value and old completion cannot confirm new session',
      () {
    fakeAsync((time) {
      final remote = <int>[];
      final first = Completer<void>();
      final badge = AppBadgeCoordinator(
        updateRemote: (n) {
          remote.add(n);
          return remote.length == 1 ? first.future : Future.value();
        },
        isSystemSupported: () async => false,
        updateSystem: (_) async {},
        onError: (e) => fail('$e'),
        now: () => DateTime(2026).add(time.elapsed),
      )..beginSession('a');
      badge.setCount(1);
      time.elapse(Duration.zero);
      badge.setCount(99);
      badge.beginSession('b');
      badge.setCount(2);
      time.elapse(const Duration(seconds: 2));
      expect(remote, [1]);
      first.complete();
      time.elapse(Duration.zero);
      expect(remote, [1, 2]);
      badge.setCount(3);
      badge.resetSession();
      time.elapse(const Duration(seconds: 2));
      expect(remote, [1, 2]);
      badge.close();
    });
  });
}
