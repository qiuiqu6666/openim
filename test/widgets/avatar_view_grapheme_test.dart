import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  tearDown(Get.reset);

  for (final example in [
    (name: '🍀好友', initial: '🍀'),
    (name: '👩🏽‍💻工程师', initial: '👩🏽‍💻'),
    (name: 'e\u0301lodie', initial: 'e\u0301'),
    (name: '张三', initial: '张'),
  ]) {
    testWidgets('avatar renders the complete first grapheme of ${example.name}',
        (tester) async {
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          home: Scaffold(
            body: Center(
              child: AvatarView(
                text: example.name,
                width: 48,
                height: 48,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(
          find.descendant(
              of: find.byType(AvatarView),
              matching: find.text(example.initial)),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
