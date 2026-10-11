import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group_setup/loading/group_setup_membership.dart';

void main() {
  for (final stillAbsent in [false, true]) {
    test('negative cache result is confirmed before publishing $stillAbsent',
        () {
      fakeAsync((time) {
        final state = GroupSetupMembership();
        final results = <bool>[];
        var calls = 0;
        state.refresh(
          query: () async => ++calls == 1 ? false : !stillAbsent,
          isCurrent: () => true,
          onResult: results.add,
        );
        time.flushMicrotasks();
        expect(results, isEmpty);
        expect(state.resolved.value, isFalse);
        expect(state.failed.value, isFalse);
        time.elapse(const Duration(milliseconds: 500));
        expect(results, [!stillAbsent]);
        expect(state.resolved.value, isTrue);
        expect(calls, 2);
        state.dispose();
      });
    });
  }

  test('sync defers a pending negative result and allows a fresh read', () {
    fakeAsync((time) {
      final state = GroupSetupMembership();
      final old = Completer<bool>();
      final results = <bool>[];
      state.refresh(
        query: () => old.future,
        isCurrent: () => true,
        onResult: results.add,
      );
      state.defer();
      state.refresh(
        query: () async => true,
        isCurrent: () => true,
        onResult: results.add,
      );
      old.complete(false);
      time.elapse(const Duration(seconds: 1));
      expect(results, [true]);
      state.dispose();
    });
  });

  test('transient initial failure retries without showing a retry button', () {
    fakeAsync((time) {
      final state = GroupSetupMembership();
      var calls = 0;
      bool? result;
      state.refresh(
        query: () async {
          if (++calls == 1) throw StateError('SDK not ready');
          return true;
        },
        isCurrent: () => true,
        onResult: (value) => result = value,
      );
      time.flushMicrotasks();
      expect(state.resolved.value, isFalse);
      expect(state.failed.value, isFalse);
      time.elapse(const Duration(milliseconds: 500));
      expect(result, isTrue);
      expect(state.resolved.value, isTrue);
      expect(calls, 2);
      state.dispose();
    });
  });

  test('stalled reads time out; retry can recover and late reads are ignored',
      () {
    fakeAsync((time) {
      final state = GroupSetupMembership();
      final replies = <Completer<bool>>[];
      final results = <bool>[];
      Future<void> refresh() => state.refresh(
            query: () {
              final reply = Completer<bool>();
              replies.add(reply);
              return reply.future;
            },
            isCurrent: () => true,
            onResult: results.add,
          );
      final first = refresh();
      expect(identical(first, refresh()), isTrue);
      time.elapse(const Duration(seconds: 17));
      expect(state.failed.value, isTrue);
      expect(state.resolved.value, isFalse);
      expect(replies, hasLength(2));
      refresh();
      replies.last.complete(true);
      time.flushMicrotasks();
      replies.first.complete(false);
      replies[1].complete(false);
      time.flushMicrotasks();
      expect(results, [true]);
      expect(state.failed.value, isFalse);
      state.dispose();
    });
  });

  for (final reason in ['membership event', 'close', 'session changed']) {
    test('$reason prevents a pending retry from updating the page', () {
      fakeAsync((time) {
        final state = GroupSetupMembership();
        var current = true;
        var calls = 0;
        final results = <bool>[];
        state.refresh(
          query: () async {
            calls++;
            throw StateError('unavailable');
          },
          isCurrent: () => current,
          onResult: results.add,
        );
        time.flushMicrotasks();
        switch (reason) {
          case 'membership event':
            state.accept();
          case 'close':
            state.dispose();
          case 'session changed':
            current = false;
        }
        time.elapse(const Duration(seconds: 20));
        expect(calls, 1);
        expect(results, isEmpty);
        expect(state.failed.value, isFalse);
        state.dispose();
      });
    });
  }
}
