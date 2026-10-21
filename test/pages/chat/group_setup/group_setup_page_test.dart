import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim/pages/chat/group_setup/group_setup_view.dart';
import 'package:openim/pages/chat/group_setup/loading/group_setup_membership.dart';
import 'package:openim_common/openim_common.dart';

class _FakeGroupSetupLogic implements GroupSetupLogic {
  _FakeGroupSetupLogic({this.manager = false});
  final bool manager;
  int avatarChanges = 0;
  int nameEdits = 0;
  int searches = 0;
  int invites = 0;
  int removals = 0;
  @override
  Future<void> removeMember() async {
    removals++;
  }
  @override
  void searchHistory() => searches++;
  @override
  Future<void> addMember() async {
    invites++;
  }

  @override
  bool get isClosed => false;
  @override
  void modifyGroupAvatar() => avatarChanges++;
  @override
  void modifyGroupName(String? faceUrl) => nameEdits++;
  @override
  final membership = GroupSetupMembership();
  int retries = 0;
  @override
  Future<void> refreshMembership() async {
    retries++;
    membership.failed.value = false;
  }

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
  bool get isOwnerOrAdmin => manager;
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
  for (final manager in [false, true]) {
    testWidgets(
        'channel profile uses reference layout and real actions ($manager)',
        (tester) async {
      tester.view.physicalSize = const Size(375, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final logic = _FakeGroupSetupLogic(manager: manager);
      logic.groupInfo.value.ex = '{"conversationKind":"channel"}';
      logic.membership.accept();
      addTearDown(logic.membership.dispose);
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
              translations: TranslationService(),
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: GroupSetupPage(logic: logic))));
      await tester.pumpAndSettle();
      expect(find.text('3位订阅者'), findsOneWidget);
      expect(find.text('频道别名'), findsOneWidget);
      expect(find.text('群成员'), findsNothing);
      expect(find.text('群公告'), findsNothing);
      expect(find.text('频道设置'), manager ? findsOneWidget : findsNothing);
      expect(find.text('移除订阅者'), manager ? findsOneWidget : findsNothing);
      await tester.tap(find.text('搜索'));
      expect(logic.searches, 1);
      if (manager) {
        await tester.tap(find.text('添加订阅者'));
        expect(logic.invites, 1);
        await tester.tap(find.text('移除订阅者'));
        expect(logic.removals, 1);
        logic.isJoinedGroup.value = false;
        await tester.pumpAndSettle();
        expect(find.text('移除订阅者'), findsNothing);
        expect(find.text('频道设置'), findsNothing);
        logic.isJoinedGroup.value = true;
        logic.membership.failed.value = true;
        await tester.pumpAndSettle();
        expect(find.text('移除订阅者'), findsNothing);
        expect(find.text('频道设置'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final manager in [false, true]) {
    testWidgets('group header avatar respects edit permission ($manager)',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final logic = _FakeGroupSetupLogic(manager: manager);
      addTearDown(logic.membership.dispose);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: GroupSetupPage(logic: logic),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AvatarView).first);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet),
          manager ? findsOneWidget : findsNothing);
      expect(logic.nameEdits, 0);
      if (manager) {
        await tester.tap(find.text(StrRes.selectAssetsFromAlbum));
        await tester.pumpAndSettle();
      }
      expect(logic.avatarChanges, manager ? 1 : 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [false, true]) {
    testWidgets('unresolved membership keeps header without delete ($dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Styles.isDark = dark;
      addTearDown(() => Styles.isDark = false);
      final logic = _FakeGroupSetupLogic()..isJoinedGroup.value = false;
      addTearDown(logic.membership.dispose);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: GroupSetupPage(logic: logic),
        ),
      ));
      await tester.pump();
      expect(find.text('测试群聊'), findsOneWidget);
      expect(find.text('正在加载群资料'), findsOneWidget);
      expect(find.text(StrRes.delete), findsNothing);
      expect(find.text(StrRes.exitGroup), findsNothing);
      logic.membership.defer();
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(find.text('群资料加载失败'), findsOneWidget);
      expect(find.text('测试群聊'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();
      expect(logic.retries, 1);
      expect(find.text('正在加载群资料'), findsOneWidget);
      logic.membership.accept();
      logic.isJoinedGroup.value = true;
      await tester.pumpAndSettle();
      expect(find.text('正在加载群资料'), findsNothing);
      expect(find.text('群成员'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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
    // A non-manager has four navigable rows; profile editing is unavailable.
    expect(chevrons, findsNWidgets(4));
    final arrowPositions =
        List.generate(4, (index) => tester.getTopLeft(chevrons.at(index)).dx);
    expect(arrowPositions.every((x) => x > 260), isTrue);
    expect(
        arrowPositions.reduce((a, b) => a > b ? a : b) -
            arrowPositions.reduce((a, b) => a < b ? a : b),
        lessThan(1));
    expect(tester.takeException(), isNull);
  });
}
