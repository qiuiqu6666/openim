import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shapes = <String, Size>{
  'wide': Size(320, 160),
  'square': Size(300, 300),
  'tall': Size(160, 320),
  'small': Size(40, 20),
  'long-wide': Size(3000, 100),
};
const _frames = <String, Size>{
  'wide': Size(144, 72),
  'square': Size(144, 144),
  'tall': Size(92, 160),
  'small': Size(144, 72),
  'long-wide': Size(144, 32),
};
final _pngs = <String, Uint8List>{};

Future<Uint8List> _png(Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF168BFF));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void _warmUrl(String url, Uint8List bytes) {
  final stream = MemoryImage(bytes).resolve(ImageConfiguration.empty);
  for (final cache in [false, true]) {
    PaintingBinding.instance.imageCache.putIfAbsent(
        ExtendedNetworkImageProvider(url, cache: cache),
        () => stream.completer!);
  }
}

Message _message(String shape,
    {bool sent = true,
    bool legacy = false,
    int status = MessageStatus.succeeded}) {
  final size = _shapes[shape]!;
  final url = 'https://stickers.test/overlay-$shape.png';
  _warmUrl(url, _pngs[shape]!);
  final data = {'url': url, 'width': size.width, 'height': size.height};
  return Message.fromJson({
    'clientMsgID':
        'overlay-$shape-${sent ? 'sent' : 'received'}-$legacy-$status',
    'contentType': legacy ? MessageType.custom : MessageType.customFace,
    'sendID': sent ? 'me' : 'peer',
    'recvID': sent ? 'peer' : 'me',
    'senderNickname': sent ? 'Me' : 'Peer',
    'sessionType': ConversationType.single,
    'sendTime': 1700000000000,
    'isRead': true,
    'status': status,
    if (!legacy) 'faceElem': {'index': 0, 'data': jsonEncode(data)},
    if (legacy)
      'customElem': {
        'data': jsonEncode({
          'customType': CustomMessageType.emoji,
          'data': data,
        })
      },
  });
}

Future<void> _flush(WidgetTester tester) async {
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _mount(WidgetTester tester, Widget child,
    {Brightness brightness = Brightness.light,
    GlobalKey? screenshotKey}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
          body: RepaintBoundary(
        key: screenshotKey,
        child: Builder(
            builder: (context) => ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Align(alignment: Alignment.topLeft, child: child),
                )),
      )),
    ),
  ));
  await _flush(tester);
}

Finder _row(Message message) => find.byWidgetPredicate(
    (widget) => widget is ChatItemView && identical(widget.message, message));

Finder _metadata(Finder row) => find.descendant(
    of: row,
    matching: find.byWidgetPredicate((widget) =>
        widget is Row &&
        widget.mainAxisSize == MainAxisSize.min &&
        widget.children.any((child) => child is Text)));

void _expectWithin(Rect item, Rect frame) {
  expect(item.left, greaterThanOrEqualTo(frame.left));
  expect(item.top, greaterThanOrEqualTo(frame.top));
  expect(item.right, lessThanOrEqualTo(frame.right));
  expect(item.bottom, lessThanOrEqualTo(frame.bottom));
}

void _expectOverlay(WidgetTester tester, Message message, Size frameSize,
    {double rowRight = 359}) {
  final row = _row(message);
  final image =
      find.descendant(of: row, matching: find.byType(ChatImageSticker));
  final frameRect = tester.getRect(image);
  expect(frameRect.width, closeTo(frameSize.width, 0.01));
  expect(frameRect.height, closeTo(frameSize.height, 0.01));
  final metadata = _metadata(row);
  final metadataRect = tester.getRect(metadata);
  _expectWithin(metadataRect, frameRect);
  expect(frameRect.right - metadataRect.right, inInclusiveRange(2.0, 14.0));
  expect(frameRect.bottom - metadataRect.bottom, inInclusiveRange(2.0, 12.0));
  final receipt =
      find.descendant(of: row, matching: find.byType(ChatReadReceiptIcon));
  final sent = message.sendID == 'me';
  expect(receipt, sent ? findsOneWidget : findsNothing);
  if (sent) {
    _expectWithin(tester.getRect(receipt), frameRect);
    expect(tester.widget<ChatReadReceiptIcon>(receipt).color, Colors.white);
  }
  final time = find.descendant(of: metadata, matching: find.byType(Text));
  expect(tester.widget<Text>(time).style?.color, Colors.white);
  final containerFinder =
      find.descendant(of: row, matching: find.byType(ChatItemContainer));
  final container = tester.widget<ChatItemContainer>(containerFinder);
  expect(container.stickerMedia, isTrue);
  expect(container.bareMedia, isTrue);
  expect(container.mediaOverlay, isTrue);
  final rect = tester.getRect(containerFinder);
  expect(rect.left, 16);
  expect(rect.right, rowRight);
  expect(tester.getRect(row).bottom - rect.bottom, closeTo(12, 0.01));
  final decorations = tester
      .widgetList<DecoratedBox>(
          find.descendant(of: row, matching: find.byType(DecoratedBox)))
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .toList();
  expect(
      decorations.where((decoration) => decoration.gradient != null), isEmpty,
      reason:
          'Sticker metadata uses a local backing, rather than a full-width gradient.');
  expect(
      decorations.any((decoration) =>
          decoration.color != null &&
          decoration.color!.a > 0 &&
          decoration.color!.a < 1),
      isTrue);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _flush(tester);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in _shapes.entries) {
      _pngs[entry.key] = await _png(entry.value);
    }
    final cache = Directory('.dart_tool/sticker-overlay-test-cache')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => cache.absolute.path);
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
  });
  setUp(() async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'me';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'me', nickname: 'Me');
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    Get.reset();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'sticker time and receipts overlay sent and received frames in $brightness',
        (tester) async {
      final key = GlobalKey();
      final messages = [
        _message('wide'),
        _message('square', sent: false),
        _message('tall', legacy: true),
        _message('small', sent: false, legacy: true),
      ];
      await _mount(
          tester,
          Column(mainAxisSize: MainAxisSize.min, children: [
            for (final message in messages)
              ChatItemView(
                  message: message,
                  showLeftNickname: false,
                  onTapUserProfile: (_) {}),
          ]),
          brightness: brightness,
          screenshotKey: key);
      for (final message in messages) {
        _expectOverlay(
            tester, message, _frames[message.clientMsgID!.split('-')[1]]!);
      }
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File('.dart_tool/sticker-layout-${brightness.name}.png')
            .writeAsBytes(png!.buffer.asUint8List());
      });
      await _unmount(tester);
    });

    testWidgets(
        'tapping a sticker receipt opens the close-only preview in $brightness',
        (tester) async {
      final message = _message('wide');
      var delegatedTap = false;
      await _mount(
          tester,
          ChatItemView(
              message: message,
              onTapUserProfile: (_) {},
              onClickItemView: () => delegatedTap = true),
          brightness: brightness);
      final receipt = find.byType(ChatReadReceiptIcon);
      final point = tester.getRect(receipt).center;
      await tester.tapAt(point);
      await _flush(tester);
      expect(find.byType(MediaBrowser), findsOneWidget);
      final browser = tester.widget<MediaBrowser>(find.byType(MediaBrowser));
      expect(browser.closeOnly, isTrue);
      expect(
          browser.sources.single.url, 'https://stickers.test/overlay-wide.png');
      expect(delegatedTap, isFalse);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byIcon(Icons.download), findsNothing);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await _flush(tester);
      expect(find.byType(MediaBrowser), findsNothing);
      await _unmount(tester);
    });
  }

  testWidgets('hidden read receipts retain the sent state on the sticker',
      (tester) async {
    final message = _message('wide');
    await _mount(
        tester, ChatItemView(message: message, onTapUserProfile: (_) {}));
    expect(
        tester
            .widget<ChatReadReceiptIcon>(find.byType(ChatReadReceiptIcon))
            .isRead,
        isTrue);
    FriendDisplayPreferences.setReadReceipts(false);
    await _flush(tester);
    final receipt =
        tester.widget<ChatReadReceiptIcon>(find.byType(ChatReadReceiptIcon));
    expect(receipt.isRead, isFalse);
    expect(receipt.semanticLabel, StrRes.sentSuccessfully);
    expect(receipt.color, Colors.white);
    _expectOverlay(tester, message, _frames['wide']!);
    await _unmount(tester);
  });

  testWidgets('very wide and narrow-parent frames keep all metadata inside',
      (tester) async {
    final long = _message('long-wide');
    await _mount(tester, ChatItemView(message: long, onTapUserProfile: (_) {}));
    _expectOverlay(tester, long, const Size(144, 32));
    await _unmount(tester);
    final narrow = _message('wide');
    await _mount(
        tester,
        ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: ChatItemView(message: narrow, onTapUserProfile: (_) {})));
    _expectOverlay(tester, narrow, const Size(47.52, 32), rowRight: 104);
    await _unmount(tester);
  });

  testWidgets('the failure state stays visible on the sticker and can resend',
      (tester) async {
    final message = _message('wide', status: MessageStatus.failed);
    var resent = false;
    await _mount(
        tester,
        ChatItemView(
            message: message,
            onTapUserProfile: (_) {},
            onFailedToResend: () => resent = true));
    final failed = find.byType(ChatSendFailedView);
    expect(failed, findsOneWidget);
    expect(find.byType(ChatReadReceiptIcon), findsNothing);
    _expectWithin(
        tester.getRect(failed), tester.getRect(find.byType(ChatImageSticker)));
    await tester.tap(failed);
    await _flush(tester);
    expect(resent, isTrue);
    expect(find.byType(MediaBrowser), findsNothing);
    await _unmount(tester);
  });
}
