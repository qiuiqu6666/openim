import 'dart:io';
import 'dart:ui' as ui;

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
      'textElem': {'content': content},
    });

List<Message> _messages() {
  final first = _text(1, '周末一起去喝咖啡吗？');
  final quote = _text(4, '', outgoing: true)
    ..contentType = MessageType.quote
    ..quoteElem = QuoteElem(text: '好，那就明天下午三点见。', quoteMessage: first);
  final private = _text(5, '此私密内容不应显示在预览中')
    ..attachedInfoElem =
        AttachedInfoElem(isPrivateChat: true, burnDuration: 30);
  return [
    first,
    _text(2, '我发现了一家很不错的新店。'),
    _text(3, '可以呀，位置发我一下。', outgoing: true),
    quote,
    private,
  ];
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('export actual conversation peek light and dark ($platform)',
        (tester) async {
      await tester.runAsync(_loadFonts);
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
              messageList: _messages(), isEnd: true, errCode: 0),
        );
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
            onRemoveFromFolder: () async {},
            onTogglePin: () async {},
            onToggleMute: () async {},
            onDelete: () async {},
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('私密消息请进入会话查看'), findsOneWidget);
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
              'docs/previews/peek$platformSuffix-${dark ? 'dark' : 'light'}.png');
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
