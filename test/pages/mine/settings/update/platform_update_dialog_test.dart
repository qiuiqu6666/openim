import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/update/platform_update_dialog.dart';
import 'package:openim_common/openim_common.dart';

const _title = '发现新版本 3.8.3+236';
const _message = '当前版本低于最低支持版本，请更新应用。';

Future<void> _openDialog(
  WidgetTester tester, {
  required bool force,
  required Future<void> Function() onUpdate,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh', 'CN'),
  Size size = const Size(375, 812),
  double textScale = 1,
  String title = _title,
  String message = _message,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final previousDark = Styles.isDark;
  Styles.isDark = brightness == Brightness.dark;
  addTearDown(() => Styles.isDark = previousDark);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: brightness),
    locale: locale,
    supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => unawaited(showPlatformUpdateDialog(
            context,
            title: title,
            message: message,
            force: force,
            onUpdate: onUpdate,
          )),
          child: const Text('Open update'),
        ),
      ),
    ),
  ));
  addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
  await tester.runAsync(() async {
    final artwork = await rootBundle.load('assets/images/renew.webp');
    expect(artwork.lengthInBytes, greaterThan(0));
    await precacheImage(const AssetImage('assets/images/renew.webp'),
        tester.element(find.byType(Scaffold)));
  });
  await tester.tap(find.text('Open update'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('same navigator reuses the update already shown', (tester) async {
    var originalUpdates = 0;
    var duplicateUpdates = 0;
    await _openDialog(tester,
        force: false, onUpdate: () async => originalUpdates++);

    final context = tester.element(find.text('Open update'));
    unawaited(showPlatformUpdateDialog(context,
        title: 'Duplicate update',
        message: 'This must not cover the active update.',
        force: true,
        onUpdate: () async => duplicateUpdates++));
    await tester.pumpAndSettle();

    expect(find.text(_title), findsOneWidget);
    expect(find.text('Duplicate update'), findsNothing);
    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();
    expect(originalUpdates, 1);
    expect(duplicateUpdates, 0);
    expect(find.text(_title), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('optional update can be closed without opening the download',
      (tester) async {
    var updates = 0;
    await _openDialog(tester, force: false, onUpdate: () async => updates++);

    expect(find.text(_title), findsOneWidget);
    expect(find.text(_message), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.image(const AssetImage('assets/images/renew.webp')),
        findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    expect(find.text(_title), findsNothing);
    expect(updates, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('force update ignores system back and outside taps',
      (tester) async {
    await _openDialog(tester, force: true, onUpdate: () async {});
    expect(find.byTooltip('关闭'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_title), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text(_title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final force in [false, true]) {
    testWidgets('successful update respects force=$force dismissal',
        (tester) async {
      var updates = 0;
      await _openDialog(tester, force: force, onUpdate: () async => updates++);

      await tester.tap(find.text('立即更新'));
      await tester.pumpAndSettle();

      expect(updates, 1);
      expect(find.text(_title), force ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('download failure stays visible and permits a retry',
      (tester) async {
    var attempts = 0;
    await _openDialog(tester, force: false, onUpdate: () async {
      attempts++;
      if (attempts == 1) throw StateError('download launch failed');
    });

    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();
    expect(find.text(_title), findsOneWidget);
    expect(find.text('无法打开下载页面，请稍后重试'), findsOneWidget);
    expect(attempts, 1);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('立即更新'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text(_title), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending download prevents duplicate requests', (tester) async {
    var attempts = 0;
    final pending = Completer<void>();
    await _openDialog(tester, force: false, onUpdate: () {
      attempts++;
      return pending.future;
    });

    final updateCenter = tester.getCenter(find.text('立即更新'));
    await tester.tapAt(updateCenter);
    await tester.pump();
    await tester.tapAt(updateCenter);
    await tester.pump();
    expect(attempts, 1);
    expect(find.text(_title), findsOneWidget);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text(_title), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English locale uses a localized update and close action',
      (tester) async {
    await _openDialog(tester,
        force: false,
        locale: const Locale('en', 'US'),
        title: 'New version 3.8.3+236',
        message: 'Please update to a supported version.',
        onUpdate: () async {});

    expect(find.text('Update Now'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.text('立即更新'), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('New version 3.8.3+236'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('long update text fits narrow large-text $brightness layout',
        (tester) async {
      final longMessage =
          List.filled(15, '本次更新优化聊天体验、连接稳定性和界面显示，请更新后继续使用。').join('\n');
      await _openDialog(tester,
          force: true,
          brightness: brightness,
          size: const Size(320, 568),
          textScale: 1.5,
          title: '发现新版本 3.8.3+236（包含聊天与界面更新）',
          message: longMessage,
          onUpdate: () async {});

      expect(find.text(longMessage), findsOneWidget);
      expect(find.text('立即更新').hitTestable(), findsOneWidget);
      final actionRect = tester.getRect(find.text('立即更新'));
      expect(actionRect.left, greaterThanOrEqualTo(0));
      expect(actionRect.right, lessThanOrEqualTo(320));
      expect(actionRect.top, greaterThanOrEqualTo(0));
      expect(actionRect.bottom, lessThanOrEqualTo(568));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('立即更新'));
      await tester.pumpAndSettle();
      expect(find.text('立即更新'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
