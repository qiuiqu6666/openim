import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/calling/ios/ios_callkit_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_ios_voip_callkit');
  late MethodChannelIOSCallKitPlatform platform;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    platform = MethodChannelIOSCallKitPlatform(channel: channel);
  });
  tearDown(() async {
    await platform.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('coalesces installation and delivers buffered actions once', () async {
    final methods = <String>[];
    final installed = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'install') {
        await installed.future;
      }
      if (call.method == 'drainPendingEvents') {
        return [
          {'type': 'answer', 'roomID': 'room_1234'}
        ];
      }
      return null;
    });
    final received = <Map<String, dynamic>>[];
    final subscription = platform.events.listen(received.add);
    final first = platform.initialize(), second = platform.initialize();
    installed.complete();
    await Future.wait([first, second]);
    await Future<void>.delayed(Duration.zero);
    expect(methods, ['install', 'setEventHandlerReady', 'drainPendingEvents']);
    expect(received.single['type'], 'answer');
    await subscription.cancel();
  });

  test('an installation failure remains retryable', () async {
    var installs = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'install' && installs++ == 0) {
        throw PlatformException(code: 'not-ready');
      }
      if (call.method == 'drainPendingEvents') return <Object?>[];
      return null;
    });
    await expectLater(platform.initialize(), throwsA(isA<PlatformException>()));
    await platform.initialize();
    expect(installs, 2);
  });

  test('decodes independent VoIP metadata and rejects ordinary APNs field', () {
    final raw = {
      'voipToken': 'ab' * 32,
      'bundleId': 'vip.99chat.ios',
      'apsEnvironment': 'production'
    };
    expect(MethodChannelIOSCallKitPlatform.decodeToken(raw)?.token, 'ab' * 32);
    expect(
        MethodChannelIOSCallKitPlatform.decodeToken({
          'apnsToken': 'ab' * 32,
          'bundleId': 'vip.99chat.ios',
          'apsEnvironment': 'production'
        }),
        null);
  });
}
