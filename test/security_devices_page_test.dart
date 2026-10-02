import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim/pages/mine/settings/pages/login_devices_page.dart';

class _Devices extends StubSettingsService {
  Completer<List<Map<String, dynamic>>> pending = Completer();
  @override
  Future<List<Map<String, dynamic>>> getLoginRecords() => pending.future;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('login device loading, error and retry in $brightness',
        (tester) async {
      final service = _Devices();
      await tester.pumpWidget(GetMaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(brightness: brightness),
          home: LoginDevicesPage(service: service)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      service.pending.completeError(StateError('Offline'));
      await tester.pumpAndSettle();
      expect(find.text('加载失败，点击重试'), findsOneWidget);
      service.pending = Completer();
      await tester.tap(find.text('加载失败，点击重试'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      service.pending.complete([
        {
          'deviceName': 'My Phone',
          'platform': 'Android',
          'version': '1.2.3',
          'ip': '127.0.0.1',
          'loginTime': 1790849179579
        }
      ]);
      await tester.pumpAndSettle();
      expect(find.text('My Phone'), findsOneWidget);
      expect(find.textContaining('127.0.0.1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      Get.reset();
    });
  }
}
