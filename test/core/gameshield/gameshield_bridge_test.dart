import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameshield_bridge/gameshield_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('openim/gameshield');
  const bridge = GameShieldBridge();
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'stop') return null;
      if (call.method == 'start') {
        expect(call.arguments['licenseToken'], 'GS2.fixture');
        expect(call.arguments['autoChangePort'], isTrue);
      }
      return {
        'ready': true,
        'sdkVersion': '60.1.10',
        'activeTunnels': 2,
        'endpoints': [
          {
            'appId': 'api',
            'groupName': 'im',
            'host': '127.0.0.1',
            'port': 20002,
            'protocol': 'tcp'
          }
        ]
      };
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  test('native channel schema supports start status and stop on both platforms',
      () async {
    final snapshot = await bridge.start('GS2.fixture');
    expect(snapshot.endpoints.single.port, 20002);
    expect(snapshot.activeTunnels, 2);
    expect((await bridge.status()).ready, isTrue);
    await bridge.stop();
    expect(calls, ['start', 'status', 'stop']);
  });
  test('absent native plugin does not report success', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await expectLater(
        bridge.start('GS2.fixture'), throwsA(isA<MissingPluginException>()));
  });
}
