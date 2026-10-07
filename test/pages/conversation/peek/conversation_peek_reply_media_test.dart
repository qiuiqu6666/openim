import 'dart:convert';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_content.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_loader.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/quote/chat_quote_card.dart';
import 'package:openim_common/src/widgets/chat/quote/chat_quote_thumbnail.dart';

Message _message(String id, {bool outgoing = false}) => Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': outgoing ? 'self' : 'peer',
      'recvID': outgoing ? 'peer' : 'self',
      'senderNickname': outgoing ? '我' : '小林',
      'sendTime': 1700000000000,
      'seq': 1,
      'status': MessageStatus.succeeded,
      // Android SDK history uses the JSON null string for absent metadata.
      'attachedInfo': 'null',
      'attachedInfoElem': {'isPrivateChat': false, 'burnDuration': 0},
      'textElem': {'content': '原消息内容'},
    });

Message _picture({bool outgoing = false, int height = 18000}) =>
    _message('picture', outgoing: outgoing)
      ..contentType = MessageType.picture
      ..pictureElem = PictureElem(
          sourcePicture: PictureInfo(
              width: 900, height: height, url: 'https://media.test/original'),
          snapshotPicture: PictureInfo(
              width: 30, height: height ~/ 30, url: 'https://media.test/tiny'));

Message _reply(int type, Message original, {bool outgoing = false}) {
  final message = _message('reply', outgoing: outgoing)..contentType = type;
  if (type == MessageType.atText) {
    message.atTextElem = AtTextElem(
        text: '@peer 回复正文',
        atUsersInfo: [AtUserInfo(atUserID: 'peer', groupNickname: '小林')],
        quoteMessage: original);
  } else {
    message.quoteElem = QuoteElem(text: '回复正文', quoteMessage: original);
  }
  return message;
}

Future<ConversationPeekLoader> _mount(WidgetTester tester, Message message,
    {bool dark = false, double width = 340}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Styles.isDark = dark;
  final conversation = ConversationInfo(
      conversationID: 'si_peer',
      conversationType: ConversationType.single,
      userID: 'peer',
      showName: '小林');
  // Exercise the same SDK serialization, clone and history path as a real peek.
  final response = jsonEncode(
      AdvancedMessage(messageList: [message], isEnd: true, errCode: 0)
          .toJson());
  final loader = ConversationPeekLoader(
      conversation: conversation,
      currentAccountID: () => 'self',
      currentToken: () => 'token',
      fetch: ({required count, startMsg}) async =>
          AdvancedMessage.fromJson(jsonDecode(response)));
  addTearDown(loader.dispose);
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: width,
                      height: 420,
                      child: ConversationPeekContent(
                          loader: loader, conversation: conversation)))))));
  await loader.loadInitial();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return loader;
}

void main() {
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    ChatHistoryCache.clear();
  });
  tearDown(() {
    Styles.isDark = false;
    ChatHistoryCache.clear();
    Get.reset();
  });

  for (final dark in [false, true]) {
    testWidgets('SDK null metadata keeps the ordinary text bubble ($dark)',
        (tester) async {
      final loader = await _mount(tester, _message('text'), dark: dark);
      expect(find.text('原消息内容', findRichText: true), findsOneWidget);
      expect(find.byType(ChatBubble), findsOneWidget);
      expect(loader.messages.single.attachedInfo, 'null');
      expect(
          ChatHistoryCache.read('self', 'si_peer').single.clientMsgID, 'text');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final type in [MessageType.quote, MessageType.atText]) {
      for (final picture in [false, true]) {
        testWidgets('history keeps quoted content ($dark, $type, $picture)',
            (tester) async {
          final original = picture ? _picture() : _message('original');
          final reply = _reply(type, original, outgoing: !dark);
          final loader = await _mount(tester, reply, dark: dark);
          expect(find.byType(ChatQuoteCard), findsOneWidget);
          final card = find.byType(ChatQuoteCard);
          expect(find.descendant(of: card, matching: find.text('小林')),
              findsOneWidget);
          expect(
              find.descendant(
                  of: card,
                  matching: find.text(picture ? StrRes.picture : '原消息内容')),
              findsOneWidget);
          expect(find.byType(ChatQuoteThumbnail),
              picture ? findsOneWidget : findsNothing);
          if (picture) {
            final thumbnail = tester.widget<ExtendedImage>(find.descendant(
                of: find.byType(ChatQuoteThumbnail),
                matching: find.byType(ExtendedImage)));
            final provider = thumbnail.image as ExtendedResizeImage;
            expect(provider.width, 40);
            expect(provider.height, 800);
            expect(thumbnail.alignment, Alignment.topCenter);
          }
          final body = find.text(
              type == MessageType.atText ? '@小林 回复正文' : '回复正文',
              findRichText: true);
          expect(body, findsOneWidget);
          expect(tester.getBottomLeft(card).dy,
              lessThan(tester.getTopLeft(body).dy));
          expect(loader.messages.single.clientMsgID, 'reply');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  for (final outgoing in [false, true]) {
    testWidgets('long image is a clear top crop in both directions ($outgoing)',
        (tester) async {
      await _mount(tester, _picture(outgoing: outgoing));
      final size = tester.getSize(find.byType(ChatPictureView));
      expect(size, const Size(156, 260));
      final image = tester
          .widgetList<ExtendedImage>(find.byType(ExtendedImage))
          .firstWhere((image) => image.width == size.width);
      expect(image.alignment, Alignment.topCenter);
      expect(image.fit, BoxFit.fitWidth);
      final provider = image.image as ExtendedResizeImage;
      expect((provider.imageProvider as ExtendedNetworkImageProvider).url,
          'https://media.test/original');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('ordinary portrait still fits without cropping', (tester) async {
    await _mount(tester, _picture(height: 1600));
    final size = tester.getSize(find.byType(ChatPictureView));
    expect(size.width / size.height, closeTo(900 / 1600, 0.001));
    expect(size.height, 260);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('long image keeps its crop ratio in a narrow incoming column',
      (tester) async {
    await _mount(tester, _picture(), width: 180);
    final size = tester.getSize(find.byType(ChatPictureView));
    expect(size.width, lessThan(156));
    expect(size.width / size.height, closeTo(3 / 5, 0.001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mention replies keep private quoted content out of peek/cache',
      (tester) async {
    final original = _message('private')
      ..attachedInfo = jsonEncode({'isPrivateChat': true, 'burnDuration': 30});
    final loader = await _mount(tester, _reply(MessageType.atText, original));
    expect(find.text('私密消息请进入会话查看'), findsOneWidget);
    expect(find.byType(ChatQuoteCard), findsNothing);
    expect(find.text('原消息内容'), findsNothing);
    expect(
        ConversationPeekLoader.containsPrivateContent(loader.messages.single),
        isTrue);
    expect(ChatHistoryCache.read('self', 'si_peer'), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
