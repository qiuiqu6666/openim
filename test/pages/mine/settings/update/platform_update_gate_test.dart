import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/services/platform_config_service.dart';
import 'package:openim/pages/mine/settings/widgets/platform_update.dart';

PlatformConfig policy({String minimum = '9.0.0', String url = ''}) =>
    PlatformConfig({
      for (final os in ['android', 'ios'])
        os: {
          'minVersion': minimum,
          'latestVersion': minimum,
          'downloadLink': url,
        }
    });

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'app',
        packageName: 'app',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
  });
  Future<void> start(
      WidgetTester tester, Future<PlatformConfig> Function() fetch,
      {Future<bool> Function(Uri)? open, void Function(bool)? finished}) async {
    late BuildContext page;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      page = context;
      return const Scaffold(body: Text('Login'));
    })));
    await tester.runAsync(() =>
        precacheImage(const AssetImage('assets/images/renew.webp'), page));
    unawaited(checkPlatformUpdate(Navigator.of(page).context,
            automatic: true, fetchConfig: fetch, openURL: open)
        .then((value) => finished?.call(value)));
    await tester.pumpAndSettle();
  }

  testWidgets('late mandatory result covers home after login route replacement',
      (tester) async {
    final response = Completer<PlatformConfig>();
    await start(tester, () => response.future);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.pushReplacement(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Home')))));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    response.complete(policy());
    await tester.pumpAndSettle();
    expect(find.text('Retry Update'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Retry Update'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mandatory missing link blocks and can fetch a repaired link',
      (tester) async {
    var repaired = false;
    Uri? opened;
    await start(tester,
        () async => policy(url: repaired ? 'https://example.com/app.apk' : ''),
        open: (uri) async {
      opened = uri;
      return true;
    });
    expect(find.text('Retry Update'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Retry Update'), findsOneWidget);
    repaired = true;
    await tester.tap(find.text('Retry Update'));
    await tester.pumpAndSettle();
    expect(opened.toString(), 'https://example.com/app.apk');
    expect(find.text('Retry Update'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'failed check retries automatically then stays blocked until recovery',
      (tester) async {
    var attempts = 0;
    var online = false;
    bool? done;
    await start(tester, () async {
      attempts++;
      if (!online) throw StateError('offline');
      return policy(minimum: '1.0.0');
    }, finished: (value) => done = value);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(attempts, 3);
    expect(done, isNull);
    expect(find.text('Retry'), findsOneWidget);
    online = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(find.text('Retry'), findsNothing);
  });
}
