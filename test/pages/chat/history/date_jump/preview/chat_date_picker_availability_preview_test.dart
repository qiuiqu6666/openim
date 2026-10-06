import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show RichText;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/chat_date_picker_availability_fixture.dart';

const _previewDirectory =
    String.fromEnvironment('CHAT_DATE_PICKER_PREVIEW_DIR');

Future<void> _loadPreviewFont() async {
  if (_previewDirectory.isEmpty) return;
  for (final font in {
    'ChatDatePickerPreview': 'C:/Windows/Fonts/msyh.ttc',
    'MaterialIcons':
        'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final loader = FontLoader(font.key);
    loader.addFont(File(font.value).readAsBytes().then(ByteData.sublistView));
    await loader.load();
  }
}

Future<void> _export(
    WidgetTester tester, DateJumpFixture fixture, String name) async {
  final render = fixture.boundary.currentContext!.findRenderObject()
      as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final output = Directory(_previewDirectory);
    await output.create(recursive: true);
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${output.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    await File('${output.path}/preview-notes.txt')
        .writeAsString('真实 Flutter 日期跳转弹窗；示例有记录日期为10月5/8/12/15日，其余灰色禁用。\n'
            '390×844标准、320×568和568×320为200%字体；2倍导出，微软雅黑。\n'
            'large/landscape另外导出滚动到12日后的scrolled视图，取消按钮保持固定。\n'
            '仅测试夹具消息，不发起服务端请求。\n');
  });
}

// Actual-widget exports, enabled only when explicitly requested:
// --dart-define=CHAT_DATE_PICKER_PREVIEW_DIR=E:/openim/.temp/chat-date-picker-preview
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Get.testMode = true);
  setUpAll(_loadPreviewFont);
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    for (final (size, scale, suffix) in const [
      (Size(390, 844), 1.0, ''),
      (Size(320, 568), 2.0, '-large'),
      (Size(568, 320), 2.0, '-landscape'),
    ]) {
      testWidgets('export ${brightness.name} date picker$suffix',
          skip: _previewDirectory.isEmpty, (tester) async {
        final fixture = DateJumpFixture(
          DateJumpSource(days: {
            DateTime(2026, 10, 5),
            dateJumpPresent,
            DateTime(2026, 10, 12),
            dateJumpToday,
          }),
        );
        await fixture.open(tester,
            brightness: brightness,
            size: size,
            textScale: scale,
            fontFamily: 'ChatDatePickerPreview');
        expect(dateJumpKey('cancel').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        final name = 'chat-date-picker-${brightness.name}$suffix';
        await _export(tester, fixture, name);
        if (suffix.isNotEmpty) {
          await tester.ensureVisible(dateJumpDay(DateTime(2026, 10, 12)));
          await tester.pumpAndSettle();
          expect(dateJumpKey('cancel').hitTestable(), findsOneWidget);
          await _export(tester, fixture, '$name-scrolled');
        }
        for (final day in [10, 12, 15, 31]) {
          final number = tester.renderObject<RenderParagraph>(find.descendant(
              of: dateJumpDay(DateTime(2026, 10, day)),
              matching: find.byType(RichText)));
          final boxes = number.getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 2));
          expect(boxes, hasLength(1),
              reason: 'Both digits of day $day must fit on one visible line');
          // Font boxes can include half of the final letter spacing outside
          // the paragraph's advance width; allow subpixel font rounding.
          expect(boxes.single.left, greaterThanOrEqualTo(-.5));
          expect(boxes.single.right, lessThanOrEqualTo(number.size.width + .5),
              reason: 'Day $day must not clip its second digit horizontally');
          expect(
              boxes.single.bottom, lessThanOrEqualTo(number.size.height + .5),
              reason: 'Day $day must not clip its second digit vertically');
        }
      });
    }
  }
}
