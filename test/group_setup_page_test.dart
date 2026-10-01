import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim/pages/chat/group_setup/group_setup_view.dart';
import 'package:openim_common/openim_common.dart';

class _FakeGroupSetupLogic implements GroupSetupLogic {
  @override
  final isJoinedGroup = true.obs;
  @override
  final updating = false.obs;
  @override
  final avatar = Rx<File?>(null);
  @override
  final groupInfo = Rx(GroupInfo(
      groupID: 'TGS12345678901234567890', groupName: '测试群聊', memberCount: 3));
  @override
  final myGroupMembersInfo = Rx(GroupMembersInfo(nickname: '我的群昵称'));
  @override
  final memberList = <GroupMembersInfo>[
    GroupMembersInfo(userID: '1', nickname: '成员一'),
    GroupMembersInfo(userID: '2', nickname: '成员二'),
  ].obs;
  @override
  bool get isOwner => false;
  @override
  bool get isAdmin => false;
  @override
  bool get isOwnerOrAdmin => false;
  @override
  bool get isNotDisturb => false;
  @override
  bool get isPinned => true;
  @override
  String? get myGroupNickname => '我的群昵称';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('group info cards fit on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final logic = _FakeGroupSetupLogic();

    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        home: GroupSetupPage(logic: logic),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('群聊'), findsOneWidget);
    expect(find.text('测试群聊'), findsOneWidget);
    expect(find.text('群成员'), findsOneWidget);
    expect(find.text('共3人'), findsOneWidget);
    expect(find.text('群ID'), findsOneWidget);
    expect(find.text('消息免打扰'), findsOneWidget);
    expect(find.text('置顶聊天'), findsOneWidget);
    final chevrons = find.byIcon(Icons.chevron_right_rounded);
    expect(chevrons, findsNWidgets(5));
    final arrowPositions =
        List.generate(5, (index) => tester.getTopLeft(chevrons.at(index)).dx);
    expect(arrowPositions.every((x) => x > 260), isTrue);
    expect(
        arrowPositions.reduce((a, b) => a > b ? a : b) -
            arrowPositions.reduce((a, b) => a < b ? a : b),
        lessThan(1));
    expect(tester.takeException(), isNull);
  });
}
