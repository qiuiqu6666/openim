import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_openim_sdk/src/logger.dart' as sdk_log;
import 'package:openim/pages/mine/settings/diagnostics/diagnostic_logging_controller.dart';
import 'package:openim/pages/mine/settings/diagnostics/diagnostic_logging_page.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('diagnostic text removes SDK branding and retains error context', () {
    final cleaned = sdk_log.Logger.clean(
        'OpenIM open-im-sdk-core open_im_sdk/caller.go:42 code=1001 op=abc');
    expect(cleaned.toLowerCase(), isNot(contains('openim')));
    expect(cleaned, isNot(contains('open-im')));
    expect(cleaned, isNot(contains('open_im')));
    expect(cleaned, contains('caller.go:42 code=1001 op=abc'));
  });
  test('native bridge uses real manager and rejects missing state', () async {
    const channel = MethodChannel('diagnostic-test');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'setDiagnosticLogging'
          ? call.arguments['seconds']
          : 123;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final manager = DiagnosticLoggingManager(channel);
    expect(await manager.setDuration(10000), 900);
    expect(
        calls.single.arguments, {'ManagerName': 'imManager', 'seconds': 900});
    expect(await manager.remainingSeconds(), 123);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(manager.remainingSeconds(), throwsFormatException);
  });

  test('failed changes preserve state, serialize requests and ignore disposal',
      () async {
    final pending = Completer<int>();
    var calls = 0;
    final controller = DiagnosticLoggingController(
      read: () async => 0,
      write: (_) {
        calls++;
        return pending.future;
      },
    );
    await controller.refresh();
    final operation = controller.setEnabled(true);
    await controller.setEnabled(true);
    expect(calls, 1);
    expect(controller.remaining, 0);
    pending.completeError(StateError('native unavailable'));
    await operation;
    expect(controller.failed, true);
    expect(controller.remaining, 0);
    await controller.refresh();
    expect(controller.failed, false);
    controller.dispose();
    await controller.refresh();
  });

  for (final dark in [false, true]) {
    testWidgets('toggle, native expiry and accessible layout dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var native = 0;
      final writes = <int>[];
      final controller = DiagnosticLoggingController(
        read: () async => native,
        write: (value) async {
          writes.add(value);
          return native = value;
        },
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: DiagnosticLoggingPage(controller: controller),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Compact mode'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
      await tester.tap(find.byType(SettingsPlatformSwitch));
      await tester.pumpAndSettle();
      expect(writes, [600]);
      expect(find.textContaining('10 min remaining'), findsOneWidget);
      native = 0;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Compact mode'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(SettingsPlatformSwitch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SettingsPlatformSwitch));
      await tester.pumpAndSettle();
      expect(writes, [600, 600, 0]);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('unsupported SDK shows retry and never pretends enabled',
      (tester) async {
    var fails = true;
    final controller = DiagnosticLoggingController(
      read: () async {
        if (fails) throw MissingPluginException();
        return 0;
      },
      write: (_) async => 600,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
        MaterialApp(home: DiagnosticLoggingPage(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.text('Status unavailable'), findsOneWidget);
    expect(
        tester
            .widget<SettingsSwitchCell>(find.byType(SettingsSwitchCell))
            .enabled,
        false);
    fails = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Compact mode'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('background suspends refresh and foreground checks native again',
      (tester) async {
    var reads = 0;
    var native = 600;
    final controller = DiagnosticLoggingController(
        read: () async {
          reads++;
          return native;
        },
        write: (v) async => v);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
        MaterialApp(home: DiagnosticLoggingPage(controller: controller)));
    await tester.pumpAndSettle();
    controller.setActive(false);
    await tester.pump(const Duration(seconds: 20));
    expect(reads, 1);
    native = 0;
    controller.setActive(true);
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(controller.remaining, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
