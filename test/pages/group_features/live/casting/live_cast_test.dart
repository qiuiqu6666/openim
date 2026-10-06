import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/live/casting/live_cast_button.dart';
import 'package:openim/pages/group_features/live/casting/live_cast_service.dart';
import 'package:openim/pages/group_features/live/widgets/live_style.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('openim_group_live_cast');
  const service = LiveCastService();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  test('opens the system picker without passing playback credentials',
      () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    await service.openSystemPicker(platform: TargetPlatform.android);
    expect(calls.single.method, 'openCastSettings');
    expect(calls.single.arguments, isNull);
  });

  for (final reply in [false, null, 'invalid']) {
    test('a native reply of $reply does not report success', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => reply);
      await expectLater(
        service.openSystemPicker(platform: TargetPlatform.android),
        throwsA(isA<LiveCastFailure>()
            .having((error) => error.message, 'message', contains('无法打开投屏设置'))),
      );
    });
  }

  for (final error in [
    MissingPluginException(),
    PlatformException(code: 'activity_unavailable'),
  ]) {
    test('native $error becomes an actionable failure', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => throw error);
      await expectLater(
        service.openSystemPicker(platform: TargetPlatform.android),
        throwsA(isA<LiveCastFailure>()),
      );
    });
  }

  test('unsupported platforms do not invoke a mobile bridge', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      called = true;
      return true;
    });
    await expectLater(
      service.openSystemPicker(platform: TargetPlatform.windows),
      throwsA(isA<LiveCastFailure>()),
    );
    expect(called, isFalse);
  });

  for (final brightness in Brightness.values) {
    testWidgets('$brightness has a readable 48px cast control', (tester) async {
      messenger.setMockMethodCallHandler(channel, (_) async => true);
      final errors = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: ColoredBox(
            color: LiveStyle.screen,
            child: LiveCastButton(
              platform: TargetPlatform.android,
              onError: errors.add,
            ),
          ),
        ),
      ));
      final button = find.byTooltip('投屏');
      expect(tester.getSize(button), const Size(48, 48));
      expect(tester.widget<IconButton>(find.byType(IconButton)).color,
          LiveStyle.screenInk);
      await tester.tap(button);
      await tester.pump();
      expect(errors, isEmpty);
    });
  }

  testWidgets('reports failure once and permits retry', (tester) async {
    final errors = <String>[];
    var attempts = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      attempts++;
      return false;
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LiveCastButton(
          platform: TargetPlatform.android,
          onError: errors.add,
        ),
      ),
    ));
    await tester.tap(find.byTooltip('投屏'));
    await tester.pump();
    expect(errors.single, contains('系统控制中心'));
    expect(attempts, 1);
    await tester.tap(find.byTooltip('投屏'));
    await tester.pump();
    expect(errors, hasLength(2));
    expect(attempts, 2);
  });

  testWidgets('rapid taps open only one picker', (tester) async {
    final opened = Completer<bool>();
    var attempts = 0;
    messenger.setMockMethodCallHandler(channel, (_) {
      attempts++;
      return opened.future;
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: LiveCastButton(platform: TargetPlatform.android)),
    ));
    await tester.tap(find.byTooltip('投屏'));
    await tester.tap(find.byTooltip('投屏'));
    await tester.pump();
    expect(attempts, 1);
    expect(find.byTooltip('正在打开投屏设置'), findsOneWidget);
    opened.complete(true);
    await tester.pump();
    expect(find.byTooltip('投屏'), findsOneWidget);
  });

  testWidgets('late bridge failure cannot show a toast after closing the view',
      (tester) async {
    final opened = Completer<bool>();
    final errors = <String>[];
    messenger.setMockMethodCallHandler(channel, (_) => opened.future);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LiveCastButton(
          platform: TargetPlatform.android,
          onError: errors.add,
        ),
      ),
    ));
    await tester.tap(find.byTooltip('投屏'));
    await tester.pumpWidget(const SizedBox.shrink());
    opened.complete(false);
    await tester.pump();
    expect(errors, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop omits an unavailable cast entry', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: LiveCastButton(platform: TargetPlatform.windows)),
    ));
    expect(find.byTooltip('投屏'), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('iOS creates a native AirPlay picker with theme colors only',
      (tester) async {
    final creates = <Map<dynamic, dynamic>>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') creates.add(call.arguments as Map);
      return null;
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: LiveCastButton(platform: TargetPlatform.iOS)),
    ));
    await tester.pump();
    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, 'openim_group_live_airplay_picker');
    expect(view.creationParams, {
      'tint': LiveStyle.screenInk.toARGB32(),
      'activeTint': AppTokens.accent.toARGB32(),
    });
    expect(creates.single['viewType'], view.viewType);
    expect(tester.getSize(find.byTooltip('投屏')), const Size(48, 48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS native picker updates when its foreground changes',
      (tester) async {
    final creates = <Map<dynamic, dynamic>>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') creates.add(call.arguments as Map);
      return null;
    });
    Widget shell(Color color) => MaterialApp(
          home: Scaffold(
            body: LiveCastButton(
              platform: TargetPlatform.iOS,
              foregroundColor: color,
            ),
          ),
        );
    await tester.pumpWidget(shell(AppTokens.textPrimaryLight));
    await tester.pump();
    await tester.pumpWidget(shell(AppTokens.textPrimaryDark));
    await tester.pump();
    final picker = tester.widget<UiKitView>(find.byType(UiKitView));
    expect((picker.creationParams as Map)['tint'],
        AppTokens.textPrimaryDark.toARGB32());
    expect(creates, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
