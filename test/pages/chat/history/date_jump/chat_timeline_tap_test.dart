import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tip = '07:16';
const _bubbleTime = '07:17';
const _action = '选择日期跳转';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    testWidgets(
        'centered tip has a 48-pixel date action, while bubble time is passive / ${brightness.name}',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await _mount(tester, brightness: brightness, onTapTimeline: () => taps++);

      final button =
          find.ancestor(of: find.text(_tip), matching: find.byType(TextButton));
      expect(button, findsOneWidget);
      final rect = tester.getRect(button);
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.center.dx, closeTo(375 / 2, .1));

      final data = tester
          .getSemantics(find.bySemanticsLabel('$_tip, $_action'))
          .getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);

      await tester.tap(find.text(_tip));
      await tester.pump();
      expect(taps, 1);
      // The enlarged part of the date target must work too, once per tap.
      await tester.tapAt(Offset(rect.center.dx, rect.top + 2));
      await tester.pump();
      expect(taps, 2);

      await tester.tap(find.text(_bubbleTime));
      await tester.pump();
      expect(taps, 2);
      expect(
          find.ancestor(
              of: find.text(_bubbleTime), matching: find.byType(TextButton)),
          findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets(
        'passive message previews have no date button / ${brightness.name}',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _mount(tester, brightness: brightness);
      expect(find.text(_tip), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(find.bySemanticsLabel('$_tip, $_action'), findsNothing);
      final data = tester.getSemantics(find.text(_tip)).getSemanticsData();
      expect(data.flagsCollection.isButton, isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      await tester.tap(find.text(_tip));
      await tester.pump();
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}

Future<void> _mount(
  WidgetTester tester, {
  required Brightness brightness,
  VoidCallback? onTapTimeline,
}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final wasDark = Styles.isDark;
  Styles.isDark = brightness == Brightness.dark;
  addTearDown(() => Styles.isDark = wasDark);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.only(top: 100),
          child: ChatItemContainer(
            id: 'date-tip-message',
            timelineStr: _tip,
            onTapTimeline: onTapTimeline,
            timelineSemanticLabel: _action,
            timeStr: _bubbleTime,
            isBubbleBg: true,
            isISend: true,
            hasRead: true,
            isSending: false,
            isSendFailed: false,
            child: const Text('聊天消息'),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}
