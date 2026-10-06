import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/session/sdk_session_queue.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
      'logout invalidates an in-flight login and the next login waits for cleanup',
      () async {
    final queue = SdkSessionQueue();
    final firstReply = Completer<String>();
    final logoutReply = Completer<void>();
    final calls = <String>[];
    final first = queue.login(() {
      calls.add('login:first');
      return firstReply.future;
    });
    final rejected = expectLater(first, throwsA(isA<SdkSessionCancelled>()));
    await _flush();
    final logout = queue.logout(() {
      calls.add('logout:first');
      return logoutReply.future;
    });
    final second = queue.login(() async {
      calls.add('login:second');
      return 'second';
    });
    firstReply.complete('first');
    await rejected;
    await _flush();
    expect(calls, ['login:first', 'logout:first']);
    logoutReply.complete();
    await logout;
    expect(await second, 'second');
    expect(calls, ['login:first', 'logout:first', 'login:second']);
  });

  test('a superseded queued login never calls the SDK', () async {
    final queue = SdkSessionQueue();
    final cleanup = Completer<void>();
    final logout = queue.logout(() => cleanup.future);
    var nativeLogins = 0;
    final obsolete = queue.login(() async => ++nativeLogins);
    final rejected = expectLater(obsolete, throwsA(isA<SdkSessionCancelled>()));
    final current = queue.login(() async => ++nativeLogins);
    cleanup.complete();
    await logout;
    await rejected;
    expect(await current, 1);
    expect(nativeLogins, 1);
  });

  test(
      'cleanup errors are reported but do not poison subsequent queue operations',
      () async {
    final queue = SdkSessionQueue();
    final failed = queue.logout(() async => throw StateError('native failed'));
    final rejected = expectLater(failed, throwsStateError);
    final next = queue.login(() async => 'next');
    await rejected;
    expect(await next, 'next');
  });

  test('closing the owner rejects late results and future login requests',
      () async {
    final queue = SdkSessionQueue();
    final reply = Completer<int>();
    final pending = queue.login(() => reply.future);
    final rejected = expectLater(pending, throwsA(isA<SdkSessionCancelled>()));
    await _flush();
    queue.close();
    reply.complete(1);
    await rejected;
    var called = false;
    await expectLater(queue.login(() async {
      called = true;
      return 2;
    }), throwsA(isA<SdkSessionCancelled>()));
    expect(called, isFalse);
  });

  test(
      'a hanging cleanup reports a finite wait and never later runs timed-out logins',
      () async {
    final queue = SdkSessionQueue();
    final cleanup = Completer<void>();
    final logout = queue.logout(() => cleanup.future);
    var nativeLogins = 0;
    for (var i = 0; i < 2; i++) {
      await expectLater(
          queue.login(() async => ++nativeLogins,
              startTimeout: const Duration(milliseconds: 5)),
          throwsA(isA<SdkSessionBusy>()));
      expect(nativeLogins, 0);
    }
    cleanup.complete();
    await logout;
    await _flush();
    expect(nativeLogins, 0);
    expect(await queue.login(() async => ++nativeLogins), 1);
  });

  test(
      'preparation timeout retains the native cleanup and prevents late expired logins',
      () async {
    final queue = SdkSessionQueue();
    final cleanup = Completer<void>();
    final calls = <String>[];
    final login = queue.login(() async {
      calls.add('login:expired');
      return 'expired';
    }, prepare: () {
      calls.add('cleanup:retry');
      return cleanup.future;
    }, startTimeout: const Duration(milliseconds: 5));
    await expectLater(login, throwsA(isA<SdkSessionBusy>()));
    await expectLater(
        queue.login(() async {
          calls.add('login:bypassed');
          return 'bypassed';
        }, startTimeout: const Duration(milliseconds: 5)),
        throwsA(isA<SdkSessionBusy>()));
    expect(calls, ['cleanup:retry']);
    cleanup.complete();
    await _flush();
    expect(calls, ['cleanup:retry']);
    expect(await queue.login(() async => 'new'), 'new');
  });
}
