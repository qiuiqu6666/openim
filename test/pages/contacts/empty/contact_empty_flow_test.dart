import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/empty/contact_list_placeholder.dart';
import 'package:openim/pages/contacts/group_list/group_list_logic.dart';
import 'package:openim/pages/contacts/group_list/group_list_view.dart';
import 'package:openim_common/openim_common.dart';

class _Groups extends GroupListLogic {
  _Groups(Future<List<GroupInfo>> Function(int, int) fetch)
      : super(fetchPage: fetch, currentUserID: () => 'self');

  @override
  // Skip the unrelated IM event bus; exercise real requests and refresh state.
  // ignore: must_call_super
  void onInit() {
    iCreatedInitial();
    iJoinedInitial();
  }
}

Future<void> _mount(WidgetTester tester, Widget page,
    {bool dark = false,
    Size size = const Size(375, 812),
    double scale = 1}) async {
  Get.testMode = true;
  Styles.isDark = dark;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
    Styles.isDark = false;
    tester.view.reset();
  });
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: page,
    ),
  ));
  await tester.pump();
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('group empty state keeps tabs and pull-to-refresh ($dark)',
        (tester) async {
      final requests = <Completer<List<GroupInfo>>>[];
      final logic = _Groups((_, __) {
        final result = Completer<List<GroupInfo>>();
        requests.add(result);
        return result.future;
      });
      Get.put<GroupListLogic>(logic);
      await _mount(tester, GroupListPage(), dark: dark);
      expect(find.text('暂无创建的群聊'), findsNothing);
      requests[0].complete([]);
      requests[1].complete([]);
      await tester.pumpAndSettle();
      expect(find.text('暂无创建的群聊'), findsOneWidget);
      await tester.tap(find.text(StrRes.iJoinedGroup));
      await tester.pumpAndSettle();
      expect(find.text('暂无加入的群聊'), findsOneWidget);
      await tester.drag(
          find.byType(CustomScrollView).first, const Offset(0, 300));
      for (var i = 0; i < 10 && requests.length == 2; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(requests, hasLength(3));
      requests.last.complete([
        GroupInfo(groupID: 'joined', groupName: '新加入的群聊', ownerUserID: 'other'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('暂无加入的群聊'), findsNothing);
      expect(find.text('新加入的群聊'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed first group load can retry to a confirmed empty result',
      (tester) async {
    var fail = true;
    final logic = _Groups((_, __) async {
      if (fail) throw StateError('offline');
      return [];
    });
    Get.put<GroupListLogic>(logic);
    await _mount(tester, GroupListPage());
    await tester.pumpAndSettle();
    expect(find.text('暂无创建的群聊'), findsNothing);
    expect(find.text('加载失败，请重试'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂无创建的群聊'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty illustration scrolls on short screens with large text',
      (tester) async {
    var retried = false;
    await _mount(
      tester,
      Scaffold(
          body: Builder(
              builder: (context) => contactListPlaceholder(
                    context,
                    title: '暂无好友申请',
                    loading: false,
                    failed: true,
                    onRetry: () => retried = true,
                  ))),
      dark: true,
      size: const Size(320, 240),
      scale: 2,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('重试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    expect(retried, isTrue);
    expect(tester.takeException(), isNull);
  });
}
