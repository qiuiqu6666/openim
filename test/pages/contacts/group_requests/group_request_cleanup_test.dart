import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_requests/group_requests_logic.dart';
import 'package:openim/pages/contacts/group_requests/group_requests_view.dart';
import 'package:openim/pages/contacts/request_history/data/request_history_store.dart';
import 'package:openim/pages/contacts/request_history/widgets/request_history_swipe_row.dart';
import 'package:openim_common/openim_common.dart';

import 'support/group_requests_test_fixture.dart';

void main() {
  late GroupRequestsFixture fixture;
  setUp(() async {
    fixture = GroupRequestsFixture();
    await fixture.initialize();
  });
  tearDown(() async {
    Styles.isDark = false;
    await fixture.dispose();
  });

  testWidgets('clear hides all 45 records after reload and accepts new notices',
      (tester) async {
    fixture.recipient = [for (var i = 45; i > 0; i--) request(time: i)];
    final logic = await fixture.mount(tester);
    expect(logic.list, hasLength(20));
    await logic.clearRequests();
    expect(logic.list, isEmpty);
    expect(logic.hasMore.value, isFalse);
    await fixture.refresh(tester, logic);
    expect(logic.list, isEmpty);
    expect(logic.hasMore.value, isFalse);
    fixture.recipient.insert(0, request(time: 46));
    await fixture.refresh(tester, logic);
    expect(logic.list.map((row) => row.reqTime), [46]);
    expect(logic.hasMore.value, isFalse);
    expect(fixture.callsFor('acceptGroupApplication'), isEmpty);
    expect(fixture.callsFor('refuseGroupApplication'), isEmpty);
  });

  testWidgets('SDK refresh already in flight cannot restore a deleted row',
      (tester) async {
    fixture.recipient = [request(time: 2), request(time: 1)];
    final logic = await fixture.mount(tester);
    fixture.holdRecipient = true;
    final pending = logic.getApplicationList();
    await tester.pump(const Duration(milliseconds: 2));
    await logic.deleteRequest(logic.list.first);
    fixture.recipientReplies.single.complete(
        jsonEncode(fixture.recipient.map((row) => row.toJson()).toList()));
    await tester.pumpAndSettle();
    await pending;
    expect(logic.list.map((row) => row.reqTime), [1]);
  });

  testWidgets('old page cannot clear records after an account switch',
      (tester) async {
    fixture.recipient = [request()];
    final logic = await fixture.mount(tester);
    OpenIM.iMManager.userID = 'another-account';
    await logic.clearRequests();
    expect(
        RequestHistoryStore('current-admin', RequestHistoryKind.group)
            .isHidden(RequestHistoryEntry.group(request())),
        isFalse);
    expect(logic.list, hasLength(1));
  });

  for (final brightness in Brightness.values) {
    testWidgets('swipe delete and confirmed clear work in $brightness',
        (tester) async {
      fixture.recipient = [request(time: 2), request(time: 1)];
      Styles.isDark = brightness == Brightness.dark;
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final logic = Get.put(GroupRequestsLogic());
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          locale: const Locale('zh', 'CN'),
          translations: TranslationService(),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('zh', 'CN')],
          theme: ThemeData(brightness: brightness),
          builder: EasyLoading.init(),
          home: GroupRequestsPage(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text(StrRes.newGroupRequest)).dx,
          closeTo(187.5, .01));
      await tester.drag(
          find.byType(RequestHistorySwipeRow).first, const Offset(-240, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text(StrRes.delete).first);
      await tester.pumpAndSettle();
      expect(logic.list.map((row) => row.reqTime), [1]);
      await tester.tap(find.byKey(const ValueKey('request-history-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('request-history-clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(StrRes.cancel));
      await tester.pumpAndSettle();
      expect(logic.list, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('request-history-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('request-history-clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(CustomDialog), matching: find.text(StrRes.clearAll)));
      await tester.pumpAndSettle();
      expect(find.text(StrRes.emptyGroupNotification), findsOneWidget);
      expect(
          tester
              .widget<IconButton>(
                  find.byKey(const ValueKey('request-history-more')))
              .onPressed,
          isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
