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
      {Future<bool> Function(Uri)? open,
      void Function(bool)? finished,
      void Function()? onBlocking}) async {
    late BuildContext page;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      page = context;
      return const Scaffold(body: Text('Login'));
    })));
    await tester.runAsync(() =>
        precacheImage(const AssetImage('assets/images/renew.webp'), page));
    unawaited(checkPlatformUpdate(Navigator.of(page).context,
            automatic: true,
            fetchConfig: fetch,
            openURL: open,
            onBlocking: onBlocking)
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
      'failed automatic check finishes silently without blocking navigation',
      (tester) async {
    var attempts = 0;
    var blocked = false;
    bool? done;
    await start(tester, () async {
      attempts++;
      throw StateError('offline');
    }, finished: (value) => done = value, onBlocking: () => blocked = true);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(attempts, 3);
    expect(done, isFalse);
    expect(blocked, isFalse);
    expect(find.text('Update Check Unavailable'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Home')))));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);

    await start(tester, () async => policy(minimum: '1.0.0'),
        finished: (value) => done = value);
    expect(done, isTrue);
  });
}
