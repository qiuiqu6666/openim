import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/core/privacy/typing_visibility_preferences.dart';
import 'package:openim/core/privacy/typing_visibility_sync.dart';
import 'package:openim/pages/chat/composer/typing/chat_typing_sender.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late String ex;
  var failSave = false;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'alice',
      'imToken': 'token',
      'chatToken': 'chat',
    }));
    OpenIM.iMManager.userID = 'alice';
    ex = '{"signature":"keep me","other":{"enabled":1}}';
    failSave = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getSelfUserInfo') {
        return jsonEncode({'userID': 'alice', 'ex': ex});
      }
      if (call.method == 'setSelfInfo') {
        if (failSave) throw PlatformException(code: 'offline');
        ex = call.arguments['ex'] as String;
        return null;
      }
      throw StateError('Unexpected SDK call');
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test(
      'server save preserves extension fields; fresh device restores remote value',
      () async {
    await TypingVisibilitySync.save('alice', false);
    expect(jsonDecode(ex), {
      'signature': 'keep me',
      'other': {'enabled': 1},
      'showTypingStatus': false
    });
    // Simulate an empty local preference cache on another signed-in device.
    await TypingVisibilityPreferences.write('alice', true);
    await TypingVisibilitySync.refresh('alice');
    expect(TypingVisibilityPreferences.read('alice'), isFalse);
  });
  test('remote self update refreshes settings and ends active typing',
      () async {
    final store = SettingsDraftStore();
    addTearDown(store.dispose);
    var updates = 0;
    store.addListener(() => updates++);
    final sent = <bool>[];
    final sender = ChatTypingSender(
        owner: 'alice',
        isCurrent: () => true,
        send: (value) async {
          sent.add(value);
        });
    addTearDown(sender.dispose);
    sender.report(true);
    await sender.settled;
    await TypingVisibilitySync.accept(
        UserInfo(userID: 'alice', ex: '{"showTypingStatus":false}'));
    await sender.settled;
    sender.report(true);
    await sender.settled;
    expect(sent, [true, false]);
    expect(store.showTypingStatus, isFalse);
    expect(updates, 1);
  });
  test('server failure cannot change the confirmed local permission', () async {
    failSave = true;
    await expectLater(TypingVisibilitySync.save('alice', false),
        throwsA(isA<PlatformException>()));
    expect(TypingVisibilityPreferences.read('alice'), isTrue);
  });
  test(
      'missing remote preference defaults on; malformed extension is not overwritten',
      () async {
    await TypingVisibilitySync.refresh('alice');
    expect(TypingVisibilityPreferences.read('alice'), isTrue);
    ex = 'unknown extension format';
    await expectLater(
        TypingVisibilitySync.save('alice', false), throwsFormatException);
    expect(ex, 'unknown extension format');
  });
  test('stale refresh cannot override a newer remote notification', () async {
    final gate = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => gate.future);
    final pending = TypingVisibilitySync.refresh('alice');
    await TypingVisibilitySync.accept(
        UserInfo(userID: 'alice', ex: '{"showTypingStatus":false}'));
    gate.complete(jsonEncode({'userID': 'alice', 'ex': '{}'}));
    await pending;
    expect(TypingVisibilityPreferences.read('alice'), isFalse);
  });
  test('account switch drops a pending refresh and another users notification',
      () async {
    final gate = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => gate.future);
    final pending = TypingVisibilitySync.refresh('alice');
    OpenIM.iMManager.userID = 'bob';
    gate.complete(
        jsonEncode({'userID': 'alice', 'ex': '{"showTypingStatus":false}'}));
    await pending;
    await TypingVisibilitySync.accept(
        UserInfo(userID: 'bob', ex: '{"showTypingStatus":false}'));
    expect(TypingVisibilityPreferences.read('alice'), isTrue);
    expect(TypingVisibilityPreferences.read('bob'), isTrue);
  });
}
