import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/blacklist/blacklist_logic.dart';
import 'package:openim/pages/mine/blacklist/blacklist_view.dart';

class _Logic extends BlacklistLogic {
  int loads = 0;
  @override
  void onReady() {}
  @override
  Future<void> loadBlacklist() async {
    loads++;
    loading.value = true;
    failed.value = false;
  }
}

Widget host(Widget child) => ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (context, _) => MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child));

void main() {
  tearDown(Get.reset);
  testWidgets('search filters names and blocked IDs and can be cleared',
      (tester) async {
    final logic = Get.put<BlacklistLogic>(_Logic());
    logic.loading.value = false;
    logic.blacklist.assignAll([
      BlacklistInfo(
          nickname: 'Alice', blockUserID: 'contact-1', userID: 'owner'),
      BlacklistInfo(nickname: '小明', blockUserID: 'contact-2'),
    ]);
    await tester.pumpWidget(host(BlacklistPage()));
    await tester.enterText(find.byType(TextField), ' ALICE ');
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('小明'), findsNothing);
    await tester.enterText(find.byType(TextField), 'contact-2');
    await tester.pump();
    expect(find.text('Alice'), findsNothing);
    expect(find.text('小明'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'owner');
    await tester.pump();
    expect(find.text('未找到匹配的联系人'), findsOneWidget);
    await tester.tap(find.text('清空搜索'));
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('小明'), findsOneWidget);
    expect(logic.searchController.text, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('loading does not flash empty state and failure offers retry',
      (tester) async {
    final logic = Get.put<BlacklistLogic>(_Logic()) as _Logic;
    await tester.pumpWidget(host(BlacklistPage()));
    expect(find.text('暂无黑名单联系人'), findsNothing);
    logic.loading.value = false;
    logic.failed.value = true;
    await tester.pump();
    expect(find.text('黑名单加载失败'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pump();
    expect(logic.loads, 1);
    expect(find.text('黑名单加载失败'), findsNothing);
    logic.loading.value = false;
    await tester.pump();
    expect(find.text('暂无黑名单联系人'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('黑名单'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
