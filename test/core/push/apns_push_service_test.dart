import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/push/apns/apns_push_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_apns');
  const session =
      (userID: 'user1', credential: 'im1', endpoint: 'https://im.test');
  const registration = {
    'token': 'abcdef0123456789',
    'environment': 'production',
  };

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('native token is registered with APNs provider, renewed and deleted',
      () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async => call.method == 'register' ? registration : null);
    final requests = <(String, String, Map<String, dynamic>)>[];
    final service = ApnsPushService(
      channel: channel,
      currentSession: () => session,
      deviceID: () async => 'device-1',
      request: (endpoint, credential, action, data) async {
        expect(endpoint, session.endpoint);
        requests.add((credential, action, data));
      },
    );
    await service.login('user1');
    await flush();
    expect(requests.single.$2, 'set_push_token');
    expect(requests.single.$3, {
      'platformID': 1,
      'deviceID': 'device-1',
      'provider': 'apns',
      ...registration,
    });
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await flush();
    expect(requests.length, 2);
    await service.logout();
    expect(requests.last.$2, 'delete_push_token');
    expect(requests.last.$1, 'im1');
    expect(requests.last.$3['deviceID'], 'device-1');
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await flush();
    expect(requests.length, 3);
  });

  test('logout deletion waits for an in-flight upload before the next login',
      () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async => call.method == 'register' ? registration : null);
    var current = session;
    final upload = Completer<void>();
    final requests = <String>[];
    final service = ApnsPushService(
      channel: channel,
      currentSession: () => current,
      deviceID: () async => 'device-1',
      request: (endpoint, credential, action, data) async {
        requests.add('$credential:$action');
        if (credential == 'im1' && action == 'set_push_token') {
          await upload.future;
        }
      },
    );
    await service.login('user1');
    await flush();
    final logout = service.logout();
    current = (userID: 'user2', credential: 'im2', endpoint: session.endpoint);
    await service.login('user2');
    await flush();
    expect(requests, ['im1:set_push_token']);
    upload.complete();
    await logout;
    await flush();
    expect(requests,
        ['im1:set_push_token', 'im1:delete_push_token', 'im2:set_push_token']);
    await service.logout();
  });

  test('a delayed native reply cannot register a signed-out account', () async {
    final native = Completer<Map<String, String>?>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async => call.method == 'register' ? await native.future : null);
    var active = true;
    final requests = <String>[];
    final service = ApnsPushService(
      channel: channel,
      currentSession: () => active ? session : null,
      deviceID: () async => 'device-1',
      request: (endpoint, credential, action, data) async =>
          requests.add(action),
    );
    final login = service.login('user1');
    await flush();
    active = false;
    await service.logout();
    native.complete(registration);
    await login;
    await flush();
    expect(requests, ['delete_push_token']);
  });

  test('permission denial does not upload an empty token or block login',
      () async {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    final requests = <String>[];
    final service = ApnsPushService(
      channel: channel,
      currentSession: () => session,
      deviceID: () async => 'device-1',
      request: (endpoint, credential, action, data) async =>
          requests.add(action),
    );
    await service.login('user1');
    await flush();
    expect(requests, isEmpty);
    await service.logout();
  });
}
