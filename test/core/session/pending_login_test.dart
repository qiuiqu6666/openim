import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/session/pending_login.dart';

void main() {
  test('success between timeout and retry is consumed without a second login',
      () async {
    final owner = PendingLogin<String>();
    final native = Completer<String>();
    var calls = 0;
    Future<String> login() {
      calls++;
      return native.future;
    }

    await expectLater(
        owner.run('account', login, timeout: const Duration(milliseconds: 5)),
        throwsA(isA<TimeoutException>()));
    native.complete('restored');
    await Future<void>.delayed(Duration.zero);
    expect(
        await owner.run('account', login, timeout: const Duration(seconds: 1)),
        'restored');
    expect(calls, 1);
  });
  test('timeouts retain one native operation; recovery joins its late result',
      () async {
    final owner = PendingLogin<String>();
    final native = Completer<String>();
    var calls = 0;
    Future<String> login() {
      calls++;
      return native.future;
    }

    for (var i = 0; i < 3; i++) {
      await expectLater(
          owner.run('account', login, timeout: const Duration(milliseconds: 5)),
          throwsA(isA<TimeoutException>()));
    }
    expect(calls, 1);
    final restored =
        owner.run('account', login, timeout: const Duration(seconds: 1));
    native.complete('restored');
    expect(await restored, 'restored');
    expect(calls, 1);
  });
  test('another account cannot bypass an unresolved native login', () async {
    final owner = PendingLogin<String>();
    final native = Completer<String>();
    await expectLater(
        owner.run('old', () => native.future,
            timeout: const Duration(milliseconds: 5)),
        throwsA(isA<TimeoutException>()));
    var calls = 0;
    await expectLater(
        owner.run('new', () async {
          calls++;
          return 'new';
        }, timeout: const Duration(seconds: 1)),
        throwsStateError);
    expect(calls, 0);
    native.completeError(StateError('old cancelled'));
    await Future<void>.delayed(Duration.zero);
    expect(
        await owner.run('new', () async => 'new',
            timeout: const Duration(seconds: 1)),
        'new');
  });
  test('a late native error is consumed and releases the slot for retry',
      () async {
    final owner = PendingLogin<String>();
    final native = Completer<String>();
    await expectLater(
        owner.run('account', () => native.future,
            timeout: const Duration(milliseconds: 5)),
        throwsA(isA<TimeoutException>()));
    native.completeError(StateError('network'));
    await Future<void>.delayed(Duration.zero);
    expect(
        await owner.run('account', () async => 'recovered',
            timeout: const Duration(seconds: 1)),
        'recovered');
  });
}
