import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../ai_assistant/presentation/support/ai_ui_test_host.dart';

final officialPreviewDirectory =
    Platform.environment['OFFICIAL_ACCOUNT_PREVIEW_DIR'] ?? '';

Future<void> loadOfficialPreviewFonts() async {
  await loadAiPreviewFonts();
  final bytes = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
  // Text styles with inherit:false use the tester's default family. Register a
  // real font there too so metadata and line measurements match the preview.
  for (final family in ['Ahem', 'Roboto']) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
}

Future<void> exportOfficialAccountPreview(
    WidgetTester tester, AiUiTestHost host, String name) async {
  if (officialPreviewDirectory.isEmpty) return;
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
      final file = File('$officialPreviewDirectory/official-$name-'
          '${host.dark ? 'dark' : 'light'}.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
