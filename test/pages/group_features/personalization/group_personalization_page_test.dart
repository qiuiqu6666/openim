import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim/pages/group_features/personalization/group_personalization_page.dart';
import 'package:openim_common/openim_common.dart';

class _Logic extends GetxController implements GroupSetupLogic {
  @override
  final groupInfo = GroupInfo(groupID: 'g', groupName: '示例群聊').obs;
  @override
  bool get isOwner => true;
  @override
  bool get isOwnerOrAdmin => true;
  @override
  GroupSetupPermissionContext capturePermissionContext() => (
        account: 'u',
        sdkAccount: 'u',
        token: 't',
        server: 's',
        groupID: 'g',
        generation: 0
      );
  @override
  bool isPermissionContextCurrent(GroupSetupPermissionContext context) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final role in [GroupRoleLevel.owner, GroupRoleLevel.admin, GroupRoleLevel.member]) {
    testWidgets('save rechecks SDK role $role before writing appearance', (tester) async {
      const channel = MethodChannel('flutter_openim_sdk');
      OpenIM.iMManager.userID = 'u';
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'getGroupMembersInfo') {
          return '[{"groupID":"g","userID":"u","roleLevel":$role}]';
        }
        if (call.method == 'getGroupsInfo') {
          return '[{"groupID":"g","groupName":"示例群聊","ex":"{}"}]';
        }
        if (call.method == 'setGroupInfo') {
          // Stop at the transport boundary; this test verifies authorization,
          // including demotion after opening an editable page.
          throw PlatformException(code: 'offline');
        }
        throw StateError(call.method);
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(home: GroupPersonalizationPage(logic: _Logic())),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('保存'), 300);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(calls.contains('setGroupInfo'), role != GroupRoleLevel.member);
      expect(find.text('保存失败，请确认管理权限后重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    testWidgets('preview color and reset fit narrow large-text screen: $dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previous = Styles.isDark;
      Styles.isDark = dark;
      addTearDown(() => Styles.isDark = previous);
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
                theme: ThemeData(
                    brightness: dark ? Brightness.dark : Brightness.light),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: child!),
                home: GroupPersonalizationPage(logic: _Logic()),
              )));
      await tester.tap(find.byTooltip('蓝色'));
      await tester.pump();
      expect(tester.widget<Text>(find.text('示例群聊')).style?.color,
          const Color(0xFF008BFF));
      await tester.ensureVisible(find.text('恢复默认'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认'));
      await tester.pump();
      expect(tester.widget<Text>(find.text('示例群聊')).style?.color,
          isNot(const Color(0xFF008BFF)));
      expect(tester.takeException(), isNull);
    });
  }
}
