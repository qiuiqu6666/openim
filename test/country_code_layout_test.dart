import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/country_code_page.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('country list and index fit small screen dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previous = Styles.isDark;
      Styles.isDark = dark;
      addTearDown(() => Styles.isDark = previous);
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
              theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light),
              home: const CountryCodePage(selectedCode: '+86'))));
      await tester.pumpAndSettle();
      expect(find.text('Afghanistan'), findsOneWidget);
      await tester.tap(find.text('Z').last);
      await tester.pumpAndSettle();
      expect(find.text('Zimbabwe'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Canada');
      await tester.pumpAndSettle();
      expect(
          find.byWidgetPredicate(
              (widget) => widget is Text && widget.data == 'Canada'),
          findsOneWidget);
      expect(find.text('Afghanistan'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
