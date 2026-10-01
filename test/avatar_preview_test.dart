import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final isGroup in [false, true]) {
    testWidgets('${isGroup ? 'group' : 'user'} avatar preview has save button',
        (tester) async {
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          home: Scaffold(
            body: Center(
              child: AvatarView(
                width: 48,
                height: 48,
                url: 'https://example.com/avatar.png',
                isGroup: isGroup,
                enabledPreview: true,
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.descendant(
        of: find.byType(AvatarView),
        matching: find.byType(GestureDetector),
      ).first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      expect(find.byType(IconButton), findsOneWidget);
    });
  }
}
