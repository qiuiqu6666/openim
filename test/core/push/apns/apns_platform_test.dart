import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/push/apns/apns_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('apns-test');
  const codec = StandardMethodCodec();
  final token = {
    'apnsToken': 'AaBb12',
    'bundleId': 'vip.99chat.ios',
    'apsEnvironment': 'production',
  };
  Future<void> native(String method, Object? arguments) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            channel.name,
            codec.encodeMethodCall(MethodCall(method, arguments)),
            (ByteData? _) {});
    await Future<void>.delayed(Duration.zero);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('register and initial tap use only the direct Apple channel', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'registerForRemoteNotifications' => {
            'authorizationStatus': 'authorized'
          },
        'getCachedTokens' => token,
        'consumePendingNotificationTap' => {'accountID': 'im_current'},
        _ => null,
      };
    });
    final platform = MethodChannelAPNsPlatform(channel: channel);
    final taps = <Map<String, dynamic>>[];
    final tokens = <APNsDeviceToken>[];
    platform.notificationTaps.listen(taps.add);
    platform.tokens.listen(tokens.add);
    await Future.wait([platform.initialize(), platform.initialize()]);
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((call) => call.method == 'install'), hasLength(1));
    expect(taps.single['accountID'], 'im_current');
    expect(await platform.register(), isTrue);
    expect((await platform.currentToken())?.token, 'aabb12');
    await native('onApnsToken', token);
    expect(tokens.single.environment, 'production');
    await platform.unregister();
    expect(calls.last.method, 'unregisterForRemoteNotifications');
    await platform.dispose();
  });
  test('denied authorization is not reported as push enabled', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'registerForRemoteNotifications'
                ? {'authorizationStatus': 'denied'}
                : null);
    final platform = MethodChannelAPNsPlatform(channel: channel);
    expect(await platform.register(), isFalse);
    await platform.dispose();
  });
  test('tap activation after logout drains once without permission or binding',
      () async {
    final calls = <String>[];
    Map<String, dynamic>? pending;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'consumePendingNotificationTap') {
        final current = pending;
        pending = null;
        return current;
      }
      return null;
    });
    final platform = MethodChannelAPNsPlatform(channel: channel);
    addTearDown(platform.dispose);
    final taps = <Map<String, dynamic>>[];
    platform.notificationTaps.listen(taps.add);
    await platform.initialize();
    await platform.unregister();
    pending = {'accountID': 'current', 'marker': 'already-delivered'};

    await platform.activateNotificationTaps();
    await platform.activateNotificationTaps();
    await Future<void>.delayed(Duration.zero);

    expect(calls.where((method) => method == 'install'), hasLength(1));
    expect(calls, isNot(contains('registerForRemoteNotifications')));
    expect(calls.where((method) => method == 'activateNotificationTaps'),
        hasLength(2));
    expect(taps, [
      {'accountID': 'current', 'marker': 'already-delivered'}
    ]);
  });
  test('initialization failure can retry without duplicate native listeners',
      () async {
    var installs = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'install' && ++installs == 1) {
        throw PlatformException(code: 'temporary');
      }
      return null;
    });
    final platform = MethodChannelAPNsPlatform(channel: channel);
    await expectLater(platform.initialize(), throwsA(isA<PlatformException>()));
    await platform.initialize();
    expect(installs, 2);
    await platform.dispose();
  });
  test('invalid device tokens or unknown signing environment are not uploaded',
      () {
    for (final value in [
      {...token, 'apnsToken': ''},
      {...token, 'apnsToken': 'not-an-apns-token'},
      {...token, 'bundleId': ''},
      {...token, 'apsEnvironment': ''},
      {...token, 'apsEnvironment': 'sandbox'},
    ]) {
      expect(APNsDeviceToken.decode(value), isNull);
    }
    // Apple does not promise a fixed device token length.
    expect(APNsDeviceToken.decode(token), isNotNull);
  });
}
