import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/peek/conversation_peek.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_actions.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_loader.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';

final _enabled = Platform.environment['EXPORT_PEEK_PREVIEW'] == '1' ||
    const String.fromEnvironment('EXPORT_PEEK_PREVIEW') == '1';
const _mediaPreview = bool.fromEnvironment('PEEK_MEDIA_PREVIEW');

Future<File> _createLongPhoto() async {
  final directory = await Directory.systemTemp.createTemp('peek-long-photo-');
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFF6F8FB), BlendMode.src);
  for (var row = 0; row < 120; row++) {
    final y = row * 60.0;
    canvas.drawRect(
        Rect.fromLTWH(0, y, 600, 60),
        Paint()
          ..color = row == 0
              ? const Color(0xFFCCE7FE)
              : row.isEven
                  ? const Color(0xFFF0F3F7)
                  : const Color(0xFFFFFFFF));
    final text = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
            text: row == 0
                ? '长图头部 · 数据明细'
                : '第 $row 行       项目 ${row + 100}       已完成',
            style: TextStyle(
                color: const Color(0xFF18324C),
                fontSize: row == 0 ? 36 : 28,
                fontFamily: 'PeekPreviewFont')))
      ..layout(maxWidth: 570);
    text.paint(canvas, Offset(15, y + 10));
    text.dispose();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(600, 7200);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final photo = await File('${directory.path}/long.png')
      .writeAsBytes(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  addTearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    await photo.delete();
    await directory.delete();
  });
  return photo;
}

Future<void> _loadFonts() async {
  final bytes = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
  for (final family in [
    'PeekPreviewFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay'
  ]) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
  await (FontLoader('packages/font_awesome_flutter/FontAwesomeSolid')
        ..addFont(rootBundle
            .load('packages/font_awesome_flutter/lib/fonts/fa-solid-900.ttf')))
      .load();
}

ThemeData _theme(bool dark) {
  final brightness = dark ? Brightness.dark : Brightness.light;
  final surface = dark ? const Color(0xFF202A36) : Colors.white;
  final foreground = dark ? const Color(0xFFE8EDF5) : const Color(0xFF0C1C33);
  final label = TextStyle(
      color: CupertinoColors.label,
      fontSize: 17.sp,
      fontFamily: 'PeekPreviewFont');
  return ThemeData(
    fontFamily: 'PeekPreviewFont',
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0089FF),
            brightness: brightness,
            surface: surface)
        .copyWith(onSurface: foreground),
    scaffoldBackgroundColor:
        dark ? const Color(0xFF141D27) : const Color(0xFFF8F9FA),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: CupertinoColors.systemBlue,
      applyThemeToAll: true,
      textTheme: const CupertinoTextThemeData().copyWith(
          textStyle: label,
          actionTextStyle: label.copyWith(color: CupertinoColors.systemBlue)),
    ),
  );
}

Message _text(int index, String content, {bool outgoing = false}) =>
    Message.fromJson({
      'clientMsgID': 'preview-$index',
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': outgoing ? 'preview-self' : 'preview-peer',
      'recvID': outgoing ? 'preview-peer' : 'preview-self',
      'senderNickname': outgoing ? '我' : '小林',
      'sendTime': DateTime(2026, 10, 4, 18, 20, index).millisecondsSinceEpoch,
      'seq': index,
      'status': MessageStatus.succeeded,
      'isRead': outgoing,
      'attachedInfo': 'null',
      'attachedInfoElem': {'isPrivateChat': false, 'burnDuration': 0},
      'textElem': {'content': content},
    });

List<Message> _messages({File? photo}) {
  if (photo != null) {
    final picture = _text(1, '', outgoing: true)
      ..contentType = MessageType.picture
      ..pictureElem = PictureElem(
          sourcePath: photo.path,
          sourcePicture: PictureInfo(width: 600, height: 7200));
    final reply = _text(2, '', outgoing: true)
      ..contentType = MessageType.atText
      ..atTextElem = AtTextElem(
          text: '@preview-peer 请核对这张长图。',
          atUsersInfo: [
            AtUserInfo(atUserID: 'preview-peer', groupNickname: '小林')
          ],
          quoteMessage: picture);
    return [picture, reply];
  }
  final first = _text(1, '周末一起去喝咖啡吗？');
  final custom = _text(3, '', outgoing: true)
    ..contentType = MessageType.custom
    ..customElem = CustomElem(
      data: jsonEncode({
        'customType': 2300,
        'data': {
          'markdown':
              '**三公结果**\n\n| 门 | 结果 |\n| --- | --- |\n| 3 | 三公 |\n\n完整正文保留换行'
        },
      }),
      description: '不应替代正文的摘要',
    );
  final quote = _text(4, '', outgoing: true)
    ..contentType = MessageType.quote
    ..quoteElem = QuoteElem(text: '好，那就明天下午三点见。', quoteMessage: first);
  final private = _text(5, '此私密内容不应显示在预览中')
    ..attachedInfoElem =
        AttachedInfoElem(isPrivateChat: true, burnDuration: 30);
  return [
    first,
    _text(2, '我发现了一家很不错的新店。'),
    custom,
    quote,
    private,
  ];
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('export actual conversation peek light and dark ($platform)',
        (tester) async {
      await tester.runAsync(_loadFonts);
      final photo =
          _mediaPreview ? await tester.runAsync(_createLongPhoto) : null;
      Get.testMode = true;
      OpenIM.iMManager.userID = 'preview-self';
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() {
        Styles.isDark = false;
        ChatHistoryCache.clear();
        Get.reset();
      });
      for (final dark in [false, true]) {
        ChatHistoryCache.clear();
        Styles.isDark = dark;
        final key = GlobalKey();
        late BuildContext hostContext;
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => RepaintBoundary(
            key: key,
            child: GetMaterialApp(
              debugShowCheckedModeBanner: false,
              translations: TranslationService(),
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: _theme(dark),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: 24, bottom: 34)),
                child: child!,
              ),
              home: Builder(builder: (context) {
                hostContext = context;
                return Scaffold(
                  appBar: AppBar(title: const Text('消息')),
                  body: ListTile(
                    leading:
                        const AvatarView(width: 54, height: 54, text: '小林'),
                    title: const Text('小林'),
                    subtitle: const Text('周末一起去喝咖啡吗？'),
                  ),
                );
              }),
            ),
          ),
        ));
        final conversation = ConversationInfo(
            conversationID: 'si_preview-peer',
            conversationType: ConversationType.single,
            userID: 'preview-peer',
            showName: '小林',
            unreadCount: 3);
        final loader = ConversationPeekLoader(
          conversation: conversation,
          currentAccountID: () => 'preview-self',
          currentToken: () => 'preview-only-token',
          fetch: ({required count, startMsg}) async => AdvancedMessage(
              messageList: _messages(photo: photo), isEnd: true, errCode: 0),
        );
        if (photo != null) {
          // Start file I/O outside the fake widget clock before mounting the
          // images, so the preview captures decoded pixels instead of a spinner.
          await tester.runAsync(() async {
            for (final size in [const Size(156, 1872), const Size(40, 480)]) {
              final image = ImageUtil.fileImage(
                file: photo,
                cacheWidth: size.width.toInt(),
                cacheHeight: size.height.toInt(),
                resizePolicy: ResizeImagePolicy.fit,
                cacheRawData: size.width == 40,
              ) as ExtendedImage;
              await precacheImage(image.image, hostContext)
                  .timeout(const Duration(seconds: 10));
            }
          });
        }
        final completion = showConversationPeek(
          context: hostContext,
          conversation: conversation,
          displayName: '小林',
          historyLoader: loader,
          isActive: () => hostContext.mounted,
          actions: ConversationPeekActions(
            onOpenChat: () {},
            onArchive: () async {},
            onAddToFolder: () async {},
            onTogglePin: () async {},
            onToggleMute: () async {},
            onDelete: () async {},
          ),
        );
        await tester.pumpAndSettle();
        if (photo != null) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
          });
          await tester.pumpAndSettle();
          expect(tester.getSize(find.byType(ChatPictureView)),
              const Size(156, 260));
          final images = tester
              .stateList(find.byType(ExtendedImage))
              .cast<ExtendedImageState>();
          expect(images, hasLength(2));
          expect(images.map((image) => image.extendedImageLoadState),
              everyElement(LoadState.completed));
          expect(find.text(StrRes.picture), findsOneWidget);
          expect(find.text('@小林 请核对这张长图。', findRichText: true), findsOneWidget);
        } else {
          expect(find.text('私密消息请进入会话查看'), findsOneWidget);
        }
        expect(find.text('此私密内容不应显示在预览中'), findsNothing);
        expect(conversation.unreadCount, 3);
        expect(tester.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final platformSuffix = platform == TargetPlatform.iOS ? '-ios' : '';
          final file = File(
              'docs/previews/peek${photo == null ? '' : '-reply-media'}$platformSuffix-${dark ? 'dark' : 'light'}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        Navigator.of(hostContext).pop();
        await tester.pumpAndSettle();
        await completion;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    }, skip: !_enabled, variant: TargetPlatformVariant({platform}));
  }
}
