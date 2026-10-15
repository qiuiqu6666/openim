import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openim/main.dart' as app;
import 'package:openim/pages/mine/settings/pages/feedback_page.dart';
import 'package:openim/pages/mine/settings/settings_home_page.dart';
import 'package:openim/theme/app_theme_controller.dart';

import 'ux_frame_metrics.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('retained tabs, themes, keyboard and feedback leave protection',
      (tester) async {
    final handler = FlutterError.onError;
    app.main();
    FlutterError.onError = handler;
    Future<void> waitFor(Finder finder, {int attempts = 100}) async {
      for (var i = 0; i < attempts && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(finder, findsWidgets, reason: 'Existing logged-in app required.');
    }

    await waitFor(find.byType(BottomNavigationBar), attempts: 600);
    await tester.pump(const Duration(seconds: 2));
    final originalTheme = AppThemeController.instance.mode;
    Future<void> tab(int index) async {
      final nav = tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar).last);
      final label = find.descendant(
          of: find.byType(BottomNavigationBar).last,
          matching: find.text(nav.items[index].label!));
      await tester.tap(label.last);
      await tester.pump(const Duration(milliseconds: 700));
    }

    try {
      final timings = await measureUxFrames(() async {
        for (var round = 0; round < 3; round++) {
          for (final index in [2, 4, 0, 4]) {
            await tab(index);
          }
        }
      }, () => tester.pump(const Duration(seconds: 1)));
      expect(timings['frame_count'], greaterThan(0));
      binding.reportData ??= {};
      binding.reportData!['tab_frame_timings'] = timings;
      await binding.convertFlutterSurfaceToImage();
      for (final dark in [false, true]) {
        await AppThemeController.instance
            .setMode(dark ? ThemeMode.dark : ThemeMode.light);
        await tester.pump(const Duration(seconds: 4));
        await binding.takeScreenshot('mine-${dark ? 'dark' : 'light'}');
        await tester.tap(find.byKey(const ValueKey('mine-top-settings')));
        await waitFor(find.byType(SettingsHomePage));
        await tester.pump(const Duration(milliseconds: 700));
        await binding.takeScreenshot('settings-${dark ? 'dark' : 'light'}');
        final feedback = find.text('意见反馈');
        await tester.ensureVisible(feedback);
        await tester.tap(feedback);
        await waitFor(find.byType(FeedbackPage));
        await tester.pump(const Duration(milliseconds: 700));
        await tester.tap(find.byType(TextField).first);
        await tester.pump(const Duration(milliseconds: 700));
        // The host types through Android's real input connection. TestTextInput
        // can be overwritten by the platform IME in a profile application.
        await binding
            .takeScreenshot('feedback-input-ready-${dark ? 'dark' : 'light'}');
        debugPrint('UX_AUDIT_INPUT_READY:${dark ? 'dark' : 'light'}');
        for (var i = 0;
            i < 100 &&
                tester
                        .widget<TextField>(find.byType(TextField).first)
                        .controller!
                        .text !=
                    'UX draft keep';
            i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final context = tester.element(find.byType(TextField).first);
        expect(
            tester
                .widget<TextField>(find.byType(TextField).first)
                .controller!
                .text,
            'UX draft keep');
        expect(ModalRoute.of(context)!.popDisposition,
            RoutePopDisposition.doNotPop);
        await binding
            .takeScreenshot('feedback-editing-${dark ? 'dark' : 'light'}');
        await Navigator.of(context).maybePop();
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.text('放弃未保存的内容？'), findsOneWidget);
        await binding
            .takeScreenshot('feedback-guard-${dark ? 'dark' : 'light'}');
        await tester.tap(find.text('继续编辑'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('UX draft keep'), findsOneWidget);
        await Navigator.of(context).maybePop();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('放弃修改'));
        await tester.pump(const Duration(milliseconds: 700));
        await Navigator.of(tester.element(find.byType(SettingsHomePage)))
            .maybePop();
        await tester.pump(const Duration(milliseconds: 700));
      }
      await tester.pump(const Duration(seconds: 4));
      binding.reportData ??= {};
      binding.reportData!['idle_transient_callbacks'] =
          SchedulerBinding.instance.transientCallbackCount;
      binding.reportData!['system_text_scale_at_16'] = MediaQuery.textScalerOf(
              tester.element(find.byType(BottomNavigationBar).last))
          .scale(16);
      binding.reportData!['completed'] = true;
      expect(tester.takeException(), isNull);
    } finally {
      await AppThemeController.instance.setMode(originalTheme);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
