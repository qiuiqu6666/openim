import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/compensation/models/compensation_detail.dart';
import 'package:openim/pages/fund/compensation/presentation/compensation_page.dart';
import 'support.dart';
import 'package:openim/pages/fund/compensation/presentation/compensation_countdown.dart';
import 'package:openim/pages/fund/compensation/presentation/compensation_artwork.dart';
import 'package:openim/pages/fund/compensation/presentation/compensation_tokens.dart';

// Opt-in, local-only screenshots with fake source; never included in the app.
void main() {
  const output = String.fromEnvironment('COMPENSATION_CAPTURE_DIR');
  const font = String.fromEnvironment('COMPENSATION_CAPTURE_FONT');
  for (final state in ['unclaimed', 'claimed', 'ended', 'ineligible']) {
    testWidgets('capture $state', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final loader = FontLoader('CaptureChinese');
      loader.addFont(
          Future.value(ByteData.sublistView(File(font).readAsBytesSync())));
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final source = FakeSource()
        ..current = CompensationDetail.fromJson(
            response(state: state, ended: state == 'ended'));
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'CaptureChinese'),
              home: CompensationPage(
                  activityID: 'activity-one', source: source))));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await precacheImage(const AssetImage(CompensationArtwork.stateAsset),
            t.element(find.byType(CompensationPage)));
        await precacheImage(const AssetImage(CompensationArtwork.stateSource),
            t.element(find.byType(CompensationPage)));
        await precacheImage(const AssetImage(CompensationArtwork.asset),
            t.element(find.byType(CompensationPage)));
        await precacheImage(
            const AssetImage(CompensationTokens.detailBackground),
            t.element(find.byType(CompensationPage)));
        await precacheImage(
            AssetImage(state == 'claimed'
                ? CompensationTokens.openAsset
                : CompensationTokens.closedAsset),
            t.element(find.byType(CompensationPage)));
      });
      await t.pumpAndSettle();
      await t.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/demo-$state.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      if (state == 'claimed') {
        await t.ensureVisible(find.byType(CompensationCountdown));
        await t.pumpAndSettle();
        await t.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/countdown-detail.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    }, skip: output.isEmpty || font.isEmpty);
  }
}
