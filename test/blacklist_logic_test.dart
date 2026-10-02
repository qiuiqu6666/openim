import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/blacklist/blacklist_logic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  for (final legacy in [false, true]) {
    test('remove passes blocked ID and updates list, legacy=$legacy', () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        received = call;
        return null;
      });
      final logic = BlacklistLogic();
      final entry = legacy
          ? BlacklistInfo(userID: 'blocked')
          : BlacklistInfo(blockUserID: 'blocked', userID: 'owner');
      logic.blacklist.add(entry);
      expect(await logic.remove(entry), true);
      expect(received!.method, 'removeBlacklist');
      expect(received!.arguments['userID'], 'blocked');
      expect(logic.blacklist, isEmpty);
      expect(logic.removing, isEmpty);
    });
  }
  test('SDK failure keeps contact and clears busy state', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: '500', message: 'failed');
    });
    final logic = BlacklistLogic();
    final entry = BlacklistInfo(blockUserID: 'blocked');
    logic.blacklist.add(entry);
    await expectLater(logic.remove(entry), throwsA(isA<PlatformException>()));
    expect(logic.blacklist, [entry]);
    expect(logic.removing, isEmpty);
  });
  test('missing ID reports error instead of silently returning', () async {
    await expectLater(
        BlacklistLogic().remove(BlacklistInfo()), throwsA(isA<StateError>()));
  });
}
