import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/mine/settings/pages/friend_permission_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'friend_auto_accept_test.dart' show host;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'alice',
      'imToken': 'token',
      'chatToken': 'chat',
    }));
    OpenIM.iMManager.userID = 'alice';
    var ex = '{}';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_openim_sdk'),
            (call) async {
      if (call.method == 'getSelfUserInfo') {
        return jsonEncode({'userID': 'alice', 'ex': ex});
      }
      if (call.method == 'setSelfInfo') {
        ex = call.arguments['ex'] as String;
        return null;
      }
      throw StateError('Unexpected SDK call');
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('flutter_openim_sdk'), null));
  for (final dark in [false, true]) {
    testWidgets('typing toggle persists and fits large text, dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final store = SettingsDraftStore();
      addTearDown(store.dispose);
      await tester.pumpWidget(
          host(FriendPermissionPage(store: store), dark: dark, scale: 2));
      final toggle = find.byType(AppSwitch).last;
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<AppSwitch>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<AppSwitch>(toggle).value, isFalse);
      expect(tester.takeException(), isNull);
      final restored = SettingsDraftStore();
      addTearDown(restored.dispose);
      expect(restored.showTypingStatus, isFalse);
      expect(find.text('展示输入状态'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('展示输入状态')), findsWidgets);
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
      semantics.dispose();
    });
  }
}
