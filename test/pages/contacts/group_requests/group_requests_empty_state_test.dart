import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_requests/group_requests_logic.dart';
import 'package:openim/pages/contacts/group_requests/group_requests_view.dart';
import 'package:openim_common/openim_common.dart';

import 'support/group_requests_test_fixture.dart';

Future<void> _open(WidgetTester tester, Brightness brightness) async {
  Styles.isDark = brightness == Brightness.dark;
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Get.put(GroupRequestsLogic());
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      locale: const Locale('zh', 'CN'),
      translations: TranslationService(),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: brightness),
      builder: EasyLoading.init(),
      home: GroupRequestsPage(),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 2));
}

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

  for (final brightness in Brightness.values) {
    testWidgets(
        'empty notices wait for SDK and recover on events ($brightness)',
        (tester) async {
      fixture.holdRecipient = true;
      await _open(tester, brightness);
      expect(find.text(StrRes.emptyGroupNotification), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      fixture.recipientReplies.single.complete('[]');
      await tester.pumpAndSettle();
      expect(find.text(StrRes.emptyGroupNotification), findsOneWidget);
      final illustration = find.byWidgetPredicate((widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              'assets/images/empty_99chat.webp');
      expect(illustration, findsOneWidget);

      fixture.holdRecipient = false;
      fixture.recipient = [request()];
      fixture.im.groupApplicationChangedSubject.add(request());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pumpAndSettle();
      expect(find.text(StrRes.emptyGroupNotification), findsNothing);
      expect(find.text(StrRes.lookOver), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed notices offer retry instead of an empty result',
      (tester) async {
    fixture.failApplications = true;
    await _open(tester, Brightness.light);
    await tester.pumpAndSettle();
    expect(find.text(StrRes.emptyGroupNotification), findsNothing);
    expect(find.text('加载失败，请重试'), findsOneWidget);
    fixture.failApplications = false;
    await tester.tap(find.text('重试'));
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();
    expect(find.text(StrRes.emptyGroupNotification), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
