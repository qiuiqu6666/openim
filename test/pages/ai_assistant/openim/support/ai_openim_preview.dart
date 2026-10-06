import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../presentation/support/ai_ui_test_host.dart';

Future<void> exportAiOpenimPreview(
    WidgetTester tester, AiUiTestHost host, String state) async {
  if (aiPreviewDirectory.isEmpty) return;
  final boundary = host.previewKey.currentContext!.findRenderObject()!
      as RenderRepaintBoundary;
  void repaint(RenderObject object) {
    object.visitChildren(repaint);
    object.markNeedsPaint();
  }

  repaint(boundary);
  await tester.pump();
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$aiPreviewDirectory/ai-openim-$state-'
          '${host.dark ? 'dark' : 'light'}.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
