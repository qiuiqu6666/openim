import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/routes/swipe_back/app_page_route.dart';
import 'package:openim/routes/swipe_back/app_page_transitions_theme.dart';

const _topKey = ValueKey('reference-top');
Widget _page(bool incoming) => Scaffold(
      key: incoming ? _topKey : const ValueKey('reference-under'),
      appBar: AppBar(title: Text(incoming ? 'Chat' : 'Messages')),
      body: ListView.builder(
          itemCount: 15,
          itemBuilder: (_, index) => ListTile(
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(incoming
                    ? 'Message ${index + 1}'
                    : 'Conversation ${index + 1}'),
                subtitle: const Text('Motion reference preview'),
              )),
    );

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness follows reference timing without scaling or gaps',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final nav = GlobalKey<NavigatorState>();
      final captureKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            navigatorKey: nav,
            theme: ThemeData(
                brightness: brightness,
                pageTransitionsTheme: appPageTransitionsTheme),
            home: _page(false),
          )));
      unawaited(nav.currentState!
          .push(AppMaterialPageRoute<void>(builder: (_) => _page(true))));
      await tester.pump();
      // Approximate edge positions measured from the user's 30 fps video.
      // A 3% screen tolerance accounts for frame quantization and onset timing.
      const samples = {
        28: .917,
        61: .649,
        94: .453,
        128: .300,
        161: .191,
        194: .118,
        228: .075,
        261: .045,
        294: .028,
        328: .014,
        361: .009,
        394: .005
      };
      var previous = 0;
      for (final sample in samples.entries) {
        await tester.pump(Duration(milliseconds: sample.key - previous));
        previous = sample.key;
        expect(tester.getTopLeft(find.byKey(_topKey)).dx / 375,
            closeTo(sample.value, .03));
        expect(tester.getSize(find.byKey(_topKey)), const Size(375, 812));
        const captureDirectory = String.fromEnvironment('MOTION_CAPTURE_DIR');
        if (captureDirectory.isNotEmpty &&
            [61, 161, 294].contains(sample.key)) {
          final boundary = captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory(captureDirectory).create(recursive: true);
            await File('$captureDirectory/${brightness.name}-${sample.key}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(_topKey)).dx, 0);
      nav.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      // Pop must respond promptly, rather than playing push easing backwards.
      expect(tester.getTopLeft(find.byKey(_topKey)).dx, greaterThan(150));
      await tester.pumpAndSettle();
      expect(find.byKey(_topKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
