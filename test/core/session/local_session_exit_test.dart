import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/session/local_session_exit.dart';

void main() {
  test('local credentials and navigation do not wait for native cleanup',
      () async {
    final cleanup = Completer<void>();
    final calls = <String>[];
    await exitLocalSession(
      logoutSdk: () {
        calls.add('invalidate SDK session');
        return cleanup.future;
      },
      clearLocal: () async => calls.add('clear credentials'),
      navigate: () => calls.add('login screen'),
      onCleanupError: (_, __) => fail('Unexpected cleanup error'),
    );
    expect(
        calls, ['invalidate SDK session', 'clear credentials', 'login screen']);
    expect(cleanup.isCompleted, isFalse);
    cleanup.complete();
    await Future<void>.delayed(Duration.zero);
  });

  test('SDK cleanup failure is observed without preventing local sign-out',
      () async {
    final cleanup = Completer<void>();
    var cleared = false;
    var navigated = false;
    final errors = <Object>[];
    await exitLocalSession(
      logoutSdk: () => cleanup.future,
      clearLocal: () async => cleared = true,
      navigate: () => navigated = true,
      onCleanupError: (error, _) => errors.add(error),
    );
    cleanup.completeError(StateError('native failed'));
    await Future<void>.delayed(Duration.zero);
    expect(cleared && navigated, isTrue);
    expect(errors.single, isA<StateError>());
  });

  test('navigation still runs when local cleanup fails', () async {
    var navigated = false;
    await expectLater(
        exitLocalSession(
          logoutSdk: () async {},
          clearLocal: () async => throw StateError('storage failed'),
          navigate: () => navigated = true,
          onCleanupError: (_, __) {},
        ),
        throwsStateError);
    expect(navigated, isTrue);
  });
}
