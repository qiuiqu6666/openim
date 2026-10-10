import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/pages/live_manage_page.dart';
import 'package:openim/pages/group_features/live/pages/live_tip_sheet.dart';
import 'package:openim/pages/group_features/live/widgets/live_sheet_surface.dart';
import 'package:openim/pages/group_features/live/widgets/live_style.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_test_support.dart';

Future<ValueNotifier<ThemeMode>> _mount(
    WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final mode = ValueNotifier(ThemeMode.light);
  addTearDown(mode.dispose);
  configureEasyLoadingInteractions();
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => ValueListenableBuilder<ThemeMode>(
          valueListenable: mode,
          builder: (_, value, __) => GetMaterialApp(
              translations: TranslationService(),
              locale: const Locale('zh', 'CN'),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              supportedLocales: const [Locale('zh', 'CN')],
              theme: ThemeData(brightness: Brightness.light),
              darkTheme: ThemeData(brightness: Brightness.dark),
              themeMode: value,
              builder: EasyLoading.init(),
              home: page))));
  await tester.pump();
  addTearDown(() async {
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  return mode;
}

void _expectSurface(WidgetTester tester, {required bool dark}) {
  final sheet = find.byType(LiveSheetSurface);
  final material = tester.widget<Material>(
      find.descendant(of: sheet, matching: find.byType(Material)).first);
  expect(material.color, AppTokens.surface(dark: dark));
  expect(Theme.of(tester.element(sheet)).brightness,
      dark ? Brightness.dark : Brightness.light);
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    Get.reset();
    Styles.isDark = false;
  });

  testWidgets('open tip sheet follows theme changes without clearing drafts',
      (tester) async {
    final transport = LiveTransport((_) => liveDTO(status: 'LIVE'));
    final mode = await _mount(
        tester,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => GroupLiveTipSheet.show(context,
                        featureContext: liveContext(transport.api()),
                        session: liveSession(status: LiveStatus.live)),
                    child: const Text('打开打赏')))));
    await tester.tap(find.text('打开打赏'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12.000001');
    await tester.enterText(find.byType(TextField).last, '谢谢主播');
    final amount =
        tester.widget<TextField>(find.byType(TextField).first).controller!;
    final memo =
        tester.widget<TextField>(find.byType(TextField).last).controller!;
    for (final dark in [false, true, false]) {
      mode.value = dark ? ThemeMode.dark : ThemeMode.light;
      await tester.pumpAndSettle();
      _expectSurface(tester, dark: dark);
      final fields =
          tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(identical(fields.first.controller, amount), isTrue);
      expect(identical(fields.last.controller, memo), isTrue);
      expect(amount.text, '12.000001');
      expect(memo.text, '谢谢主播');
      expect(Theme.of(tester.element(find.text('打赏主播'))).brightness,
          dark ? Brightness.dark : Brightness.light);
    }
    expect(transport.requests, isEmpty);
  });

  testWidgets('open schedule picker follows theme and preserves selected time',
      (tester) async {
    final transport = LiveTransport((_) => {'active': false});
    final mode = await _mount(
        tester, LiveManagePage(featureContext: liveContext(transport.api())));
    final context = tester.element(find.byType(LiveManagePage));
    await tester.runAsync(() async {
      for (final asset in [LiveStyle.backgroundAsset, LiveStyle.createAsset]) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('预约开播'));
    await tester.tap(find.text('预约开播'));
    await tester.pumpAndSettle();
    final picker = find.byType(CupertinoDatePicker);
    final state = tester.state(picker);
    final selected = tester
        .widget<CupertinoDatePicker>(picker)
        .initialDateTime
        .add(const Duration(hours: 1));
    tester.widget<CupertinoDatePicker>(picker).onDateTimeChanged(selected);
    for (final dark in [false, true, false]) {
      mode.value = dark ? ThemeMode.dark : ThemeMode.light;
      await tester.pumpAndSettle();
      _expectSurface(tester, dark: dark);
      expect(identical(tester.state(picker), state), isTrue);
      expect(CupertinoTheme.of(tester.element(picker)).brightness,
          dark ? Brightness.dark : Brightness.light);
    }
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text(DateFormat('yyyy-MM-dd HH:mm').format(selected)),
        findsOneWidget);
    expect(transport.requests.length, 1);
    expect(tester.takeException(), isNull);
  });
}
