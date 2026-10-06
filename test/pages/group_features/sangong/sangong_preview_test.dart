import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/group_features/sangong/sangong_module.dart';
import 'sangong_test_support.dart';

const _output = String.fromEnvironment('SANGONG_PREVIEW');

void main() {
  testWidgets(
      'export actual Sangong pages and native overlay across platforms, themes and sizes',
      (tester) async {
    expect(File(_output).isAbsolute, isTrue);
    SharedPreferences.setMockInitialValues({});
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = oldShadows);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final path in [
        'C:/Windows/Fonts/msyh.ttf',
        'C:/Windows/Fonts/msyh.ttc'
      ]) {
        final font = File(path);
        if (!await font.exists()) continue;
        final bytes = ByteData.sublistView(await font.readAsBytes());
        await (FontLoader('SangongPreviewFont')..addFont(Future.value(bytes)))
            .load();
        await (FontLoader('Roboto')..addFont(Future.value(bytes))).load();
        break;
      }
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final captures = <ui.Image>[];
    const cellWidth = 390.0, cellHeight = 868.0;
    var column = 0;
    for (final size in [const Size(320, 640), const Size(390, 844)]) {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        for (final dark in [false, true]) {
          tester.view.physicalSize = size;
          final api = SangongTestApi();
          final context = sangongTestContext(api, groupID: 'preview-$column');
          final runtime = SangongRuntime(context);
          final pages = <Widget>[
            Scaffold(
                appBar: AppBar(title: const Text('三公交流群')),
                body: SangongFeatureHost(
                    featureContext: context,
                    builder: (_, banner, overlay) => Column(children: [
                          banner,
                          Expanded(
                              child: Stack(fit: StackFit.expand, children: [
                            const Center(child: Text('群聊消息')),
                            overlay
                          ]))
                        ]))),
            const SangongManageHomePage(
                gameGroupId: 'group-sangong',
                canEditConfig: true,
                canManageMembers: true),
            const SangongMyConfigPage(initialGameGroupId: 'group-sangong'),
            const SangongGameRulesSettingsPage(),
            const SangongAgentDashboardPage(),
          ];
          for (var row = 0; row < pages.length; row++) {
            final boundary = GlobalKey();
            await pumpSangongPage(tester, runtime, pages[row],
                dark: dark,
                platform: platform,
                boundary: boundary,
                fontFamily: 'SangongPreviewFont');
            if (row == 0) {
              await tester.tap(find.byTooltip('展开游戏功能'));
              await flushSangong(tester);
            }
            await tester.pump(const Duration(milliseconds: 450));
            expect(tester.takeException(), isNull,
                reason: 'page=$row size=$size platform=$platform dark=$dark');
            final render = boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final capture = (await tester.runAsync(() => render.toImage()))!;
            captures.add(capture);
            final x = column * cellWidth, y = row * cellHeight;
            canvas.drawRect(Rect.fromLTWH(x, y, cellWidth, cellHeight),
                Paint()..color = const Color(0xff888888));
            final label = TextPainter(
                text: TextSpan(
                    text:
                        '${size.width.toInt()} ${platform.name} ${dark ? 'dark' : 'light'}',
                    style: const TextStyle(
                        fontFamily: 'SangongPreviewFont',
                        fontSize: 12,
                        color: Colors.white)),
                textDirection: TextDirection.ltr)
              ..layout(maxWidth: cellWidth);
            label.paint(canvas, Offset(x + 8, y + 4));
            canvas.drawImage(capture,
                Offset(x + (cellWidth - size.width) / 2, y + 24), Paint());
            label.dispose();
            await unmountSangong(tester);
          }
          runtime.dispose();
          column++;
        }
      }
    }
    final picture = recorder.endRecording();
    await tester.runAsync(() async {
      final result = await picture.toImage(3120, 4340);
      final png = await result.toByteData(format: ui.ImageByteFormat.png);
      final file = File(_output);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
      result.dispose();
      picture.dispose();
      for (final capture in captures) {
        capture.dispose();
      }
    });
    debugDisableShadows = oldShadows;
  }, skip: _output.isEmpty);
}
