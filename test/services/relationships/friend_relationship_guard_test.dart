import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  var entries = '[]';
  Completer<void>? gate;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    OpenIM.iMManager.userID = 'me';
    entries = '[]';
    gate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getBlacklist');
      if (gate != null) await gate!.future;
      return entries;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('blocks only the requested peer and allows removal', () async {
    entries = '[{"userID":"me","blockUserID":"peer"}]';
    await expectLater(FriendRelationshipGuard.requireNotBlocked('peer'),
        throwsA(isA<PlatformException>().having(
            (error) => error.code, 'code', 'FriendBlacklisted')));
    await FriendRelationshipGuard.requireNotBlocked('other');
    entries = '[]';
    await FriendRelationshipGuard.requireNotBlocked('peer');
  });
  test('account replacement cannot authorize an old request', () async {
    gate = Completer<void>();
    final pending = FriendRelationshipGuard.requireNotBlocked('peer');
    OpenIM.iMManager.userID = 'other';
    gate!.complete();
    await expectLater(pending, throwsA(isA<PlatformException>()));
  });
}
