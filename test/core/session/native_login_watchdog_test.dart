import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

void main() {
  testWidgets(
      'cancellation acknowledgement gates retry and targets original login',
      (tester) async {
    const channel = MethodChannel('login-cancel-watchdog-test');
    final native = Completer<String>();
    final cleanup = Completer<void>();
    var logins = 0, cancellations = 0;
    String? operation;
    Object? target;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'getLoginStatus') return logins == 0 ? 1 : 2;
      if (call.method == 'login') {
        logins++;
        operation = call.arguments['operationID'] as String;
        return native.future;
      }
      if (call.method == 'cancelLogin') {
        cancellations++;
        target = call.arguments['targetOperationID'];
        await cleanup.future;
        native.completeError(PlatformException(code: '10004'));
        return null;
      }
      return null;
    });
    final manager = IMManager(channel);
    Object? failure;
    final login = manager
        .login(userID: 'account', token: 'test-token')
        .then<void>((_) => fail('cancelled login succeeded'),
            onError: (Object e) {
      failure = e;
    });
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    expect(cancellations, 1);
    expect(target, operation);
    await tester.pump(const Duration(seconds: 30));
    expect(cancellations, 1);
    expect(logins, 1);
    expect(failure, isNull);
    cleanup.complete();
    await tester.pump();
    await login;
    expect(failure, isA<PlatformException>());
    expect(manager.isLogined, isFalse);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });
  testWidgets('lost login reply is reconciled by status without a second login',
      (tester) async {
    const channel = MethodChannel('login-watchdog-test');
    final native = Completer<String>();
    var logins = 0, polls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'getLoginStatus') {
        polls++;
        if (polls > 1) {
          native.complete('');
          return 3;
        }
        return 1;
      }
      if (call.method == 'login') {
        logins++;
        return native.future;
      }
      if (call.method == 'getSelfUserInfo') return '{"userID":"account"}';
      return null;
    });
    final manager = IMManager(channel);
    UserInfo? result;
    final login = manager
        .login(userID: 'account', token: 'test-token')
        .then((value) => result = value);
    await tester.pump();
    expect(result, isNull);
    await tester.pump(const Duration(seconds: 5));
    await login;
    expect(result?.userID, 'account');
    expect(logins, 1);
    final completedPolls = polls;
    await tester.pump(const Duration(seconds: 20));
    expect(polls, completedPolls);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });
}
