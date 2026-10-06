import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_live/src/models/call_types.dart';
import 'package:openim_live/src/session/single_call_session.dart';

void main() {
  SingleCallSession session(
          {CallState initial = CallState.beCalled,
          Future<void> Function(CallAttempt, bool)? connect,
          Future<void> Function()? release,
          Future<void> Function(CallTermination)? finish,
          void Function()? close,
          DateTime Function()? now}) =>
      SingleCallSession(
          initialState: initial,
          connect: connect ?? (_, __) async {},
          release: release ?? () async {},
          onTerminated: finish ?? (_) async {},
          onClosed: close ?? () {},
          now: now);

  test('duplicate accept admits one connection and needs actual peer presence',
      () async {
    final gate = Completer<void>();
    var connects = 0;
    final call = session(connect: (_, outgoing) {
      expect(outgoing, false);
      connects++;
      return gate.future;
    });
    final first = call.accept();
    await call.accept();
    expect(connects, 1);
    expect(call.state, CallState.connecting);
    gate.complete();
    await first;
    expect(call.connected, false);
    call.peerConnected();
    expect(call.state, CallState.calling);
    await call.end(CallState.hangup);
    call.dispose();
  });

  test('early peer presence waits for media publication', () async {
    final gate = Completer<void>();
    final call = session(connect: (_, __) => gate.future);
    final pending = call.accept();
    call.peerConnected();
    expect(call.connected, false);
    gate.complete();
    await pending;
    expect(call.connected, true);
    await call.end(CallState.hangup);
    call.dispose();
  });

  test('failed credential or media operation never emits calling', () async {
    final outcomes = <CallTermination>[];
    final states = <CallState>[];
    var closes = 0, releases = 0;
    final call = session(
        connect: (_, __) async {
          throw StateError('failed');
        },
        release: () async {
          releases++;
        },
        finish: (result) async {
          outcomes.add(result);
        },
        close: () => closes++);
    call.addListener(() => states.add(call.state));
    await call.accept();
    call.peerConnected();
    expect(states, isNot(contains(CallState.calling)));
    expect(outcomes.single.state, CallState.networkError);
    expect(outcomes.single.error, isA<StateError>());
    expect([closes, releases], [1, 1]);
    call.dispose();
  });

  test(
      'cancel invalidates credentials before a late connection can allocate media',
      () async {
    final credentials = Completer<void>();
    var allocations = 0, endings = 0;
    final call = session(
        initial: CallState.call,
        connect: (attempt, _) async {
          await credentials.future;
          if (!attempt.isCurrent) return;
          allocations++;
        },
        finish: (_) async {
          endings++;
        });
    final pending = call.dial();
    await call.end(CallState.cancel);
    credentials.complete();
    await pending;
    expect(allocations, 0);
    expect(endings, 1);
    call.dispose();
  });

  test(
      'duplicate endings share cleanup and hold completion until media releases',
      () async {
    final cleanup = Completer<void>();
    var releases = 0, endings = 0, closes = 0;
    final call = session(
        release: () {
          releases++;
          return cleanup.future;
        },
        finish: (_) async {
          endings++;
        },
        close: () => closes++);
    final first = call.end(CallState.reject);
    final second = call.end(CallState.beHangup);
    expect(identical(first, second), true);
    expect(call.active, false);
    call.peerConnected();
    expect(call.connected, false);
    expect(closes, 0);
    cleanup.complete();
    await first;
    expect([releases, endings, closes], [1, 1, 1]);
    call.dispose();
  });

  test(
      'unanswered deadline fires once at thirty seconds and cancels later taps',
      () {
    fakeAsync((clock) {
      final outcomes = <CallTermination>[];
      var attempts = 0;
      final call = session(connect: (_, __) async {
        attempts++;
      }, finish: (result) async {
        outcomes.add(result);
      });
      call.armDeadline();
      call.armDeadline();
      clock.elapse(const Duration(seconds: 29));
      expect(call.active, true);
      clock.elapse(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(outcomes.single.state, CallState.timeout);
      unawaited(call.accept());
      clock.flushMicrotasks();
      expect(attempts, 0);
      clock.elapse(const Duration(minutes: 1));
      expect(outcomes.length, 1);
      call.dispose();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('connected call cancels ringing deadline and uses elapsed local time',
      () {
    fakeAsync((clock) {
      var now = DateTime(2026, 10, 5);
      final call = session(now: () => now);
      call.armDeadline();
      unawaited(call.accept());
      clock.flushMicrotasks();
      call.peerConnected();
      now = now.add(const Duration(minutes: 4, seconds: 5));
      expect(call.duration, 245);
      clock.elapse(const Duration(seconds: 31));
      expect(call.active, true);
      unawaited(call.end(CallState.hangup));
      clock.flushMicrotasks();
      call.dispose();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('reconnection succeeds without resetting duration', () {
    fakeAsync((clock) {
      var now = DateTime(2026);
      final call = session(now: () => now);
      unawaited(call.accept());
      clock.flushMicrotasks();
      call.peerConnected();
      now = now.add(const Duration(seconds: 8));
      call.reconnecting();
      expect(call.state, CallState.connecting);
      call.peerConnected();
      clock.elapse(const Duration(seconds: 21));
      expect(call.active, true);
      expect(call.duration, 8);
      unawaited(call.end(CallState.hangup));
      clock.flushMicrotasks();
      call.dispose();
    });
  });

  test('connection and reconnection deadlines fail with cleanup', () {
    fakeAsync((clock) {
      final outcomes = <CallTermination>[];
      final never = Completer<void>();
      final call = session(
          connect: (_, __) => never.future,
          finish: (result) async {
            outcomes.add(result);
          });
      unawaited(call.accept());
      clock.elapse(const Duration(seconds: 20));
      clock.flushMicrotasks();
      expect(outcomes.single.state, CallState.networkError);
      never.complete();
      clock.flushMicrotasks();
      expect(outcomes.length, 1);
      call.dispose();
    });
  });

  test('cleanup and record failures still close the call', () async {
    var closes = 0;
    final call = session(
        release: () async {
          throw StateError('cleanup');
        },
        finish: (_) async {
          throw StateError('record');
        },
        close: () => closes++);
    await call.end(CallState.beHangup, notifyPeer: false);
    expect(closes, 1);
    expect(call.cleanupError, isA<StateError>());
    call.dispose();
  });

  test('dispose during connection removes timers and invalidates late events',
      () {
    fakeAsync((clock) {
      final gate = Completer<void>();
      final call = session(connect: (_, __) => gate.future);
      call.armDeadline();
      unawaited(call.accept());
      call.dispose();
      gate.complete();
      clock.flushMicrotasks();
      call.peerConnected();
      expect(call.connected, false);
      clock.elapse(const Duration(seconds: 40));
      expect(clock.pendingTimers, isEmpty);
    });
  });
}
