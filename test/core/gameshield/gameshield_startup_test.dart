import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/gameshield/startup/gameshield_startup_failure_app.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('protected initialization failure does not run the normal app callback',
      () async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    var launched = false, failed = false;
    await Config.init(() {
      launched = true;
    }, prepareNetwork: () async {
      throw StateError('network unavailable');
    }, onInitError: (_) {
      failed = true;
    });
    expect(failed, isTrue);
    expect(launched, isFalse);
  });
  for (final dark in [false, true]) {
    testWidgets('failure retry remains usable on narrow screen dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.platformBrightnessTestValue =
          dark ? Brightness.dark : Brightness.light;
      tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final gate = Completer<void>();
      var retries = 0;
      await tester.pumpWidget(GameShieldStartupFailureApp(onRetry: () async {
        retries++;
        await gate.future;
      }));
      await tester.pumpAndSettle();
      expect(find.text('暂时无法连接'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(find.text('连接中…'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      expect(retries, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
