import 'package:azlistview/azlistview.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/country_code_page.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final language in ['zh', 'en']) {
    for (final dark in [false, true]) {
      testWidgets(
          'country list and index fit small screen $language dark=$dark',
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
                locale: Locale(language),
                supportedLocales: const [Locale('zh'), Locale('en')],
                localizationsDelegates: const [
                  CountryLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                theme: ThemeData(
                    brightness: dark ? Brightness.dark : Brightness.light),
                home: const CountryCodePage(selectedCode: '+86'))));
        await tester.pumpAndSettle();
        final afghanistan = language == 'zh' ? '阿富汗' : 'Afghanistan';
        final canada = language == 'zh' ? '加拿大' : 'Canada';
        expect(find.text(afghanistan), findsOneWidget);
        final rows = tester.widget<AzListView>(find.byType(AzListView)).data;
        String tagFor(String code) => rows
            .cast<dynamic>()
            .firstWhere((row) => row.country.countryCode == code)
            .getSuspensionTag() as String;
        expect(tagFor('CN'), language == 'zh' ? 'Z' : 'C');
        expect(tagFor('US'), language == 'zh' ? 'M' : 'U');
        expect(tagFor('CA'), language == 'zh' ? 'J' : 'C');
        expect(tagFor('ZW'), language == 'zh' ? 'J' : 'Z');
        await tester.tap(find.text('Z').last);
        await tester.pumpAndSettle();
        expect(find.text(language == 'zh' ? '中国' : 'Zimbabwe'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Canada');
        await tester.pumpAndSettle();
        expect(
            find.byWidgetPredicate(
                (widget) => widget is Text && widget.data == canada),
            findsOneWidget);
        expect(find.text(afghanistan), findsNothing);
        if (language == 'zh') {
          await tester.enterText(find.byType(TextField), '加拿大');
          await tester.pumpAndSettle();
          expect(
              find.byWidgetPredicate(
                  (widget) => widget is Text && widget.data == '加拿大'),
              findsOneWidget);
        }
        await tester.enterText(find.byType(TextField), '+86');
        await tester.pumpAndSettle();
        expect(find.text(language == 'zh' ? '中国' : 'China'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
