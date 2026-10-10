import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/entry/wallet_entry_coordinator.dart';
import 'package:openim/pages/wallet/wallet_screen.dart';
import 'package:openim/pages/wallet/wallet_tab_shell.dart';

import 'support/wallet_entry_fixture.dart';

const _directory = String.fromEnvironment('WALLET_ENTRY_PREVIEW_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_directory.isEmpty) return;
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      await (FontLoader('WalletEntryPreview')
            ..addFont(
                Future.value(ByteData.sublistView(await font.readAsBytes()))))
          .load();
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final brightness in Brightness.values) {
      for (final narrow in [false, true]) {
        testWidgets(
            'wallet gate layout ${platform.name} ${brightness.name} narrow=$narrow',
            (tester) async {
          tester.view.physicalSize = Size(narrow ? 320 : 390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final status = Completer<bool>();
          final settings = WalletEntrySettings()..check = (_) => status.future;
          final coordinator = WalletEntryCoordinator(
              settingsFactory: () => settings, sessionKey: () => 'preview');
          final active = ValueNotifier(3);
          addTearDown(coordinator.dispose);
          addTearDown(active.dispose);
          final boundary = GlobalKey();
          late BuildContext owner;
          var retries = 0;
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                platform: platform,
                brightness: brightness,
                fontFamily: _directory.isEmpty ? null : 'WalletEntryPreview'),
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(builder: (context) {
              owner = context;
              return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(narrow ? 2 : 1),
                      padding: const EdgeInsets.only(top: 24, bottom: 34)),
                  child: RepaintBoundary(
                      key: boundary,
                      child: WalletTabShell(
                          activeTabIndexListenable: active,
                          entry: coordinator,
                          onRetryEntry: () async {
                            retries++;
                          })));
            }),
          ));
          final pending =
              coordinator.enter(owner, isActive: () => true, onAllowed: () {});
          await tester.pumpAndSettle();
          expect(find.byType(WalletScreen), findsNothing);
          expect(find.byKey(const ValueKey('wallet-skeleton-actions')),
              findsOneWidget);
          final rows = [
            for (var i = 0; i < 3; i++)
              tester.getRect(find.byKey(ValueKey('wallet-skeleton-asset-$i')))
          ];
          expect(rows[1].top, greaterThan(rows[0].bottom));
          expect(rows[2].width, lessThanOrEqualTo(narrow ? 320 : 390));
          expect(
              find.byKey(const ValueKey('wallet-entry-retry')), findsNothing);
          expect(tester.takeException(), isNull);
          if (!narrow) {
            await _export(tester, boundary,
                'wallet-entry-${platform.name}-${brightness.name}-loading');
          }

          status.completeError(TimeoutException('connection timed out'));
          await tester.pumpAndSettle();
          expect(await pending, isFalse);
          expect(find.byType(WalletScreen), findsNothing);
          expect(
              find.byKey(const ValueKey('wallet-entry-retry')), findsNothing);
          expect(
              find.byKey(const ValueKey('wallet-entry-message')), findsNothing);
          await tester.drag(
              find.byKey(const ValueKey('wallet-entry-placeholder')),
              const Offset(0, 300));
          await tester.pumpAndSettle();
          expect(retries, 1);
          expect(tester.takeException(), isNull);
          if (!narrow) {
            await _export(tester, boundary,
                'wallet-entry-${platform.name}-${brightness.name}-retry');
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}

Future<void> _export(
    WidgetTester tester, GlobalKey boundary, String name) async {
  if (_directory.isEmpty) return;
  await tester.pumpAndSettle();
  final render =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(_directory)..createSync(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
