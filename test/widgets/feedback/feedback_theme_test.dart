import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

void main() {
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });

  for (final dark in [false, true]) {
    testWidgets('production toast remains readable dark=$dark', (tester) async {
      Styles.isDark = dark;
      configureEasyLoadingInteractions();
      configureEasyLoadingAppearance();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: EasyLoading.init(),
        home: const Scaffold(body: Text('Page')),
      ));
      final shown = IMViews.showToast('Saved successfully');
      await tester.pump();
      await tester.pumpAndSettle();
      await shown;
      final text = tester.widget<Text>(find.text('Saved successfully'));
      expect(
          _contrast(text.style!.color!, EasyLoading.instance.backgroundColor!),
          greaterThanOrEqualTo(4.5));
      final dismissed = EasyLoading.dismiss();
      await tester.pumpAndSettle();
      await dismissed;
    });
  }

  testWidgets('progress overlay stays readable when an open page changes theme',
      (tester) async {
    final mode = ValueNotifier(ThemeMode.light);
    final progress = Stream<double>.value(.5);
    addTearDown(mode.dispose);
    await tester.pumpWidget(ValueListenableBuilder<ThemeMode>(
      valueListenable: mode,
      builder: (_, value, __) {
        Styles.isDark = value == ThemeMode.dark;
        return GetMaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: value,
          home: const Scaffold(body: Text('Page')),
        );
      },
    ));
    LoadingView().progress(progress);
    await tester.pump();
    await tester.pump();
    final originalText = tester.widget<Text>(find.text('50.0%'));
    expect(_contrast(originalText.style!.color!, FeedbackColors.background),
        greaterThanOrEqualTo(4.5));
    mode.value = ThemeMode.dark;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final indicator = tester.widget<CupertinoActivityIndicator>(
        find.byType(CupertinoActivityIndicator));
    expect(_contrast(indicator.color!, FeedbackColors.background),
        greaterThanOrEqualTo(3));
    expect(find.text('50.0%'), findsOneWidget);
    await LoadingView().dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
