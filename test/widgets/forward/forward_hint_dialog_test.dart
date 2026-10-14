import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/forward/forward_message_preview.dart';

Message message(int type, Map<String, dynamic> fields) =>
    Message.fromJson(jsonDecode(jsonEncode({
      'contentType': type,
      'status': MessageStatus.succeeded,
      'senderNickname': '小林',
      ...fields,
    })));

final samples = <Message>[
  message(MessageType.text, {
    'textElem': {'content': '周六下午两点见，记得带上相机。\n我们在公园入口集合。'}
  }),
  message(MessageType.atText, {
    'atTextElem': {'text': '@atAllTag 周六见'}
  }),
  message(MessageType.advancedText, {
    'advancedTextElem': {'text': '带格式的消息'}
  }),
  message(MessageType.quote, {
    'quoteElem': {
      'text': '好的，周六见',
      'quoteMessage': {
        'contentType': MessageType.text,
        'senderNickname': '小林',
        'textElem': {'content': '下午两点集合'}
      }
    }
  }),
  message(MessageType.picture, {'pictureElem': {}}),
  message(MessageType.video, {
    'videoElem': {'duration': 24}
  }),
  message(MessageType.voice, {
    'soundElem': {'duration': 12}
  }),
  message(MessageType.file, {
    'fileElem': {'fileName': '项目方案.pdf', 'fileSize': 2936013}
  }),
  message(MessageType.card, {
    'cardElem': {'nickname': '林小满', 'userID': 'peer'}
  }),
  message(MessageType.location, {
    'locationElem': {
      'description': '世纪公园 · 锦绣路1001号',
      'latitude': 31.22,
      'longitude': 121.55
    }
  }),
  message(MessageType.customFace, {
    'faceElem': {'data': 'invalid'}
  }),
  message(MessageType.merger, {
    'mergeElem': {
      'title': '群聊的聊天记录',
      'abstractList': ['小林：周末一起出发吧', '阿杰：[图片]']
    }
  }),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
    Get.addTranslations(TranslationService().keys);
    Get.locale = const Locale('zh', 'CN');
  });
  tearDown(() => Get.reset());

  test('all forwardable SDK types retain their type-specific content', () {
    expect(samples.map(ForwardPreviewData.fromMessage).map((p) => p.kind), [
      ForwardPreviewKind.text,
      ForwardPreviewKind.text,
      ForwardPreviewKind.text,
      ForwardPreviewKind.text,
      ForwardPreviewKind.picture,
      ForwardPreviewKind.video,
      ForwardPreviewKind.voice,
      ForwardPreviewKind.file,
      ForwardPreviewKind.card,
      ForwardPreviewKind.location,
      ForwardPreviewKind.sticker,
      ForwardPreviewKind.record,
    ]);
    expect(ForwardPreviewData.fromMessage(samples[0]).title, contains('\n'));
    expect(ForwardPreviewData.fromMessage(samples[1]).title,
        contains('@${StrRes.everyone}'));
    expect(ForwardPreviewData.fromMessage(samples[3]).subtitle,
        contains('下午两点集合'));
    expect(ForwardPreviewData.fromMessage(samples[5]).duration, 24);
    expect(ForwardPreviewData.fromMessage(samples[7]).subtitle, '2.8 MB');
    expect(ForwardPreviewData.fromMessage(samples[9]).subtitle,
        contains('31.22000'));
    expect(ForwardPreviewData.fromMessage(samples[10]).imageUrl, isNull);
  });

  test('batch and merged previews preserve count, order, bounded summaries',
      () {
    final batch = ForwardPreviewData.fromMessages(samples);
    final merged = ForwardPreviewData.fromMessages(samples,
        merged: true, mergeTitle: '周末群的聊天记录');
    expect(batch.kind, ForwardPreviewKind.batch);
    expect(batch.count, samples.length);
    expect(batch.lines, hasLength(3));
    expect(batch.lines.first, contains('周六下午两点见'));
    expect(merged.kind, ForwardPreviewKind.record);
    expect(merged.title, '周末群的聊天记录');
    expect(merged.lines.first, startsWith('小林：'));
  });

  test('media keeps thumbnail and fallback paths, never video/audio URL', () {
    final picture =
        ForwardPreviewData.fromMessage(message(MessageType.picture, {
      'pictureElem': {
        'sourcePath': '/missing.jpg',
        'snapshotPicture': {'url': 'https://example.com/thumb.jpg'},
        'sourcePicture': {'url': 'https://example.com/full.jpg'}
      }
    }));
    expect(picture.imageUrl, 'https://example.com/thumb.jpg');
    expect(picture.imagePath, '/missing.jpg');
    final video = ForwardPreviewData.fromMessage(message(MessageType.video, {
      'videoElem': {
        'videoUrl': 'https://example.com/video.mp4',
        'snapshotUrl': 'https://example.com/poster.jpg'
      }
    }));
    expect(video.imageUrl, 'https://example.com/poster.jpg');
    final sticker =
        ForwardPreviewData.fromMessage(message(MessageType.customFace, {
      'faceElem': {
        'data':
            '{"url":"https://example.com/sticker.gif","width":100,"height":100}'
      }
    }));
    expect(sticker.imageUrl, endsWith('sticker.gif'));
  });

  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets('all previews fit dark=$dark large=$large', (tester) async {
        tester.view.physicalSize =
            large ? const Size(320, 568) : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final preview in [
          ...samples.map(ForwardPreviewData.fromMessage),
          ForwardPreviewData.fromMessages(samples),
          ForwardPreviewData.fromMessages(samples, merged: true)
        ]) {
          await tester.pumpWidget(ScreenUtilInit(
              designSize: const Size(375, 812),
              builder: (_, __) => MaterialApp(
                  theme: ThemeData(
                      brightness: dark ? Brightness.dark : Brightness.light),
                  home: MediaQuery(
                      data: MediaQueryData(
                          size: large
                              ? const Size(320, 568)
                              : const Size(390, 844),
                          textScaler: TextScaler.linear(large ? 2 : 1)),
                      child: Scaffold(
                          body: ForwardHintDialog(
                              title: '',
                              preview: preview,
                              checkedList: List.generate(
                                  large ? 20 : 1,
                                  (i) => UserInfo(
                                      userID: '$i',
                                      nickname: '很长的收件人名字 $i'))))))));
          await tester.pumpAndSettle();
          expect(find.byType(ForwardMessagePreview), findsOneWidget);
          final panel = tester.widget<Container>(
              find.byKey(const ValueKey('forward-message-preview')));
          expect((panel.decoration as BoxDecoration).color,
              AppTokens.surfaceAlt(dark: dark));
          expect(find.byKey(const ValueKey('forward-send')).hitTestable(),
              findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets(
      'cancel and send return the correct result; empty selection cannot send',
      (tester) async {
    bool? result;
    var empty = false;
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          result = await showDialog<bool>(
                              context: context,
                              builder: (_) => ForwardHintDialog(
                                  title: '待转发消息',
                                  checkedList: empty
                                      ? []
                                      : [
                                          UserInfo(userID: 'a', nickname: '冬'),
                                          UserInfo(userID: 'b', nickname: '小林')
                                        ]));
                        },
                        child: const Text('打开')))))));
    for (final send in [false, true]) {
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('${StrRes.send}（2）'), findsOneWidget);
      await tester
          .tap(find.byKey(ValueKey(send ? 'forward-send' : 'forward-cancel')));
      await tester.pumpAndSettle();
      expect(result, send);
    }
    empty = true;
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('forward-send')))
            .onPressed,
        isNull);
  });

  testWidgets(
      'local media decodes and missing files fall back without an exception',
      (tester) async {
    for (final exists in [true, false]) {
      final path = File(exists
              ? 'assets/ai/welcome.jpg'
              : 'test/missing-forward-thumbnail.jpg')
          .absolute
          .path;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 320,
                  child: ForwardMessagePreview(
                      data: ForwardPreviewData(
                          kind: ForwardPreviewKind.picture,
                          title: '图片',
                          imagePath: path))))));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      if (exists) {
        final raw = tester.widget<RawImage>(find.byType(RawImage));
        expect(raw.image, isNotNull);
        expect(raw.image!.width / raw.image!.height, closeTo(3, 0.05));
      } else {
        expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('render light and dark implementation previews', (tester) async {
    const directory = String.fromEnvironment('FORWARD_PREVIEW_DIR');
    if (directory.isEmpty) return;
    await tester.runAsync(() async {
      await (FontLoader('ForwardPreviewFont')
            ..addFont(File('C:/Windows/Fonts/msyh.ttc')
                .readAsBytes()
                .then(ByteData.sublistView)))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    });
    tester.view.physicalSize = const Size(1200, 2100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final dark in [false, true]) {
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(1200, 2100),
          builder: (_, __) => MaterialApp(
              theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                  fontFamily: 'ForwardPreviewFont'),
              home: RepaintBoundary(
                  key: const ValueKey('capture'),
                  child: Scaffold(
                      body: GridView.count(
                          crossAxisCount: 3,
                          childAspectRatio: 1,
                          children: [
                        for (final sample in samples)
                          ForwardHintDialog(
                              title: '',
                              preview: ForwardPreviewData.fromMessage(sample),
                              checkedList: [
                                UserInfo(userID: 'a', nickname: '冬')
                              ]),
                        ForwardHintDialog(
                            title: '',
                            preview: ForwardPreviewData.fromMessages(samples),
                            checkedList: List.generate(
                                4,
                                (i) => UserInfo(
                                    userID: '$i',
                                    nickname: ['冬', '小林', '阿杰', '设计群'][i]))),
                        ForwardHintDialog(
                            title: '',
                            preview: ForwardPreviewData.fromMessages(samples,
                                merged: true),
                            checkedList: [
                              UserInfo(userID: 'a', nickname: '冬')
                            ]),
                      ]))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$directory/forward-${dark ? 'dark' : 'light'}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
