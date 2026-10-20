import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/language_setup/language_setup_logic.dart';
import 'package:openim/pages/mine/language_setup/language_setup_view.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  test('system Chinese script and region resolve to supported translations',
      () {
    for (final region in ['TW', 'HK', 'MO']) {
      expect(TranslationService.localeForSetting(0, Locale('zh', region)),
          const Locale('zh', 'TW'));
    }
    expect(
        TranslationService.resolveLocale(
            const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
        const Locale('zh', 'TW'));
    expect(
        TranslationService.resolveLocale(const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hans', countryCode: 'HK')),
        const Locale('zh', 'CN'));
    expect(TranslationService.localeForSetting(1, const Locale('zh', 'TW')),
        const Locale('zh', 'CN'));
    expect(TranslationService.localeForSetting(2, const Locale('zh', 'TW')),
        const Locale('en', 'US'));
    expect(TranslationService.localeForSetting(3, const Locale('en', 'US')),
        const Locale('zh', 'TW'));
  });

  test('traditional resources retain all keys and interpolation placeholders',
      () {
    final maps = TranslationService().keys;
    final simplified = maps['zh_CN']!;
    final traditional = maps['zh_TW']!;
    expect(traditional.keys.toSet(), simplified.keys.toSet());
    final placeholder = RegExp(r'@[a-zA-Z_]\w*');
    for (final key in simplified.keys) {
      expect(
        placeholder
            .allMatches(traditional[key]!)
            .map((m) => m.group(0))
            .toList(),
        placeholder
            .allMatches(simplified[key]!)
            .map((m) => m.group(0))
            .toList(),
        reason: key,
      );
    }
    expect(traditional['languageSetup'], '語言設定');
  });

  for (final brightness in Brightness.values) {
    testWidgets('selection persists and large text fits in $brightness',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await DataSp.init();
      await DataSp.putLanguage(1);
      final logic = Get.put(LanguageSetupLogic());
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('zh', 'TW'),
            Locale('en', 'US'),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: LanguageSetupPage(),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('繁體中文'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(Get.locale, const Locale('zh', 'TW'));
      expect(DataSp.getLanguage(), 3);
      expect(logic.selectedLanguage.value, 3);
      expect(find.text('語言設定'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final restored = LanguageSetupLogic()..onInit();
      expect(restored.selectedLanguage.value, 3);
      restored.onClose();
      await tester.scrollUntilVisible(find.text('English'), 100);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('English'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(Get.locale, const Locale('en', 'US'));
      expect(DataSp.getLanguage(), 2);
      expect(tester.takeException(), isNull);
    });
  }
}
