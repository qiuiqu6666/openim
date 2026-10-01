import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/theme/app_theme_controller.dart';
import 'package:openim/widgets/theme_aware_page.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('theme choice persists and system mode follows brightness',
      (tester) async {
    SharedPreferences.setMockInitialValues({'appThemeMode': 'dark'});
    await SpUtil().init();
    final controller = AppThemeController.instance;
    controller.load();
    expect(controller.mode, ThemeMode.dark);
    expect(Styles.isDark, isTrue);
    expect(Styles.c_FFFFFF, const Color(0xFF202A36));

    await controller.setMode(ThemeMode.light);
    expect(SpUtil().getString('appThemeMode'), 'light');
    expect(Styles.isDark, isFalse);

    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await controller.setMode(ThemeMode.system);
    expect(Styles.isDark, isTrue);
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pump();
    expect(Styles.isDark, isFalse);
    tester.binding.platformDispatcher.clearPlatformBrightnessTestValue();
  });

  testWidgets('an open page refreshes its shared colors on theme change',
      (tester) async {
    final mode = ValueNotifier(ThemeMode.light);
    addTearDown(() {
      Styles.isDark = false;
      mode.dispose();
    });

    await tester.pumpWidget(ValueListenableBuilder<ThemeMode>(
      valueListenable: mode,
      builder: (_, value, __) {
        Styles.isDark = value == ThemeMode.dark;
        return MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: value,
          home: ThemeAwarePage(
            builder: (_) => Scaffold(
              body: Text('sample', style: TextStyle(color: Styles.c_0C1C33)),
            ),
          ),
        );
      },
    ));
    expect(tester.widget<Text>(find.text('sample')).style!.color,
        const Color(0xFF0C1C33));

    mode.value = ThemeMode.dark;
    await tester.pump();
    expect(tester.widget<Text>(find.text('sample')).style!.color,
        const Color(0xFFE8EDF5));
  });
}
