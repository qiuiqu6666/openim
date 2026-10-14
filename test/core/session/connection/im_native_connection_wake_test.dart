import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/session/connection/im_connection_recovery.dart';
import 'package:openim/core/session/connection/im_native_connection_wake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('im-wake-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('both wake methods supply the native manager dispatch envelope',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'setAppBackgroundStatus') {
        throw PlatformException(code: 'offline');
      }
      return null;
    });
    await expectLater(
        wakeIMConnection(
            channel: channel,
            isCurrent: () => true,
            isDisconnected: () => true),
        throwsA(isA<PlatformException>()));
    expect(calls.map((call) => call.method),
        ['networkStatusChanged', 'setAppBackgroundStatus']);
    for (final call in calls) {
      // Android reflects this manager field; iOS switches on the same key.
      // Missing it leaves the native result unresolved on both platforms.
      expect(call.arguments['ManagerName'], 'imManager');
      expect(
          call.arguments['operationID'],
          isA<String>().having(
              (value) => value.isNotEmpty, 'nonempty operation ID', isTrue));
    }
    expect(calls.last.arguments['isBackground'], isFalse);
  });

  testWidgets('a pre-background reply cannot replace the new foreground report',
      (tester) async {
    final pending = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (calls.length == 1) await pending.future;
      return null;
    });
    final nativeWake = IMNativeConnectionWake(
        channel: channel,
        isCurrentSession: () => true,
        isDisconnected: () => false);
    var reconciled = 0;
    final recovery = IMConnectionRecovery(
      isCurrent: () => true,
      isDisconnected: () => false,
      wake: nativeWake.wake,
      networkChanges: const Stream.empty(),
      onError: (error) => fail('$error'),
      onWakeSucceeded: () => reconciled++,
    )..start();
    recovery.didChangeAppLifecycleState(AppLifecycleState.paused);
    recovery.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    recovery.didChangeAppLifecycleState(AppLifecycleState.paused);
    recovery.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, ['setAppBackgroundStatus'],
        reason: 'Native calls remain serialized.');
    pending.complete();
    await tester.pump();
    expect(calls, ['setAppBackgroundStatus', 'setAppBackgroundStatus']);
    expect(reconciled, 1,
        reason: 'Only the current foreground ACK triggers catch-up.');
    recovery.close();
    nativeWake.close();
    await tester.pump();
  });

  testWidgets('slow native wake keeps its slot and does not close the socket',
      (tester) async {
    final stalled = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'setAppBackgroundStatus') {
        expectSync(call.arguments['isBackground'], isFalse);
        await stalled.future;
      }
      return null;
    });
    var current = true;
    final errors = <Object>[];
    final nativeWake = IMNativeConnectionWake(
        channel: channel,
        isCurrentSession: () => current,
        isDisconnected: () => false);
    final recovery = IMConnectionRecovery(
      isCurrent: () => current,
      isDisconnected: () => true,
      wake: nativeWake.wake,
      onError: errors.add,
      networkChanges: const Stream.empty(),
    )..start();
    recovery.didChangeAppLifecycleState(AppLifecycleState.paused);
    recovery.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, ['setAppBackgroundStatus']);
    await tester.pump(const Duration(seconds: 12));
    expect(calls, ['setAppBackgroundStatus']);
    expect(errors, [isA<TimeoutException>()]);
    await tester.pump(const Duration(seconds: 3));
    expect(calls, ['setAppBackgroundStatus']);
    // Closing must release timers without waiting for a native response.
    current = false;
    recovery.close();
    nativeWake.close();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    stalled.completeError(PlatformException(code: 'late'));
    await tester.pump();
    expect(calls, hasLength(1));
    expect(errors, hasLength(1));
  });

  test(
      'a healthy foreground acknowledgement retries sync without disconnecting',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    await wakeIMConnection(channel: channel, isCurrent: () => true);
    expect(calls, ['setAppBackgroundStatus']);
  });

  test('native failure on a healthy transport does not reset its socket',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'setAppBackgroundStatus') {
        throw PlatformException(code: 'offline');
      }
      return null;
    });
    await expectLater(wakeIMConnection(channel: channel, isCurrent: () => true),
        throwsA(isA<PlatformException>()));
    expect(calls, ['setAppBackgroundStatus']);
  });

  test('an expired session cannot signal native recovery', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('An obsolete session must not wake a new account');
    });
    await wakeIMConnection(channel: channel, isCurrent: () => false);
  });
}
