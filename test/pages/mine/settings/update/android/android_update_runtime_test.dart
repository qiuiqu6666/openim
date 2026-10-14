import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/mine/settings/update/android/android_update_controller.dart';
import 'package:openim/pages/mine/settings/update/android/android_update_runtime.dart';
import 'android_update_controller_test.dart' show FakePlatform, release;
import 'package:openim/services/platform_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'legacy required prompt stays after website return and back; actual upgrade releases it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var installed = '3.0.1+1';
    var offline = false;
    var opens = 0;
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const Scaffold(body: Text('Home'));
    })));
    await tester.runAsync(() =>
        precacheImage(const AssetImage('assets/images/renew.webp'), context));
    final c = AndroidUpdateController(
        platform: FakePlatform(),
        fetch: () async {
          if (offline) throw StateError('offline');
          return PlatformConfig({
            'android': {
              'minVersion': '3.0.1+2',
              'latestVersion': '3.0.1+3',
              'downloadURL': 'https://example.com'
            }
          });
        },
        installedVersion: () async => installed,
        bucket: 99);
    final runtime = AndroidUpdateRuntime.test(
        coordinator: c,
        preferences: prefs,
        foreground: () => true,
        calling: () => false,
        context: () => context,
        openURL: (_) async {
          opens++;
          return true;
        });
    await runtime.start();
    await tester.runAsync(() => c.tick());
    await tester.pumpAndSettle();
    expect(find.text('Update Now'), findsOneWidget);
    expect(runtime.blocksNavigation, true);
    await tester.tap(find.text('Update Now'));
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(runtime.blocksNavigation, true);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Update Now'), findsOneWidget);
    offline = true;
    await c.tick(refresh: true);
    await tester.pumpAndSettle();
    expect(runtime.blocksNavigation, true);
    offline = false;
    installed = '3.0.1+3';
    await c.tick(refresh: true);
    await tester.pumpAndSettle();
    expect(find.text('Update Now'), findsNothing);
    expect(runtime.blocksNavigation, false);
    runtime.dispose();
  });
  test('network restoration automatically retries in background without a tap',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final changes = StreamController<List<ConnectivityResult>>(sync: true);
    final native = FakePlatform();
    var offline = true;
    var requests = 0;
    final coordinator = AndroidUpdateController(
        platform: native,
        fetch: () async {
          requests++;
          if (offline) throw StateError('network unavailable');
          return release();
        },
        installedVersion: () async => '3.0.1+1',
        bucket: 0);
    final runtime = AndroidUpdateRuntime.test(
        coordinator: coordinator,
        preferences: preferences,
        foreground: () => false,
        calling: () => false,
        context: () => null,
        networkChanges: changes.stream);
    await runtime.start();
    expect(coordinator.phase, AndroidUpdatePhase.retry);
    expect(requests, 1);
    changes.add([ConnectivityResult.none]);
    offline = false;
    changes.add([ConnectivityResult.wifi]);
    await coordinator.tick();
    expect(requests, 2);
    expect(coordinator.phase, AndroidUpdatePhase.downloading);
    expect(native.downloads, 1);
    expect(runtime.blocksNavigation, false);
    changes.add([ConnectivityResult.wifi]);
    await coordinator.tick();
    expect(requests, 2);
    runtime.dispose();
    expect(changes.hasListener, false);
    await changes.close();
  });

  test('restored network failure returns to backoff instead of retry storm',
      () async {
    SharedPreferences.setMockInitialValues({});
    final changes = StreamController<List<ConnectivityResult>>(sync: true);
    var requests = 0;
    final coordinator = AndroidUpdateController(
        platform: FakePlatform(),
        fetch: () async {
          requests++;
          throw StateError('server still unavailable');
        },
        installedVersion: () async => '3.0.1+1',
        bucket: 0);
    final runtime = AndroidUpdateRuntime.test(
        coordinator: coordinator,
        preferences: await SharedPreferences.getInstance(),
        foreground: () => false,
        calling: () => false,
        context: () => null,
        networkChanges: changes.stream);
    await runtime.start();
    changes.add([ConnectivityResult.wifi]);
    await coordinator.tick();
    expect(requests, 2);
    changes.add([ConnectivityResult.wifi]);
    changes.add([ConnectivityResult.wifi]);
    await coordinator.tick();
    expect(requests, 2);
    expect(coordinator.phase, AndroidUpdatePhase.retry);
    runtime.dispose();
    await changes.close();
  });
  testWidgets('cached ready APK is rechecked before foreground prompt',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final native = FakePlatform();
    var config = release();
    var foreground = false;
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const Scaffold(body: Text('Home'));
    })));
    final c = AndroidUpdateController(
        platform: native,
        fetch: () async => config,
        installedVersion: () async => '3.0.1+1',
        bucket: 0);
    final runtime = AndroidUpdateRuntime.test(
        coordinator: c,
        preferences: prefs,
        foreground: () => foreground,
        calling: () => false,
        context: () => context);
    await runtime.start();
    native.state = 'complete';
    await runtime.start();
    expect(c.ready, true);
    config = release(minimum: '', ratio: 0);
    foreground = true;
    await runtime.start();
    expect(runtime.blocksNavigation, false);
    await tester.runAsync(() => c.tick());
    await tester.pumpAndSettle();
    expect(find.text('Install Now'), findsNothing);
    expect(c.ready, false);
    runtime.dispose();
  });
  testWidgets(
      'background/call defer prompt; foreground shows only verified APK; withdrawal unlocks',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final native = FakePlatform();
    var config = release();
    var foreground = false, calling = false;
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const Scaffold(body: Text('Chat remains usable'));
    })));
    await tester.runAsync(() =>
        precacheImage(const AssetImage('assets/images/renew.webp'), context));
    final c = AndroidUpdateController(
        platform: native,
        fetch: () async => config,
        installedVersion: () async => '3.0.1+1',
        bucket: 0);
    final runtime = AndroidUpdateRuntime.test(
        coordinator: c,
        preferences: prefs,
        foreground: () => foreground,
        calling: () => calling,
        context: () => context);
    await runtime.start();
    expect(runtime.blocksNavigation, false);
    native.state = 'complete';
    await runtime.start();
    await tester.pumpAndSettle();
    expect(c.ready, true);
    expect(find.text('Install Now'), findsNothing);
    foreground = true;
    calling = true;
    await runtime.start();
    await tester.pumpAndSettle();
    expect(runtime.blocksNavigation, false);
    expect(find.text('Install Now'), findsNothing);
    calling = false;
    await runtime.start();
    await tester.runAsync(() => c.tick());
    await tester.pumpAndSettle();
    expect(runtime.blocksNavigation, true);
    expect(find.text('Install Now'), findsOneWidget);
    config = release(minimum: '', ratio: 0);
    await c.tick(refresh: true);
    await tester.pumpAndSettle();
    expect(runtime.blocksNavigation, false);
    expect(find.text('Install Now'), findsNothing);
    expect(find.text('Chat remains usable'), findsOneWidget);
    runtime.dispose();
  });

  testWidgets(
      'optional dismissal snoozes across runtime recreation but never suppresses force',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final native = FakePlatform();
    var config = release(minimum: '');
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const Scaffold(body: Text('Home'));
    })));
    await tester.runAsync(() =>
        precacheImage(const AssetImage('assets/images/renew.webp'), context));
    AndroidUpdateRuntime make() => AndroidUpdateRuntime.test(
        coordinator: AndroidUpdateController(
            platform: native,
            fetch: () async => config,
            installedVersion: () async => '3.0.1+1',
            bucket: 0),
        preferences: prefs,
        foreground: () => true,
        calling: () => false,
        context: () => context);
    var runtime = make();
    await runtime.start();
    native.state = 'complete';
    await runtime.start();
    await tester.runAsync(() => runtime.controller!.tick());
    await tester.pumpAndSettle();
    expect(runtime.blocksNavigation, false);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    runtime.dispose();
    runtime = make();
    await runtime.start();
    await tester.pumpAndSettle();
    expect(find.text('Install Now'), findsNothing);
    config = release();
    await runtime.controller!.tick(refresh: true);
    await tester.runAsync(() => runtime.controller!.tick());
    await tester.pumpAndSettle();
    expect(find.text('Install Now'), findsOneWidget);
    expect(runtime.blocksNavigation, true);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    runtime.dispose();
  });
}
