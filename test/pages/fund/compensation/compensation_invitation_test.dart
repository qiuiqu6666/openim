import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/compensation/models/compensation_detail.dart';
import 'package:openim/pages/fund/compensation/presentation/compensation_invitation.dart';
import 'package:openim/pages/fund/compensation/presentation/compensation_tokens.dart';
import 'support.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    for (final dark in [false, true]) {
      testWidgets('original demo artwork supports text $scale dark=$dark',
          (t) async {
        await t.binding.setSurfaceSize(const Size(360, 780));
        addTearDown(() => t.binding.setSurfaceSize(null));
        bool? result;
        await t.pumpWidget(MaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            builder: (c, w) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: w!),
            home: Builder(
                builder: (c) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          result = await showDialog<bool>(
                              context: c,
                              builder: (_) => CompensationInvitation(
                                  detail: CompensationDetail.fromJson(
                                      response(total: '10.00'))));
                        },
                        child: const Text('open'))))));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        expect(
            find.descendant(
                of: find.byType(CompensationInvitation),
                matching: find.byType(Text)),
            findsNothing);
        expect(
            (t
                    .widget<Image>(find.descendant(
                        of: find.byType(CompensationInvitation),
                        matching: find.byType(Image)))
                    .image as AssetImage)
                .assetName,
            CompensationTokens.poster);
        expect(find.textContaining('300万'), findsNothing);
        expect(find.textContaining('金额随机'), findsNothing);
        expect(t.widget<Dialog>(find.byType(Dialog)).backgroundColor,
            Colors.transparent);
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.byTooltip('关闭活动提醒'));
        await t.tap(find.byTooltip('关闭活动提醒'));
        await t.pumpAndSettle();
        expect(result, false);
      });
    }
  }
  const output = String.fromEnvironment('INVITATION_CAPTURE');
  testWidgets('capture real invitation layout', skip: output.isEmpty,
      (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final loader = FontLoader('PosterCJK');
    loader.addFont(Future.value(ByteData.sublistView(
        File('C:/Windows/Fonts/msyh.ttc').readAsBytesSync())));
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'PosterCJK'),
        home: RepaintBoundary(
            key: key,
            child: Scaffold(
                backgroundColor: Colors.grey,
                body: CompensationInvitation(
                    detail: CompensationDetail.fromJson(
                        response(total: '10.00')))))));
    await t.runAsync(() => precacheImage(
        const AssetImage(CompensationTokens.poster),
        t.element(find.byType(CompensationInvitation))));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(output).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
