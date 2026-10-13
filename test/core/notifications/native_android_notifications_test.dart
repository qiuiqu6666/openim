import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/notifications/native_android_notifications.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('openim_native_im');
  final calls = <MethodCall>[];
  setUp(() async {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    Get.locale = const Locale('zh', 'CN');
    Get.addTranslations(TranslationService().keys);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return call.method == 'initialize' ? true : null;
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    Get.reset();
  });
  test('release gate leaves existing notification owner untouched', () async {
    final bridge = NativeAndroidNotifications(isAndroid: true, enabled: false);
    await bridge.initialize((_) => fail('unexpected action'));
    expect(bridge.ownsNotifications, isFalse);
    expect(calls, isEmpty);
  });
  test('native ownership requires successful handshake before action readiness',
      () async {
    final bridge = NativeAndroidNotifications(isAndroid: true, enabled: true);
    await bridge.initialize((_) {});
    expect(bridge.ownsNotifications, isTrue);
    expect(calls.map((e) => e.method), ['initialize', 'readyForActions']);
  });
  test(
      'policy synchronization carries account and settings but no message or token',
      () async {
    final bridge = NativeAndroidNotifications(isAndroid: true, enabled: true);
    await bridge.initialize((_) {});
    await bridge.configure(
        accountID: 'owner',
        sessionKey: 'opaque-fingerprint',
        activeConversationID: 'c1',
        suppressSound: true);
    final data = calls.last.arguments as Map;
    expect(data['accountID'], 'owner');
    expect(data['activeConversationID'], 'c1');
    expect(data['suppressSound'], isTrue);
    expect(data.containsKey('token'), isFalse);
    expect(data.containsKey('message'), isFalse);
    final settings = data['preferences'] as Map;
    expect(settings['closedPreview'], 'detail');
    expect(settings['quickReply'], isTrue);
    expect((settings['labels'] as Map)['picture'], '图片');
  });
  test('logout invalidation is scoped to the original session', () async {
    final bridge = NativeAndroidNotifications(isAndroid: true, enabled: true);
    await bridge.initialize((_) {});
    await bridge.clear('old-session');
    expect(calls.last.method, 'clear');
    expect(calls.last.arguments, {'sessionKey': 'old-session'});
  });
}
