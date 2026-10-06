import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group_setup/group_setup_logic.dart';
import 'package:openim/pages/chat/group_setup/group_setup_view.dart';
import 'package:openim_common/openim_common.dart';

class _PreviewLogic implements GroupSetupLogic {
  @override
  final isJoinedGroup = true.obs;
  @override
  final updating = false.obs;
  @override
  final avatar = Rx<File?>(null);
  @override
  final groupInfo = GroupInfo(
    groupID: 'preview-group',
    groupName: '群聊测试',
    memberCount: 10002,
    ownerUserID: 'owner',
  ).obs;
  @override
  final myGroupMembersInfo = GroupMembersInfo(nickname: '我的昵称').obs;
  @override
  final memberList = <GroupMembersInfo>[].obs;
  @override
  final membersLoading = false.obs;
  @override
  final membersFailed = false.obs;

  int retries = 0;

  @override
  bool get isOwner => false;
  @override
  bool get isAdmin => true;
  @override
  bool get isOwnerOrAdmin => true;
  @override
  bool get isNotDisturb => false;
  @override
  bool get isPinned => false;
  @override
  String? get myGroupNickname => '我的昵称';

  @override
  Future<void> getGroupMembers() async {
    retries++;
    membersFailed.value = false;
    membersLoading.value = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpPage(
  WidgetTester tester,
  _PreviewLogic logic, {
  required bool dark,
}) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  Styles.isDark = dark;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => Styles.isDark = false);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: GroupSetupPage(logic: logic),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder get _previewRow =>
    find.byKey(const ValueKey('group-member-preview-row'));
Finder get _retry => find.byKey(const ValueKey('group-member-preview-retry'));
Finder get _placeholders => find.byWidgetPredicate((widget) =>
    widget.key is ValueKey<String> &&
    (widget.key! as ValueKey<String>)
        .value
        .startsWith('group-member-placeholder-'));

void main() {
  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('$theme loading shows six member placeholders at 320px',
        (tester) async {
      final logic = _PreviewLogic()..membersLoading.value = true;
      await _pumpPage(tester, logic, dark: dark);

      expect(_placeholders, findsNWidgets(6));
      expect(_retry, findsNothing);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
      expect(find.text('共10002人'), findsOneWidget);
      final circle = tester.widget<CircleAvatar>(find.descendant(
        of: _placeholders.first,
        matching: find.byType(CircleAvatar),
      ));
      expect(circle.backgroundColor, Styles.c_E8EAEF);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$theme failed preview offers inline retry and keeps actions',
        (tester) async {
      final logic = _PreviewLogic()..membersFailed.value = true;
      await _pumpPage(tester, logic, dark: dark);

      final message = find.text('群成员加载失败，点击重试');
      expect(message, findsOneWidget);
      expect(tester.widget<Text>(message).style!.color, Styles.c_8E9AB0);
      expect(_placeholders, findsNothing);
      final rowBefore = tester.getRect(_previewRow);
      final addBefore = tester.getRect(find.byIcon(Icons.add));
      final removeBefore = tester.getRect(find.byIcon(Icons.remove));
      await tester.tap(_retry);
      await tester.pump();

      expect(logic.retries, 1);
      expect(_placeholders, findsNWidgets(6));
      expect(message, findsNothing);
      expect(tester.getRect(_previewRow), rowBefore);
      expect(tester.getRect(find.byIcon(Icons.add)), addBefore);
      expect(tester.getRect(find.byIcon(Icons.remove)), removeBefore);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$theme empty preview can be retried without an empty gap',
        (tester) async {
      final logic = _PreviewLogic();
      await _pumpPage(tester, logic, dark: dark);

      expect(find.text('暂未获取到群成员，点击重试'), findsOneWidget);
      expect(_placeholders, findsNothing);
      await tester.tap(_retry);
      await tester.pump();
      expect(logic.retries, 1);
      expect(_placeholders, findsNWidgets(6));
      expect(tester.takeException(), isNull);
    });

    testWidgets('$theme cached members stay visible during loading or failure',
        (tester) async {
      final logic = _PreviewLogic()
        ..membersLoading.value = true
        ..membersFailed.value = true;
      logic.memberList.addAll([
        GroupMembersInfo(userID: 'owner', nickname: '群主甲'),
        GroupMembersInfo(userID: 'member', nickname: '成员乙'),
      ]);
      await _pumpPage(tester, logic, dark: dark);

      expect(find.text('群主甲'), findsOneWidget);
      expect(find.text('成员乙'), findsOneWidget);
      expect(_placeholders, findsNothing);
      expect(_retry, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$theme preview arrival preserves height and action positions',
        (tester) async {
      final logic = _PreviewLogic()..membersLoading.value = true;
      await _pumpPage(tester, logic, dark: dark);
      final rowBefore = tester.getRect(_previewRow);
      final addBefore = tester.getRect(find.byIcon(Icons.add));
      final removeBefore = tester.getRect(find.byIcon(Icons.remove));

      logic.memberList.add(GroupMembersInfo(userID: 'owner', nickname: '群主甲'));
      logic.membersLoading.value = false;
      await tester.pump();

      expect(find.text('群主甲'), findsOneWidget);
      expect(_placeholders, findsNothing);
      expect(tester.getRect(_previewRow), rowBefore);
      expect(tester.getRect(find.byIcon(Icons.add)), addBefore);
      expect(tester.getRect(find.byIcon(Icons.remove)), removeBefore);
      expect(tester.takeException(), isNull);
    });
  }
}
