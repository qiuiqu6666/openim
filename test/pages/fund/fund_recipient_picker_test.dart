import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/fund/fund_recipient_picker.dart';
import 'package:openim_common/openim_common.dart';

GroupMembersInfo member(String id, String name) =>
    GroupMembersInfo(userID: id, nickname: name);

void main() {
  setUp(() {
    OpenIM.iMManager.userID = 'me';
    Get.testMode = true;
    Get.locale = const Locale('zh', 'CN');
  });
  tearDown(Get.reset);

  Future<void> open(WidgetTester tester, FundMemberLoader loader,
      {ValueChanged<GroupMembersInfo?>? onSelected}) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        navigatorKey: nav,
        home: const Scaffold(),
      ),
    ));
    nav.currentState!
        .push<GroupMembersInfo>(MaterialPageRoute(
            builder: (_) =>
                FundRecipientPicker(groupID: 'group', memberLoader: loader)))
        .then((value) => onSelected?.call(value));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('shows reference avatar rows and returns one actual SDK member',
      (tester) async {
    GroupMembersInfo? selected;
    await open(
        tester,
        (_, __, ___) async => [
              member('me', '我'),
              member('a', '小林'),
              member('a', '重复'),
              member('', '无效'),
              member('b', '阿明'),
            ],
        onSelected: (value) => selected = value);
    expect(find.text('选择接收人'), findsOneWidget);
    expect(find.text('小林'), findsOneWidget);
    expect(find.text('重复'), findsNothing);
    expect(find.text('无效'), findsNothing);
    final avatars = tester.widgetList<AvatarView>(find.byType(AvatarView));
    expect(avatars, hasLength(2));
    expect(
        avatars
            .every((avatar) => avatar.isCircle == true && avatar.width == 42),
        isTrue);
    await tester.tap(find.byKey(const ValueKey('fund-member-a')));
    await tester.pumpAndSettle();
    expect(selected?.userID, 'a');
    expect(selected?.nickname, '小林');
  });

  testWidgets('new search ignores the earlier in-flight response',
      (tester) async {
    final initial = Completer<List<GroupMembersInfo>>();
    final searched = Completer<List<GroupMembersInfo>>();
    final queries = <String>[];
    await open(tester, (query, offset, count) {
      queries.add(query);
      expect(offset, 0);
      expect(count, 50);
      return query.isEmpty ? initial.future : searched.future;
    });
    await tester.enterText(find.byType(TextField), '小林');
    await tester.pump(const Duration(milliseconds: 310));
    initial.complete([member('old', '旧成员')]);
    await tester.pump();
    expect(find.text('旧成员'), findsNothing);
    searched.complete([member('new', '小林')]);
    await tester.pumpAndSettle();
    expect(queries, ['', '小林']);
    expect(find.byKey(const ValueKey('fund-member-new')), findsOneWidget);
  });

  testWidgets('scroll loads the next SDK page once and stops at the final page',
      (tester) async {
    final offsets = <int>[];
    await open(tester, (_, offset, __) async {
      offsets.add(offset);
      return offset == 0
          ? [for (var i = 0; i < 50; i++) member('u$i', '成员$i')]
          : [member('last', '最后成员')];
    });
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(offsets, [0, 50]);
    expect(find.text('最后成员'), findsOneWidget);
    expect(find.text('加载更多成员'), findsNothing);
  });

  testWidgets(
      'account switch drops stale members and cannot select another identity',
      (tester) async {
    final response = Completer<List<GroupMembersInfo>>();
    await open(tester, (_, __, ___) => response.future);
    OpenIM.iMManager.userID = 'other-account';
    response.complete([member('a', '旧账户成员')]);
    await tester.pumpAndSettle();
    expect(find.text('旧账户成员'), findsNothing);
    await tester.enterText(find.byType(TextField), '小林');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pumpAndSettle();
    expect(find.text('账户已切换，请重新打开'), findsOneWidget);
  });

  testWidgets('failed member loading offers a retry using real loader data',
      (tester) async {
    var attempts = 0;
    await open(tester, (_, __, ___) async {
      if (++attempts == 1) throw StateError('offline');
      return [member('a', '恢复成员')];
    });
    await tester.tap(find.text('成员加载失败，请重试'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('恢复成员'), findsOneWidget);
  });
}
