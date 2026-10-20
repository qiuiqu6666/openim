import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/theme/app_theme_data.dart';
import 'package:openim_common/openim_common.dart';

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'production loading and checkbox colors stay readable $brightness',
        (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          theme: buildAppThemeData(brightness),
          home: Builder(builder: (context) {
            theme = Theme.of(context);
            return Scaffold(
              body: Column(children: [
                const CircularProgressIndicator(),
                const LinearProgressIndicator(),
                Checkbox(value: true, onChanged: (_) {}),
              ]),
            );
          }),
        ),
      ));
      expect(_contrast(theme.progressIndicatorTheme.color!, theme.cardColor),
          greaterThanOrEqualTo(3));
      expect(theme.progressIndicatorTheme.color, AppTokens.accent);
      expect(
          theme.progressIndicatorTheme.linearTrackColor,
          AppTokens.accent
              .withValues(alpha: brightness == Brightness.dark ? .2 : .1));
      final selected = {WidgetState.selected};
      expect(
          _contrast(theme.checkboxTheme.checkColor!.resolve(selected)!,
              theme.checkboxTheme.fillColor!.resolve(selected)!),
          greaterThanOrEqualTo(4.5));
      if (brightness == Brightness.dark) {
        expect(theme.checkboxTheme.fillColor!.resolve({})!.computeLuminance(),
            lessThan(.1));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an open iOS confirmation follows the production theme',
      (tester) async {
    final mode = ValueNotifier(ThemeMode.light);
    addTearDown(mode.dispose);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (_, value, __) => MaterialApp(
          theme: buildAppThemeData(Brightness.light),
          darkTheme: buildAppThemeData(Brightness.dark),
          themeMode: value,
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => showCupertinoDialog<void>(
                        context: context,
                        builder: (_) => const CupertinoAlertDialog(
                          title: Text('Delete conversation'),
                          content: Text('Clear its messages?'),
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  )),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final state = tester.element(find.byType(CupertinoAlertDialog));
    expect(CupertinoTheme.of(state).brightness, Brightness.light);
    mode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(find.text('Clear its messages?'), findsOneWidget);
    expect(CupertinoTheme.of(state).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an existing default action follows the dark button foreground',
      (tester) async {
    final mode = ValueNotifier(ThemeMode.light);
    var taps = 0;
    addTearDown(() {
      Styles.isDark = false;
      mode.dispose();
    });
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (_, value, __) {
          Styles.isDark = value == ThemeMode.dark;
          return MaterialApp(
            theme: buildAppThemeData(Brightness.light),
            darkTheme: buildAppThemeData(Brightness.dark),
            themeMode: value,
            home: Scaffold(body: Button(text: 'Save', onTap: () => taps++)),
          );
        },
      ),
    ));
    expect(tester.widget<Text>(find.text('Save')).style!.color, Colors.white);
    mode.value = ThemeMode.dark;
    await tester.pumpAndSettle();
    final label = tester.widget<Text>(find.text('Save'));
    final ink = tester.widget<Ink>(
        find.descendant(of: find.byType(Button), matching: find.byType(Ink)));
    final fill = (ink.decoration! as BoxDecoration).color!;
    expect(_contrast(label.style!.color!, fill), greaterThanOrEqualTo(4.5));
    await tester.tap(find.text('Save'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
