import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/core/session/connection/widgets/connection_health_title.dart';
import 'package:openim/core/session/connection/widgets/connection_signal_icon.dart';
import 'package:openim/pages/conversation/widgets/conversation_header_actions.dart';
import 'package:openim_common/openim_common.dart';

Widget header(int latency, {bool offline = false, bool checking = false}) =>
    SizedBox(
        height: kToolbarHeight,
        child: GlassAppBar(
          toolbarHeight: kToolbarHeight,
          automaticallyImplyLeading: false,
          centerTitle: false,
          titleSpacing: 16,
          title: ConnectionHealthTitle(
            title: '消息',
            connection: offline
                ? IMSdkStatus.connectionFailed
                : checking
                    ? IMSdkStatus.connecting
                    : IMSdkStatus.connectionSucceeded,
            apiAvailable: const AlwaysStoppedAnimation(true),
            latencyMs: AlwaysStoppedAnimation(latency),
            routeMarker: () => '2',
          ),
          actions: [
            ConversationHeaderActions(
                editing: false,
                onSupport: () {},
                onToggleEditing: () {},
                plusKey: GlobalKey(),
                plusTurns: 0,
                onPlus: () {})
          ],
        ));

Widget app(Widget child,
        {Brightness brightness = Brightness.light,
        double textScale = 1,
        String? font}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: brightness, fontFamily: font),
      home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Material(
              child: Align(alignment: Alignment.topLeft, child: child))),
    );

void main() {
  testWidgets('Chinese connecting label replaces latency in a compact header',
      (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(app(
          SizedBox(width: 320, child: header(62, checking: true)),
          brightness: brightness,
          textScale: 2));
      expect(find.text('消息'), findsOneWidget);
      expect(find.text('连接中...'), findsOneWidget);
      expect(find.text('62 ms · 2'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'capsules without captions and actions fit the toolbar in $brightness',
        (tester) async {
      for (final width in [320.0, 375.0, 700.0]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(app(
              SizedBox(
                  width: width,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final ms in [61, 280, 680]) header(ms),
                      header(680, offline: true)
                    ],
                  )),
              brightness: brightness,
              textScale: scale));
          await tester.pump();
          expect(find.text('良好'), findsNothing);
          expect(find.text('一般'), findsNothing);
          expect(find.text('较高'), findsNothing);
          expect(find.text('离线'), findsNothing);
          expect(find.text('不可用'), findsOneWidget);
          expect(find.byType(ConnectionSignalIcon), findsNWidgets(4));
          expect(tester.takeException(), isNull, reason: '$width / $scale');
        }
      }
    });
  }

  const output = String.fromEnvironment('BADGE_PREVIEW');
  testWidgets('render actual header states for visual inspection',
      (tester) async {
    // Optional local visual export; no OS font paths are required by CI.
    await tester.runAsync(() async {
      for (final entry in {
        'Preview': 'C:/Windows/Fonts/msyh.ttc',
        'PreviewBold': 'C:/Windows/Fonts/msyhbd.ttc'
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(File(entry.value)
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)));
        await loader.load();
      }
    });
    await tester.binding.setSurfaceSize(const Size(750, 350));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundary = GlobalKey();
    Widget panel(Brightness brightness) => SizedBox(
        width: 375,
        child: app(
            Column(children: [
              const SizedBox(height: 30),
              for (final ms in [61, 280, 680])
                Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: header(ms)),
              header(680, offline: true),
            ]),
            brightness: brightness,
            font: 'Preview'));
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: Row(
            textDirection: TextDirection.ltr,
            children: [panel(Brightness.light), panel(Brightness.dark)])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(output).parent.create(recursive: true);
      await File(output).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }, skip: output.isEmpty);
}
