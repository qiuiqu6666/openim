import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;

import '../support/chat_date_picker_availability_fixture.dart';

const _output = String.fromEnvironment('CHAT_DATE_IMAGE_PREVIEW_DIR');

class _PhotoSource extends DateJumpSource {
  _PhotoSource()
      : super(days: {
          for (var day = 1; day <= 15; day++) DateTime(2026, 10, day)
        });
  final paths = [
    File('assets/ai/11.webp').absolute.path,
    File('assets/img/group_live_hero.webp').absolute.path,
    File('assets/images/ivnbg.webp').absolute.path,
  ];

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    if (query.messageTypes.length != 1 ||
        query.messageTypes.single != MessageType.picture) {
      return super.search(
          conversationID: conversationID,
          query: query,
          pageIndex: pageIndex,
          count: count);
    }
    expect(conversationID, dateJumpConversation);
    expect(count, 20);
    final day = query.localStart!;
    imageCalls.add(day);
    if (day.day == 3 || day.day == 7 || !days.contains(day) || pageIndex != 1) {
      return [];
    }
    return [
      Message.fromJson({
        'clientMsgID': 'photo-${day.toIso8601String()}',
        'contentType': MessageType.picture,
        'sendTime':
            DateTime(day.year, day.month, day.day, 12).millisecondsSinceEpoch,
        'pictureElem': {
          'sourcePath': day.day == 9
              ? '/missing/preview-photo.png'
              : paths[day.day % paths.length],
        },
      })
    ];
  }
}

Future<void> _fonts() async {
  if (_output.isEmpty) return;
  for (final font in {
    'ChatDateImagePreview': 'C:/Windows/Fonts/msyh.ttc',
    'MaterialIcons':
        'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    await (FontLoader(font.key)
          ..addFont(File(font.value).readAsBytes().then(ByteData.sublistView)))
        .load();
  }
}

Future<void> _save(
    WidgetTester tester, DateJumpFixture fixture, String name) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  final render = fixture.boundary.currentContext!.findRenderObject()
      as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final output = Directory(_output);
    await output.create(recursive: true);
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${output.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    await File('${output.path}/preview-notes.txt').writeAsString(
        '真实日期跳转弹窗，真实SDK source interface测试照片投影，图片来自现有本地演示assets。\n'
        '10月1-15日有记录，3/7日无图片，9日图片加载失败；所有日期仍按真实可用性规则。\n'
        '390×844标准；320×568、568×320为200%字体；2倍导出，微软雅黑。\n');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_fonts);
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);
  for (final brightness in Brightness.values) {
    for (final (size, scale, suffix) in const [
      (Size(390, 844), 1.0, ''),
      (Size(320, 568), 2.0, '-large'),
      (Size(568, 320), 2.0, '-landscape'),
    ]) {
      testWidgets('export decoded-photo modal ${brightness.name}$suffix',
          skip: _output.isEmpty, (tester) async {
        final fixture = DateJumpFixture(_PhotoSource());
        await fixture.open(tester,
            brightness: brightness,
            size: size,
            textScale: scale,
            fontFamily: 'ChatDateImagePreview');
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        await tester.runAsync(() async {
          for (final image in images) {
            await precacheImage(image.image, fixture.boundary.currentContext!);
          }
        });
        await tester.pumpAndSettle();
        expect(
            tester
                .widgetList<RawImage>(find.byType(RawImage))
                .where((image) => image.image != null)
                .length,
            greaterThanOrEqualTo(10));
        final photoText = find.descendant(
            of: dateJumpDay(dateJumpPresent), matching: find.byType(Text));
        expect(tester.widget<Text>(photoText).style!.color, AppTokens.onAccent);
        expect(dateJumpKey('cancel').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        final name = 'chat-date-images-${brightness.name}$suffix';
        await _save(tester, fixture, name);
        if (suffix.isNotEmpty) {
          await tester.ensureVisible(dateJumpDay(DateTime(2026, 10, 12)));
          await tester.pumpAndSettle();
          expect(dateJumpKey('cancel').hitTestable(), findsOneWidget);
          await _save(tester, fixture, '$name-scrolled');
        }
      });
    }
  }
}
