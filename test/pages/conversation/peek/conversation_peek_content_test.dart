import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/fund/fund_message_card.dart';
import 'package:openim/pages/chat/media/widgets/chat_video_thumbnail.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_content.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_loader.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_message.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_attachment_view.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

ConversationInfo _conversation() => ConversationInfo(
      conversationID: 'si_peer',
      conversationType: ConversationType.single,
      userID: 'peer',
      showName: 'Peer',
      unreadCount: 6,
    );

Message _message(String id, int sequence, {String? text}) => Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': 'peer',
      'recvID': 'self',
      'senderNickname': 'Peer',
      'sendTime': 1700000000000 + sequence * 1000,
      'seq': sequence,
      'status': MessageStatus.succeeded,
      'isRead': false,
      'textElem': {'content': text ?? id},
    });

class _Read {
  _Read(this.cursor);
  final String? cursor;
  final response = Completer<AdvancedMessage>();
  void complete(List<Message> messages, {bool isEnd = false}) =>
      response.complete(
          AdvancedMessage(messageList: messages, isEnd: isEnd, errCode: 0));
}

class _History {
  final reads = <_Read>[];

  Future<AdvancedMessage> fetch({required int count, Message? startMsg}) {
    expect(count, 30);
    final read = _Read(startMsg?.clientMsgID);
    reads.add(read);
    return read.response.future;
  }

  ConversationPeekLoader loader(ConversationInfo conversation) =>
      ConversationPeekLoader(
        conversation: conversation,
        fetch: fetch,
        currentAccountID: () => 'self',
        currentToken: () => 'token',
      );
}

Future<void> _mount(WidgetTester tester, Widget child,
    {bool dark = false,
    Size size = const Size(375, 812),
    Size preview = const Size(340, 320),
    double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = dark;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      debugShowCheckedModeBanner: false,
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: AppTokens.accent,
              brightness: dark ? Brightness.dark : Brightness.light)),
      builder: (context, body) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: body!,
      ),
      home: Scaffold(
          body: Center(
              child: SizedBox(
                  width: preview.width, height: preview.height, child: child))),
    ),
  ));
  await tester.pump();
}

Future<void> _close(WidgetTester tester, ConversationPeekLoader? loader) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpAndSettle();
  loader?.dispose();
  expect(tester.takeException(), isNull);
}

Finder _row(String id) => find.byKey(ValueKey('conversation-peek-message-$id'));
Finder get _historyView =>
    find.byKey(const ValueKey('conversation-peek-history'));

(String, Rect) _visibleAnchor(WidgetTester tester) {
  final viewport = tester.getRect(_historyView);
  final visible = <(String, Rect)>[];
  for (final widget in tester.widgetList<ConversationPeekMessage>(
      find.descendant(
          of: _historyView, matching: find.byType(ConversationPeekMessage)))) {
    final id = widget.message.clientMsgID!;
    final rect = tester.getRect(_row(id));
    if (rect.top >= viewport.top && rect.bottom <= viewport.bottom) {
      visible.add((id, rect));
    }
  }
  expect(visible, isNotEmpty);
  visible.sort((a, b) => (a.$2.center.dy - viewport.center.dy)
      .abs()
      .compareTo((b.$2.center.dy - viewport.center.dy).abs()));
  return visible.first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late Duration previousVisibilityInterval;

  setUp(() {
    previousVisibilityInterval =
        VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    Get.testMode = true;
    ChatHistoryCache.clear();
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
  });
  tearDown(() {
    VisibilityDetectorController.instance.updateInterval =
        previousVisibilityInterval;
    ChatHistoryCache.clear();
    Styles.isDark = false;
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
  });

  testWidgets(
      'content performs only SDK history reads and keeps unread unchanged',
      (tester) async {
    final methods = <String>[];
    final response = Completer<String>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      methods.add(call.method);
      expect(call.method, 'getAdvancedHistoryMessageList');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['count'], 30);
      expect(args['conversationID'], 'si_peer');
      return response.future;
    });
    final conversation = _conversation();
    final loader = ConversationPeekLoader(
        conversation: conversation,
        currentAccountID: () => 'self',
        currentToken: () => 'token');
    addTearDown(loader.dispose);
    await _mount(tester,
        ConversationPeekContent(loader: loader, conversation: conversation));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final pending = loader.loadInitial();
    final message = _message('Unread text', 1);
    response.complete(jsonEncode(
        AdvancedMessage(messageList: [message], isEnd: true, errCode: 0)
            .toJson()));
    expect(await pending, isTrue);
    await tester.pumpAndSettle();
    expect(_row('Unread text'), findsOneWidget);
    await tester.tap(_row('Unread text'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(methods, ['getAdvancedHistoryMessageList']);
    expect(message.isRead, isFalse);
    expect(loader.messages.single.isRead, isFalse);
    expect(conversation.unreadCount, 6);
    expect(Get.isRegistered<ChatLogic>(), isFalse);
    await _close(tester, loader);
  });

  for (final dark in [false, true]) {
    testWidgets('loading, failure retry and successful empty history ($dark)',
        (tester) async {
      final history = _History();
      final conversation = _conversation();
      final loader = history.loader(conversation);
      addTearDown(loader.dispose);
      await _mount(tester,
          ConversationPeekContent(loader: loader, conversation: conversation),
          dark: dark);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final initial = loader.loadInitial();
      history.reads.last.response.completeError(StateError('offline'));
      expect(await initial, isFalse);
      await tester.pumpAndSettle();
      expect(find.text('加载失败，请重试'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('conversation-peek-retry')));
      await tester.pump();
      expect(history.reads, hasLength(2));
      final retry = loader.loadInitial();
      history.reads.last.complete([], isEnd: true);
      expect(await retry, isTrue);
      await tester.pumpAndSettle();
      expect(find.text('暂无消息'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('重试'), findsNothing);
      expect(Get.isRegistered<ChatLogic>(), isFalse);
      await _close(tester, loader);
    });
  }

  testWidgets('cached history stays visible when latest read fails and retries',
      (tester) async {
    ChatHistoryCache.write('self', 'si_peer', [_message('Cached text', 1)]);
    final history = _History();
    final conversation = _conversation();
    final loader = history.loader(conversation);
    addTearDown(loader.dispose);
    await _mount(tester,
        ConversationPeekContent(loader: loader, conversation: conversation));
    expect(_row('Cached text'), findsOneWidget);
    final pending = loader.loadInitial();
    history.reads.last.response.completeError(StateError('offline'));
    expect(await pending, isFalse);
    await tester.pumpAndSettle();
    expect(_row('Cached text'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('conversation-peek-older-retry')));
    await tester.pump();
    final retry = loader.loadInitial();
    history.reads.last.complete([_message('Fresh text', 2)], isEnd: true);
    expect(await retry, isTrue);
    await tester.pumpAndSettle();
    expect(_row('Fresh text'), findsOneWidget);
    expect(_row('Cached text'), findsNothing);
    expect(find.text('重试'), findsNothing);
    await _close(tester, loader);
  });

  testWidgets(
      'a short latest page automatically loads older history without reading it',
      (tester) async {
    final history = _History();
    final conversation = _conversation();
    final loader = history.loader(conversation);
    addTearDown(loader.dispose);
    await _mount(tester,
        ConversationPeekContent(loader: loader, conversation: conversation));
    final latest = _message('latest-short-page', 20);
    final initial = loader.loadInitial();
    history.reads.single.complete([latest]);
    expect(await initial, isTrue);

    // No gesture or explicit paging call: the undersized viewport starts the
    // next read after laying out the latest page.
    await tester.pump();
    final controller = tester.widget<ListView>(_historyView).controller!;
    expect(controller.position.maxScrollExtent, 0);
    expect(
        history.reads.map((read) => read.cursor), [null, 'latest-short-page']);
    expect(loader.loadingOlder, isTrue);
    final latestRect = tester.getRect(_row('latest-short-page'));
    final older = loader.loadOlder();
    final olderMessages = [
      for (var i = 0; i < 10; i++) _message('older-short-page-$i', i),
    ];
    history.reads.last.complete(olderMessages, isEnd: true);
    expect(await older, isTrue);
    await tester.pumpAndSettle();

    expect(history.reads, hasLength(2));
    expect(loader.hasMoreOlder, isFalse);
    expect(controller.position.pixels, 0);
    expect(tester.getRect(_row('latest-short-page')), latestRect);
    expect(latestRect.bottom,
        closeTo(tester.getRect(_historyView).bottom - 4, .01));
    expect(loader.messages.last.clientMsgID, 'latest-short-page');
    expect(loader.messages.every((message) => message.isRead == false), isTrue);
    expect(latest.isRead, isFalse);
    expect(olderMessages.every((message) => message.isRead == false), isTrue);
    expect(conversation.unreadCount, 6);
    expect(Get.isRegistered<ChatLogic>(), isFalse);
    await _close(tester, loader);
  });

  testWidgets(
      'older history retry retains the viewport and uses its raw cursor',
      (tester) async {
    final history = _History();
    final conversation = _conversation();
    final loader = history.loader(conversation);
    addTearDown(loader.dispose);
    await _mount(tester,
        ConversationPeekContent(loader: loader, conversation: conversation));
    final initial = loader.loadInitial();
    history.reads.last.complete([
      for (var i = 0; i < 30; i++) _message('latest-$i', i),
    ]);
    await initial;
    await tester.pumpAndSettle();
    final latestRect = tester.getRect(_row('latest-29'));
    final older = loader.loadOlder();
    history.reads.last.response.completeError(StateError('older unavailable'));
    expect(await older, isFalse);
    await tester.pumpAndSettle();
    expect(tester.getRect(_row('latest-29')), latestRect);
    await tester
        .tap(find.byKey(const ValueKey('conversation-peek-older-retry')));
    await tester.pump();
    final retry = loader.loadOlder();
    history.reads.last.complete([
      for (var i = -10; i < 0; i++) _message('older-$i', i),
    ]);
    expect(await retry, isTrue);
    await tester.pumpAndSettle();
    expect(history.reads.map((read) => read.cursor),
        [null, 'latest-0', 'latest-0']);
    expect(tester.getRect(_row('latest-29')), latestRect);

    final controller = tester.widget<ListView>(_historyView).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(history.reads, hasLength(4));
    expect(history.reads.last.cursor, 'older--10');
    final (anchorID, anchorRect) = _visibleAnchor(tester);
    final pagination = loader.loadOlder();
    history.reads.last.complete([
      for (var i = -20; i < -10; i++) _message('earlier-$i', i),
    ], isEnd: true);
    expect(await pagination, isTrue);
    await tester.pumpAndSettle();
    expect(tester.getRect(_row(anchorID)).top, closeTo(anchorRect.top, .01));
    expect(loader.hasMoreOlder, isFalse);
    await _close(tester, loader);
  });

  testWidgets(
      'a filtered empty page still reaches older history and retries it',
      (tester) async {
    final history = _History();
    final conversation = _conversation();
    final loader = history.loader(conversation);
    addTearDown(loader.dispose);
    await _mount(tester,
        ConversationPeekContent(loader: loader, conversation: conversation));
    final initial = loader.loadInitial();
    history.reads.last.complete([
      _message('filtered-boundary', 2)..contentType = MessageType.typing,
    ]);
    expect(await initial, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('暂无消息'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('conversation-peek-load-older')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final older = loader.loadOlder();
    history.reads.last.response.completeError(StateError('offline'));
    expect(await older, isFalse);
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('conversation-peek-older-retry')));
    await tester.pump();
    final retry = loader.loadOlder();
    history.reads.last.complete([_message('visible older', 1)], isEnd: true);
    expect(await retry, isTrue);
    await tester.pumpAndSettle();
    expect(history.reads.map((read) => read.cursor),
        [null, 'filtered-boundary', 'filtered-boundary']);
    expect(_row('visible older'), findsOneWidget);
    expect(find.text('暂无消息'), findsNothing);
    expect(find.text('重试'), findsNothing);
    await _close(tester, loader);
  });

  testWidgets('a session change closes loading and reports inactive content',
      (tester) async {
    final pending = Completer<AdvancedMessage>();
    var account = 'self';
    final conversation = _conversation();
    final loader = ConversationPeekLoader(
      conversation: conversation,
      currentAccountID: () => account,
      currentToken: () => 'token',
      fetch: ({required count, startMsg}) => pending.future,
    );
    addTearDown(loader.dispose);
    await _mount(tester,
        ConversationPeekContent(loader: loader, conversation: conversation));
    final loading = loader.loadInitial();
    account = 'other';
    pending.complete(AdvancedMessage(
        messageList: [_message('Old account content', 1)],
        isEnd: true,
        errCode: 0));
    expect(await loading, isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('会话已失效'), findsOneWidget);
    expect(_row('Old account content'), findsNothing);
    expect(Get.isRegistered<ChatLogic>(), isFalse);
    await _close(tester, loader);
  });

  testWidgets(
      'direct and nested private messages display only their privacy mask',
      (tester) async {
    final private = _message('private', 1, text: 'Confidential content')
      ..attachedInfo = jsonEncode({'isPrivateChat': true, 'burnDuration': 30});
    final quote = _message('quote', 2, text: 'Outer quote text')
      ..contentType = MessageType.quote
      ..quoteElem = QuoteElem(text: 'Quote secret', quoteMessage: private);
    final merged = _message('merged', 3)
      ..contentType = MessageType.merger
      ..mergeElem = MergeElem(title: 'Merge secret', multiMessage: [quote]);
    await _mount(
        tester,
        ListView(children: [
          for (final message in [private, quote, merged])
            ConversationPeekMessage(message: message, isGroupChat: false),
        ]));
    await tester.pumpAndSettle();
    expect(find.text('私密消息请进入会话查看'), findsNWidgets(3));
    expect(find.text('Confidential content', findRichText: true), findsNothing);
    expect(find.text('Quote secret', findRichText: true), findsNothing);
    expect(find.text('Merge secret', findRichText: true), findsNothing);
    expect(find.byType(ChatItemView), findsNothing);
    expect(find.byType(ChatExpiringContent), findsNothing);
    expect(private.isRead, isFalse);
    expect(private.hasReadTime, isNull);
    expect(Get.isRegistered<ChatLogic>(), isFalse);
    await _close(tester, null);
  });

  testWidgets('passive voice and video previews cannot start playback',
      (tester) async {
    final voice = _message('voice', 1)
      ..contentType = MessageType.voice
      ..soundElem = SoundElem(duration: 6);
    final video = _message('video', 2)
      ..contentType = MessageType.video
      ..videoElem =
          VideoElem(duration: 9, snapshotWidth: 640, snapshotHeight: 480);
    await _mount(
        tester,
        ListView(children: [
          ConversationPeekMessage(message: voice, isGroupChat: false),
          ConversationPeekMessage(message: video, isGroupChat: false),
        ]),
        preview: const Size(340, 480));
    await tester.pumpAndSettle();
    final voiceView =
        tester.widget<ChatVoiceMessageView>(find.byType(ChatVoiceMessageView));
    expect(voiceView.readOnly, isTrue);
    expect(voiceView.onPlayed, isNull);
    expect(voiceView.playback, isNull);
    expect(find.byType(ChatVideoThumbnail), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
    await tester.tap(find.byType(ChatVoiceMessageView), warnIfMissed: false);
    await tester.tap(find.byType(ChatVideoThumbnail), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(voice.isRead, isFalse);
    expect(video.isRead, isFalse);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(Get.isRegistered<ChatLogic>(), isFalse);
    await _close(tester, null);
  });

  for (final dark in [false, true]) {
    testWidgets('custom Markdown shows the original body and table ($dark)',
        (tester) async {
      const body =
          '# 三公结果\n\n| 门 | 结果 |\n| --- | --- |\n| 3 | **三公** |\n\n尾部正文';
      final message = _message('custom-markdown', 1)
        ..contentType = MessageType.custom
        ..customElem = CustomElem(
          description: '列表里的简短摘要',
          data: jsonEncode({
            'customType': 2300,
            'data': jsonEncode({'markdown': body}),
          }),
        );
      await _mount(
          tester,
          SingleChildScrollView(
              child: ConversationPeekMessage(
            message: message,
            isGroupChat: true,
          )),
          dark: dark,
          preview: const Size(260, 420),
          textScale: 1.3);
      await tester.pumpAndSettle();
      expect(find.byType(ChatMarkdownText), findsOneWidget);
      expect(
          tester.widget<ChatMarkdownText>(find.byType(ChatMarkdownText)).text,
          body);
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('尾部正文', findRichText: true), findsOneWidget);
      expect(find.text('列表里的简短摘要', findRichText: true), findsNothing);
      expect(message.isRead, isFalse);
      expect(Get.isRegistered<ChatLogic>(), isFalse);
      await _close(tester, null);
    });

    testWidgets(
        'custom cards and relationship notices reuse chat views ($dark)',
        (tester) async {
      final cases = <(Map<String, dynamic>, Type)>[
        (
          {
            'customType': CustomMessageType.call,
            'data': {'type': 'audio', 'state': 'hangup', 'duration': 65}
          },
          ChatCallItemView
        ),
        (
          {'customType': CustomMessageType.deletedByFriend, 'data': {}},
          ChatFriendRelationshipAbnormalHintView
        ),
        (
          {
            'orderID': 'snapshot-order',
            'biz': 'transfer',
            'currency': 'USDT',
            'amount': '10',
            'status': 'done'
          },
          FundMessageCard
        ),
      ];
      for (final (payload, type) in cases) {
        final message = _message('known-custom', 1)
          ..contentType = MessageType.custom
          ..customElem =
              CustomElem(data: jsonEncode(payload), description: '摘要');
        await _mount(
            tester,
            ConversationPeekMessage(
              message: message,
              isGroupChat: false,
              peerName: '小林',
            ),
            dark: dark,
            preview: const Size(340, 420));
        await tester.pumpAndSettle();
        expect(find.byType(type), findsOneWidget);
        if (type == FundMessageCard) {
          expect(
              tester.widget<FundMessageCard>(find.byType(type)).statusResolved,
              isFalse);
        }
        if (type == ChatFriendRelationshipAbnormalHintView) {
          final view = tester.widget<ChatFriendRelationshipAbnormalHintView>(
              find.byType(type));
          expect(view.name, '小林');
          expect(view.onTap, isNull);
        }
        expect(find.text('摘要', findRichText: true), findsNothing);
        expect(message.isRead, isFalse);
        await _close(tester, null);
      }
    });
  }

  testWidgets(
      'unknown custom formats retain payload and assistant cards show details',
      (tester) async {
    for (final (data, description, visible) in [
      ('未知正文\n第二行', '摘要', '未知正文\n第二行'),
      ('{"customType":999999,"result":[1,2]}', '摘要', '"result"'),
      ('{broken payload', '摘要', '{broken payload'),
      ('{"prompt":"绘制一座山"}', 'image', '绘制一座山'),
      ('{"groupName":"项目讨论"}', 'groupCard', '项目讨论'),
    ]) {
      final message = _message('fallback', 1)
        ..contentType = MessageType.custom
        ..customElem = CustomElem(data: data, description: description);
      await _mount(
          tester,
          SingleChildScrollView(
              child: ConversationPeekMessage(
            message: message,
            isGroupChat: false,
          )),
          preview: const Size(340, 420));
      await tester.pumpAndSettle();
      expect(find.textContaining(visible, findRichText: true), findsWidgets);
      expect(find.text(StrRes.unsupportedMessage, findRichText: true),
          findsNothing);
      await _close(tester, null);
    }
  });

  for (final dark in [false, true]) {
    testWidgets('small previews and large text keep message bounds ($dark)',
        (tester) async {
      final message =
          _message('long', 1, text: List.filled(18, '这是一个用于预览的长消息').join(' '));
      final video = _message('video', 2)
        ..contentType = MessageType.video
        ..videoElem = VideoElem(snapshotWidth: 640, snapshotHeight: 480);
      await _mount(
          tester,
          SingleChildScrollView(
            child: Column(children: [
              ConversationPeekMessage(message: message, isGroupChat: true),
              ConversationPeekMessage(message: video, isGroupChat: true),
            ]),
          ),
          dark: dark,
          size: const Size(320, 568),
          preview: const Size(260, 260),
          textScale: 1.8);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ConversationPeekMessage), findsNWidgets(2));
      final surface = tester.getRect(find.byType(SingleChildScrollView));
      final bubble = tester.getRect(find.byType(ChatBubble).first);
      expect(bubble.left, greaterThanOrEqualTo(surface.left));
      expect(bubble.right, lessThanOrEqualTo(surface.right));
      expect(message.isRead, isFalse);
      await _close(tester, null);
    });
  }
}
