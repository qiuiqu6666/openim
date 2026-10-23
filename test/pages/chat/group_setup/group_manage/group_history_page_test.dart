import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim/pages/chat/group_setup/group_manage/history_visibility/group_history_page.dart';
import 'package:openim_common/openim_common.dart';
import 'dart:convert';
import 'package:openim/core/controller/im_controller.dart';
import 'package:rxdart/rxdart.dart';

class _IM extends GetxController implements IMController {
  @override
  final groupInfoUpdatedSubject = PublishSubject<GroupInfo>();
  @override
  void close() => groupInfoUpdatedSubject.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Logic extends GetxController implements GroupSetupLogic {
  bool valid = true;
  @override
  final imLogic = _IM();
  @override
  void applyGroupInfo(GroupInfo value) => groupInfo.value = value;
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
  bool isPermissionContextCurrent(GroupSetupPermissionContext context) => valid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'owner saves selection and preserves latest metadata dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final logic = _Logic();
      final previousDark = Styles.isDark;
      Styles.isDark = dark;
      addTearDown(() {
        Styles.isDark = previousDark;
        logic.imLogic.close();
      });
      const channel = MethodChannel('flutter_openim_sdk');
      final writes = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getGroupMembersInfo':
            return '[{"groupID":"g","userID":"u","roleLevel":100}]';
          case 'getGroupsInfo':
            return jsonEncode([
              {
                'groupID': 'g',
                'ex': jsonEncode({'gameType': 3})
              }
            ]);
          case 'setGroupInfo':
            writes.add(call);
            return '';
          default:
            throw StateError(call.method);
        }
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: MediaQuery(
              data: const MediaQueryData(
                  size: Size(320, 760), textScaler: TextScaler.linear(2)),
              child: GroupHistoryPage(logic: logic))));
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          AppTokens.background(dark: dark));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.text('仅查看入群后消息'));
      await tester.pump();
      await tester.ensureVisible(find.text('保存'));
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.style!.backgroundColor!.resolve({}), AppTokens.accent);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(jsonDecode(logic.groupInfo.value.ex!),
          {'gameType': 3, 'enableHistoryForNewMembers': false});
      expect(tester.takeException(), isNull);
    });
  }
  for (final role in [
    GroupRoleLevel.owner,
    GroupRoleLevel.admin,
    GroupRoleLevel.member
  ]) {
    testWidgets('save rechecks SDK role $role before writing history policy',
        (tester) async {
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
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) =>
            MaterialApp(home: GroupHistoryPage(logic: _Logic())),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('保存'), 300);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(calls.contains('setGroupInfo'), role == GroupRoleLevel.owner);
      expect(find.text('保存失败，请确认群主权限后重试'), findsOneWidget);
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(calls.where((call) => call == 'setGroupInfo').length,
          role == GroupRoleLevel.owner ? 2 : 0);
      expect(tester.takeException(), isNull);
    });
  }
}
