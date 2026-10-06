import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_requests/widgets/group_request_handler_label.dart';
import 'package:openim_common/openim_common.dart';

Future<void> _mount(
  WidgetTester tester,
  String? nickname, {
  Locale locale = const Locale('zh', 'CN'),
  Brightness brightness = Brightness.light,
  TextAlign textAlign = TextAlign.start,
  double textScale = 1,
}) async {
  Styles.isDark = brightness == Brightness.dark;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      locale: locale,
      translations: TranslationService(),
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Center(
            child: SizedBox(
              width: 320,
              child: GroupRequestHandlerLabel(
                nickname: nickname,
                textAlign: textAlign,
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  final update = Get.updateLocale(locale);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pumpAndSettle();
  await update;
}

void main() {
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });

  testWidgets('confirmed nickname is localized and trimmed', (tester) async {
    await _mount(tester, '  阿秋  ');
    expect(find.text('处理人：阿秋'), findsOneWidget);
    await _mount(tester, ' Alice ', locale: const Locale('en', 'US'));
    expect(find.text('Handled by: Alice'), findsOneWidget);
  });

  testWidgets('missing nicknames occupy no label or reserved vertical space',
      (tester) async {
    for (final nickname in [null, '', '   ']) {
      await _mount(tester, nickname);
      expect(find.byType(Text), findsNothing);
      expect(tester.getSize(find.byType(GroupRequestHandlerLabel)).height, 0);
    }
  });

  testWidgets('detail can center the same reusable handler label',
      (tester) async {
    await _mount(tester, '阿秋', textAlign: TextAlign.center);
    final text = tester.widget<Text>(find.text('处理人：阿秋'));
    expect(text.textAlign, TextAlign.center);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'long handler uses a readable single line in ${brightness.name}',
        (tester) async {
      final nickname = List.filled(20, '管理员昵称👩‍💻').join();
      await _mount(tester, nickname, brightness: brightness, textScale: 2);
      final textFinder = find.byType(Text);
      final text = tester.widget<Text>(textFinder);
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.style!.color, Styles.c_8E9AB0);
      expect(text.style!.color, isNot(Styles.c_0C1C33));
      final labelBounds = tester.getRect(find.byType(GroupRequestHandlerLabel));
      final textBounds = tester.getRect(textFinder);
      expect(textBounds.right, lessThanOrEqualTo(labelBounds.right));
      expect(textBounds.left, greaterThanOrEqualTo(labelBounds.left));
      expect(textBounds.width, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    });
  }
}
