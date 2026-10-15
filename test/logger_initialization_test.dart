import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/utils/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a burst of logs probes device info once and tolerates plugin failure',
      () async {
    const channel = MethodChannel('dev.fluttercommunity.plus/device_info');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var queries = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      queries++;
      throw PlatformException(code: 'unavailable');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    for (var index = 0; index < 100; index++) {
      Logger.print('visible $index', onlyConsole: true);
    }
    await Future<void>.delayed(Duration.zero);
    expect(queries, 1);
    Logger.print('after platform failure', onlyConsole: true);
    await Future<void>.delayed(Duration.zero);
    expect(queries, 1);
    expect(Logger(), same(Logger()));
  });

  for (final failure in [
    PlatformException(code: '10006', message: 'sdk not init'),
    MissingPluginException('engine detached'),
  ]) {
    test('native logging survives teardown and recovery: $failure', () async {
      const channel = MethodChannel('flutter_openim_sdk');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final pending = Completer<void>();
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'logs');
        calls++;
        if (calls == 1) await pending.future;
        return null;
      });
      addTearDown(() {
        Logger().sdkIsInited = false;
        messenger.setMockMethodCallHandler(channel, null);
      });
      Logger().sdkIsInited = true;
      Logger.print('record before native teardown');
      Logger().sdkIsInited = false;
      pending.completeError(failure);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1, reason: 'failure must not recurse into native logging');
      Logger.print('record while native SDK is unavailable');
      expect(calls, 1);
      Logger().sdkIsInited = true;
      Logger.print('record after native recovery');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2,
          reason: 'a failed record must not disable later logging');
    });
  }
}
