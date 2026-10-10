import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/theme/app_theme_data.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets(
      'an open phone-code selector preserves search across theme changes',
      (tester) async {
    final mode = ValueNotifier(ThemeMode.light);
    String? picked;
    addTearDown(() {
      mode.dispose();
      Get.reset();
    });
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (_, value, __) => GetMaterialApp(
          theme: buildAppThemeData(Brightness.light),
          darkTheme: buildAppThemeData(Brightness.dark),
          themeMode: value,
          locale: const Locale('en', 'US'),
          home: Scaffold(
            body: TextButton(
              onPressed: () =>
                  IMViews.showCountryCodePicker().then((code) => picked = code),
              child: const Text('Select code'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Select code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Canada');
    await tester.pumpAndSettle();
    final canada = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'Canada');
    expect(canada, findsOneWidget);
    final sheetState = tester.state(find.byType(BottomSheet));
    mode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(BottomSheet)), same(sheetState));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Canada');
    final fieldContext = tester.element(find.byType(TextField));
    final theme = Theme.of(fieldContext);
    expect(theme.brightness, Brightness.dark);
    final paintedSheet = tester
        .widgetList<Material>(find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(Material)))
        .first;
    expect(paintedSheet.color!.computeLuminance(), lessThan(.1));
    await tester.tap(canada);
    await tester.pumpAndSettle();
    expect(picked, '+1');
    expect(tester.takeException(), isNull);
  });
}
