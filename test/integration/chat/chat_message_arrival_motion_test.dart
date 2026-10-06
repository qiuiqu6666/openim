import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/chat_view.dart';
import 'package:openim/pages/chat/history/chat_history_prefetcher.dart';
import 'package:openim/pages/chat/messages/arrival/chat_message_arrival_animations.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/group_features/data/group_feature_runtime.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../support/chat/chat_entry_sdk.dart';

const _step = Duration(milliseconds: 80);
const _duration = Duration(milliseconds: 240);
// Flutter's interpolation reaches value 1 at the boundary, then reports
// completed on the next tick. Advance past it before measuring the full frame.
const _completionTick = Duration(milliseconds: 1);
const _historyCount = 80;

Message _message(String id, int sequence,
        {bool incoming = false, bool tall = false}) =>
    Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': incoming ? 'peer' : 'self',
      'recvID': incoming ? 'self' : 'peer',
      'senderNickname': incoming ? 'Peer' : 'Self',
      'seq': sequence,
      'sendTime': 1700000000000 + sequence * 1000,
      'status': MessageStatus.succeeded,
      'isRead': false,
      'textElem': {
        'content': tall
            ? List.generate(6, (index) => '$id line ${index + 1}').join('\n')
            : id,
      },
    });

Message _historyMessage(int index) => _message('history-$index', index + 1);

Finder _item(String id) => find.byWidgetPredicate(
    (widget) => widget is ChatItemView && widget.message.clientMsgID == id,
    skipOffstage: false);

Finder _arrival(String id) => find.byWidgetPredicate(
    (widget) =>
        widget is ChatMessageArrivalTransition && widget.messageID == id,
    // The entrance starts at zero extent, before the sliver can paint the row.
    skipOffstage: false);

Rect _rowRect(WidgetTester tester, String id) {
  final transition = _arrival(id);
  return tester
      .getRect(transition.evaluate().isEmpty ? _item(id) : transition.first);
}

Rect _bubbleRect(WidgetTester tester, String id) =>
    tester.getRect(find.descendant(
        of: _item(id),
        matching: find.byType(ChatItemContainer, skipOffstage: false),
        skipOffstage: false));

double _progress(WidgetTester tester, String id) {
  final transition = _arrival(id);
  if (transition.evaluate().isEmpty) return 1;
  return tester
      .widget<ChatMessageArrivalTransition>(transition)
      .animation
      .value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late EntryTestIM im;
  late ChatLogic logic;
  late List<EntryHistoryCall> histories;
  late List<String?> capturedReadTargets;
  late List<({String method, String? target, List<String> ids})> nativeReads;
  late StreamSubscription<dynamic> readSubscription;
  late bool opened;
  late GlobalKey previewKey;

  setUp(() async {
    Get.testMode = true;
    final previousInterval =
        VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(() => VisibilityDetectorController.instance.updateInterval =
        previousInterval);
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await SpUtil().init();
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    GroupFeatureRuntime.reset();
    Get.put<AppController>(EntryTestApp());
    im = Get.put<IMController>(EntryTestIM()) as EntryTestIM;
    Get.put<ConversationLogic>(EntryTestConversation());
    Get.put<CacheController>(EntryTestCache());
    histories = [];
    capturedReadTargets = [];
    nativeReads = [];
    opened = false;
    previewKey = GlobalKey();
    readSubscription = im.conversationReadRequestSubject
        .listen((request) => capturedReadTargets.add(request.messageID));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      if (call.method == 'getAdvancedHistoryMessageList') {
        final history =
            EntryHistoryCall(Map<String, dynamic>.from(call.arguments as Map));
        histories.add(history);
        return history.result.future;
      }
      if (call.method == 'getBlacklist') return '[]';
      if (call.method == 'markConversationMessageAsRead' ||
          call.method == 'markMessagesAsReadByMsgID') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        // Conversation reads have no message IDs in the native payload. The
        // real neutral request captures their target immediately before SDK IO.
        nativeReads.add((
          method: call.method,
          target: capturedReadTargets.isEmpty ? null : capturedReadTargets.last,
          ids: (args['messageIDList'] as List?)?.cast<String>() ?? [],
        ));
        return null;
      }
      if ({'changeInputStates', 'setConversationDraft'}.contains(call.method)) {
        return null;
      }
      throw StateError('Unexpected native call ${call.method}');
    });
  });

  tearDown(() async {
    if (opened && !logic.isClosed) logic.onDelete();
    for (final history in histories) {
      history.complete([]);
    }
    await readSubscription.cancel();
    GroupFeatureRuntime.reset();
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
  });

  Future<void> withChat(WidgetTester tester, Future<void> Function() check,
      {Brightness brightness = Brightness.light,
      int historyCount = _historyCount}) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // Match the actual GetMaterialApp home route when the owned chat callbacks
    // capture route identity, including the production visibility-read guard.
    Get.routing.current = '/';
    Get.routing.args = {
      'conversationInfo': ConversationInfo(
        conversationID: 'chat',
        userID: 'peer',
        conversationType: ConversationType.single,
        showName: 'Peer',
        unreadCount: 0,
        groupAtType: GroupAtType.atNormal,
        latestMsg: historyCount == 0 ? null : _historyMessage(historyCount - 1),
      ),
    };
    logic = Get.put<ChatLogic>(ChatLogic(), tag: GetTags.chat);
    opened = true;
    await tester.idle();
    expect(histories, hasLength(1));
    histories.single.complete(List.generate(historyCount, _historyMessage));
    try {
      await tester.pumpWidget(RepaintBoundary(
          key: previewKey,
          child: ScreenUtilInit(
              designSize: const Size(375, 812),
              builder: (_, __) => GetMaterialApp(
                    translations: TranslationService(),
                    locale: const Locale('zh', 'CN'),
                    theme: ThemeData(
                        brightness: brightness,
                        platform: TargetPlatform.android),
                    home: ChatPage(),
                  ))));
      await tester.pumpAndSettle();
      expect(find.byType(ChatPage), findsOneWidget);
      expect(find.byType(ChatListView), findsOneWidget);
      expect(logic.initialHistoryLoading.value, isFalse);
      expect(logic.newMessages.awayFromLatest.value, isFalse);
      expect(find.byType(ChatMessageArrivalTransition), findsNothing,
          reason: 'SDK history is already fully painted without an entrance.');
      capturedReadTargets.clear();
      nativeReads.clear();
      await check();
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!logic.isClosed) logic.onDelete();
      await tester.pump();
    }
  }

  bool nativeReadContains(String id) =>
      nativeReads.any((call) => call.target == id || call.ids.contains(id));

  void expectNotRead(String id) {
    expect(nativeReadContains(id), isFalse);
    expect(logic.messageList.firstWhere((m) => m.clientMsgID == id).isRead,
        isNot(true));
  }

  void expectArrivalOrder(WidgetTester tester, String older, String newer) {
    final olderPaint = tester.getRect(_item(older));
    final newerPaint = tester.getRect(_item(newer));
    expect(newerPaint.top, greaterThanOrEqualTo(olderPaint.bottom - .5),
        reason: 'Whole arriving rows must keep their order without overlap.');
  }

  Future<void> exportFrame(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('EXPORT_CHAT_ARRIVAL_PREVIEWS')) return;
    await tester.runAsync(() async {
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(previewKey));
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final folder = Directory('build/chat-message-arrival-preview-20261006');
        await folder.create(recursive: true);
        await File('${folder.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  for (final brightness in Brightness.values) {
    for (final tall in [false, true]) {
      testWidgets(
          'a real ${tall ? 'multiline' : 'short'} arrival slides from below the viewport and lifts the '
          'previous bubble before being read in $brightness', (tester) async {
        await withChat(tester, () async {
          const previousID = 'history-79';
          final before = _bubbleRect(tester, previousID);
          final incoming = _message('entering-${brightness.name}-$tall', 81,
              incoming: true, tall: tall);
          final id = incoming.clientMsgID!;
          im.recvNewMessage(incoming);
          expect(logic.messageArrivals.isEntering(id), isTrue,
              reason: 'The active latest route should admit a live arrival: '
                  'route=${logic.messageRoute?.isCurrent}, '
                  'away=${logic.newMessages.awayFromLatest.value}, '
                  'scrolling=${logic.scrollController.position.isScrollingNotifier.value}');
          await tester.pump();
          expect(_arrival(id), findsOneWidget);
          final bubbleElement = tester.element(_item(id));
          final start = _rowRect(tester, id);
          final startBubble = _bubbleRect(tester, id);
          final viewport = tester.getRect(find.byType(ChatListView));
          final previousStart = _bubbleRect(tester, previousID);
          expect(start.height, closeTo(0, 1));
          expect(previousStart.top, closeTo(before.top, 1));
          expect(previousStart.bottom, closeTo(before.bottom, 1));
          expect(startBubble.top, greaterThanOrEqualTo(viewport.bottom));
          expect(startBubble.height, greaterThan(0),
              reason: 'The whole bubble starts outside, without scaling.');
          expect(_progress(tester, id), 0);
          expectNotRead(id);
          if (brightness == Brightness.light && !tall) {
            await exportFrame(tester, 'incoming-000ms');
          }

          await tester.pump(_step);
          final early = _rowRect(tester, id);
          final previousEarly = _bubbleRect(tester, previousID);
          final earlyBubble = _bubbleRect(tester, id);
          expect(early.height, greaterThan(start.height + 1));
          expect(previousEarly.top, lessThan(previousStart.top - 1));
          expect(previousEarly.bottom, lessThan(previousStart.bottom - 1));
          expect(earlyBubble.top, lessThan(startBubble.top));
          expect(earlyBubble.top, lessThan(viewport.bottom));
          expect(earlyBubble.bottom, greaterThan(viewport.bottom));
          expect(earlyBubble.height, closeTo(startBubble.height, .01));
          expectNotRead(id);
          if (brightness == Brightness.light && !tall) {
            await exportFrame(tester, 'incoming-080ms');
          }

          await tester.pump(_step);
          final later = _rowRect(tester, id);
          final previousLater = _bubbleRect(tester, previousID);
          expect(later.height, greaterThan(early.height + .1));
          expect(previousLater.top, lessThan(previousEarly.top - .1));
          expect(previousLater.bottom, lessThan(previousEarly.bottom - .1));
          final laterBubble = _bubbleRect(tester, id);
          expect(laterBubble.top, lessThan(earlyBubble.top));
          expect(laterBubble.height, closeTo(startBubble.height, .01));
          expectNotRead(id);
          if (brightness == Brightness.light && !tall) {
            await exportFrame(tester, 'incoming-160ms');
          }

          await tester.pump(_step);
          await tester.pump(_completionTick);
          await tester.pump();
          final complete = _rowRect(tester, id);
          final previousComplete = _bubbleRect(tester, previousID);
          expect(complete.height, greaterThan(later.height + .01));
          expect(previousComplete.top, lessThan(previousLater.top - .01));
          expect(previousComplete.bottom, lessThan(previousLater.bottom - .01));
          final completeBubble = _bubbleRect(tester, id);
          expect(completeBubble.top, lessThan(laterBubble.top));
          expect(
              completeBubble.bottom, lessThanOrEqualTo(viewport.bottom + .5));
          expect(completeBubble.height, closeTo(startBubble.height, .01));
          expect(_progress(tester, id), 1);
          expect(tester.element(_item(id)), same(bubbleElement),
              reason: 'Completing entrance must preserve the bubble subtree.');
          expect(nativeReadContains(id), isTrue);
          if (brightness == Brightness.light && !tall) {
            await exportFrame(tester, 'incoming-241ms');
          }
          await tester.pump(_step);
          expect(_rowRect(tester, id).height, closeTo(complete.height, .01));
          expect(logic.newMessages.awayFromLatest.value, isFalse);
          expect(logic.scrollController.offset,
              closeTo(logic.scrollController.position.minScrollExtent, 1));
        }, brightness: brightness);
      });
    }
  }

  for (final historyCount in [0, 1]) {
    testWidgets('a $historyCount-row short chat enters from the viewport edge',
        (tester) async {
      await withChat(tester, () async {
        final viewport = tester.getRect(find.byType(ChatListView));
        final previous =
            historyCount == 0 ? null : _bubbleRect(tester, 'history-0');
        final id = 'short-chat-$historyCount';
        im.recvNewMessage(_message(id, historyCount + 1, incoming: true));
        expect(logic.messageArrivals.isEntering(id), isTrue);
        await tester.pump();
        final start = _bubbleRect(tester, id);
        expect(start.top, greaterThanOrEqualTo(viewport.bottom));
        expectNotRead(id);
        await tester.pump(_step);
        final early = _bubbleRect(tester, id);
        expect(early.top, lessThan(start.top));
        expect(early.height, closeTo(start.height, .01));
        expectNotRead(id);
        await tester.pump(_step);
        final later = _bubbleRect(tester, id);
        expect(later.top, lessThan(early.top));
        expectNotRead(id);
        await tester.pump(_step + _completionTick);
        await tester.pump();
        final complete = _bubbleRect(tester, id);
        expect(complete.top, lessThan(later.top));
        expect(complete.top, lessThan(viewport.center.dy),
            reason: 'Short conversations preserve their existing top layout.');
        expect(complete.height, closeTo(start.height, .01));
        if (previous != null) {
          final after = _bubbleRect(tester, 'history-0');
          expect(after.top, closeTo(previous.top, .01));
          expect(after.bottom, closeTo(previous.bottom, .01));
        }
        expect(nativeReadContains(id), isTrue);
      }, historyCount: historyCount);
    });
  }

  testWidgets('a real receipt refresh never replays a completed arrival',
      (tester) async {
    await withChat(tester, () async {
      const id = 'arrival-before-receipt';
      im.recvNewMessage(_message(id, 81, incoming: true));
      await tester.pump();
      await tester.pump(_duration);
      await tester.pump(_completionTick);
      await tester.pump();
      final complete = _rowRect(tester, id);
      expect(_progress(tester, id), 1);
      im.recvC2CMessageReadReceipt([
        ReadReceiptInfo(userID: 'peer', msgIDList: ['history-79']),
      ]);
      await tester.pump();
      await tester.pump();
      expect(
          logic.messageList
              .firstWhere((m) => m.clientMsgID == 'history-79')
              .isRead,
          isTrue);
      expect(_rowRect(tester, id).height, closeTo(complete.height, .01));
      expect(_progress(tester, id), 1);
      await tester.pump(_step);
      expect(_rowRect(tester, id).height, closeTo(complete.height, .01));
    });
  });

  testWidgets('same-frame SDK batch enters each new row once', (tester) async {
    await withChat(tester, () async {
      const first = 'batch-first', second = 'batch-second';
      im.recvNewMessage(_message(first, 81, incoming: true));
      im.recvNewMessage(_message(second, 82, incoming: true, tall: true));
      await tester.pump();
      expect(_arrival(first), findsOneWidget);
      expect(_arrival(second), findsOneWidget);
      expect(_rowRect(tester, first).height, closeTo(0, 1));
      expect(_rowRect(tester, second).height, closeTo(0, 1));
      expectArrivalOrder(tester, first, second);
      await tester.pump(_step);
      final firstEarly = _rowRect(tester, first).height;
      final secondEarly = _rowRect(tester, second).height;
      expect(firstEarly, greaterThan(0));
      expect(secondEarly, greaterThan(firstEarly));
      expectArrivalOrder(tester, first, second);
      expectNotRead(first);
      expectNotRead(second);
      await tester.pump(_step);
      expect(_rowRect(tester, first).height, greaterThan(firstEarly));
      expect(_rowRect(tester, second).height, greaterThan(secondEarly));
      expectArrivalOrder(tester, first, second);
      expectNotRead(second);
      await tester.pump(_step);
      await tester.pump(_completionTick);
      await tester.pump();
      expect(_progress(tester, first), 1);
      expect(_progress(tester, second), 1);
      expectArrivalOrder(tester, first, second);
      expect(nativeReadContains(second), isTrue);
      expect(
          logic.messageList.where((m) => m.clientMsgID == first), hasLength(1));
      expect(logic.messageList.where((m) => m.clientMsgID == second),
          hasLength(1));
    });
  });

  testWidgets('a second arrival keeps the first row animation and progress',
      (tester) async {
    await withChat(tester, () async {
      const first = 'overlap-first', second = 'overlap-second';
      im.recvNewMessage(_message(first, 81, incoming: true));
      await tester.pump();
      await tester.pump(_step);
      final animation = tester
          .widget<ChatMessageArrivalTransition>(_arrival(first))
          .animation;
      final firstProgress = animation.value;
      final firstHeight = _rowRect(tester, first).height;
      im.recvNewMessage(_message(second, 82, incoming: true));
      await tester.pump();
      expect(
          tester
              .widget<ChatMessageArrivalTransition>(_arrival(first))
              .animation,
          same(animation));
      expect(animation.value, closeTo(firstProgress, .001));
      expect(_rowRect(tester, first).height, closeTo(firstHeight, .01));
      expect(_rowRect(tester, second).height, closeTo(0, 1));
      expectArrivalOrder(tester, first, second);
      await tester.pump(_step);
      expect(animation.value, greaterThan(firstProgress));
      expect(_rowRect(tester, first).height, greaterThan(firstHeight));
      expectArrivalOrder(tester, first, second);
      expectNotRead(second);
      await tester.pump(_step);
      await tester.pump(_completionTick);
      await tester.pump();
      final firstComplete = _rowRect(tester, first).height;
      expect(_progress(tester, first), 1);
      expect(_progress(tester, second), lessThan(1));
      expectArrivalOrder(tester, first, second);
      expectNotRead(second);
      await tester.pump(_step);
      await tester.pump(_completionTick);
      await tester.pump();
      expect(_rowRect(tester, first).height, closeTo(firstComplete, .01));
      expect(_progress(tester, second), 1);
      expectArrivalOrder(tester, first, second);
      expect(nativeReadContains(second), isTrue);
    });
  });

  testWidgets('an offscreen arrival preserves the historical reader position',
      (tester) async {
    await withChat(tester, () async {
      logic.scrollController.jumpTo(900);
      await tester.pumpAndSettle();
      expect(logic.newMessages.awayFromLatest.value, isTrue);
      final viewport = tester.getRect(find.byType(ChatListView));
      final anchor = tester
          .widgetList<ChatItemView>(find.byType(ChatItemView))
          .firstWhere((item) {
            final rect = tester.getRect(_item(item.message.clientMsgID!));
            return rect.top > viewport.top && rect.bottom < viewport.bottom;
          })
          .message
          .clientMsgID!;
      final before = _bubbleRect(tester, anchor);
      final beforeOffset = logic.scrollController.offset;
      const id = 'historical-offscreen-arrival';
      final incoming = _message(id, 81, incoming: true, tall: true);
      im.recvNewMessage(incoming);
      im.recvNewMessage(incoming);
      await tester.pump();
      await tester.pump(_duration);
      expect(logic.messageArrivals.isEntering(id), isFalse);
      expect(_arrival(id), findsNothing);
      expect(_bubbleRect(tester, anchor).top, closeTo(before.top, .01));
      expect(_bubbleRect(tester, anchor).bottom, closeTo(before.bottom, .01));
      expect(logic.scrollController.offset, closeTo(beforeOffset, .01));
      expect(logic.newMessages.unseenCount.value, 1);
      expectNotRead(id);
      logic.scrollBottom(smooth: false);
      await tester.pumpAndSettle();
      expect(_arrival(id), findsNothing,
          reason: 'Returning to a previously received row must not replay it.');
      expect(_rowRect(tester, id).height, greaterThan(0));
      expect(_progress(tester, id), 1);
      expect(logic.newMessages.awayFromLatest.value, isFalse);
      expect(nativeReadContains(id), isTrue);
    });
  });

  testWidgets('platform reduced motion paints the incoming row immediately',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await withChat(tester, () async {
      expect(
          MediaQuery.disableAnimationsOf(
              tester.element(find.byType(ChatListView))),
          isTrue);
      const id = 'reduced-motion-arrival';
      im.recvNewMessage(_message(id, 81, incoming: true, tall: true));
      await tester.pump();
      final complete = _rowRect(tester, id).height;
      expect(complete, greaterThan(0));
      expect(_arrival(id), findsNothing);
      expect(_progress(tester, id), 1);
      await tester.pump();
      expect(nativeReadContains(id), isTrue);
      await tester.pump(_step);
      expect(_rowRect(tester, id).height, closeTo(complete, .01));
    });
  });

  testWidgets('self delivery and peer typing never enter the arrival motion',
      (tester) async {
    await withChat(tester, () async {
      const id = 'self-sdk-delivery';
      im.recvNewMessage(_message(id, 81));
      await tester.pump();
      final complete = _rowRect(tester, id).height;
      expect(complete, greaterThan(0));
      expect(_arrival(id), findsNothing);
      im.recvNewMessage(Message.fromJson({
        'clientMsgID': 'peer-typing',
        'contentType': MessageType.typing,
        'sessionType': ConversationType.single,
        'sendID': 'peer',
        'recvID': 'self',
        'typingElem': {'msgTips': 'yes'},
      }));
      await tester.pump();
      expect(logic.peerTyping.value, isTrue);
      expect(logic.messageList.any((m) => m.clientMsgID == 'peer-typing'),
          isFalse);
      expect(find.byType(ChatMessageArrivalTransition), findsNothing);
      await tester.pump(_step);
      expect(_rowRect(tester, id).height, closeTo(complete, .01));
    });
  });

  testWidgets('a real drag cancels entrance without reading or moving back',
      (tester) async {
    await withChat(tester, () async {
      const id = 'drag-cancel-arrival';
      im.recvNewMessage(_message(id, 81, incoming: true));
      await tester.pump();
      await tester.pump(_step);
      final animation = tester
          .widget<ChatMessageArrivalTransition>(_arrival(id))
          .animation as AnimationController;
      expect(animation.isAnimating, isTrue);
      expect(_progress(tester, id), inExclusiveRange(0, 1));
      expectNotRead(id);

      final viewport = tester.getRect(find.byType(ChatListView));
      final gesture = await tester.startGesture(viewport.center);
      try {
        // Send real pointer events through the production Scrollable, rather
        // than calling cancel() or manufacturing a ScrollStartNotification.
        await gesture.moveBy(const Offset(0, 24));
        await gesture.moveBy(Offset(0, viewport.height * .4));
        await tester.pump();
        await tester.pump();
        expect(animation.isAnimating, isFalse);
        expect(animation.value, 1);
        expect(logic.messageArrivals.isEntering(id), isFalse);
        expect(logic.newMessages.awayFromLatest.value, isTrue);
        expectNotRead(id);

        final anchor = tester
            .widgetList<ChatItemView>(find.byType(ChatItemView))
            .firstWhere((item) {
              final rect = tester.getRect(_item(item.message.clientMsgID!));
              return rect.top > viewport.top && rect.bottom < viewport.bottom;
            })
            .message
            .clientMsgID!;
        final reader = _bubbleRect(tester, anchor);
        final offset = logic.scrollController.offset;
        // Keep the pointer held so any later shift comes from stale entrance
        // work, rather than an intentional user fling or ballistic scrolling.
        await tester.pump(_duration + _completionTick);
        await tester.pump();
        expect(_bubbleRect(tester, anchor).top, closeTo(reader.top, .01));
        expect(_bubbleRect(tester, anchor).bottom, closeTo(reader.bottom, .01));
        expect(logic.scrollController.offset, closeTo(offset, .01));
        expect(animation.isAnimating, isFalse);
        expectNotRead(id);
      } finally {
        await gesture.up();
      }
      await tester.pumpAndSettle();
      expectNotRead(id);
      logic.scrollBottom(smooth: false);
      await tester.pumpAndSettle();
      expect(logic.messageArrivals.isEntering(id), isFalse);
      expect(_progress(tester, id), 1);
      expect(nativeReadContains(id), isTrue,
          reason: 'The cancelled read barrier must permit a later full view.');
    });
  });

  testWidgets('reducing motion mid-entrance reads only the full painted row',
      (tester) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await withChat(tester, () async {
      const id = 'reduce-during-arrival';
      im.recvNewMessage(_message(id, 81, incoming: true, tall: true));
      await tester.pump();
      await tester.pump(_step);
      final animation = tester
          .widget<ChatMessageArrivalTransition>(_arrival(id))
          .animation as AnimationController;
      final fullHeight = tester.getSize(_item(id)).height;
      expect(_rowRect(tester, id).height, lessThan(fullHeight));
      expectNotRead(id);
      final heightsAtRead = <double>[];
      final subscription = im.conversationReadRequestSubject.listen((request) {
        if (request.messageID == id) {
          final row =
              _arrival(id).evaluate().single.findRenderObject() as RenderBox;
          heightsAtRead.add(row.size.height);
        }
      });
      addTearDown(subscription.cancel);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pump();
      expect(_rowRect(tester, id).height, closeTo(fullHeight, .01));
      expect(_progress(tester, id), 1);
      expect(animation.isAnimating, isFalse);
      await tester.pump();
      expect(logic.messageArrivals.isEntering(id), isFalse);
      expect(nativeReadContains(id), isTrue);
      expect(heightsAtRead, isNotEmpty);
      for (final height in heightsAtRead) {
        expect(height, closeTo(fullHeight, .01),
            reason: 'Native reads must follow the fully expanded painted row.');
      }
      await tester.pump(_duration + _completionTick);
      await tester.pump();
      expect(_rowRect(tester, id).height, closeTo(fullHeight, .01));
      expect(animation.isAnimating, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  testWidgets('a self latest cannot clear an earlier partial incoming row',
      (tester) async {
    await withChat(tester, () async {
      const incomingID = 'incoming-before-self', selfID = 'self-after-incoming';
      im.recvNewMessage(_message(incomingID, 81, incoming: true));
      await tester.pump();
      await tester.pump(_step);
      expect(_progress(tester, incomingID), inExclusiveRange(0, 1));
      expect(nativeReads, isEmpty);

      im.recvNewMessage(_message(selfID, 82));
      await tester.pump();
      expect(logic.messageList.last.clientMsgID, selfID);
      expect(_arrival(selfID), findsNothing);
      expect(_rowRect(tester, selfID).height, greaterThan(0));
      expect(nativeReads, isEmpty,
          reason: 'A fully visible self row cannot read the partial peer row.');
      expectNotRead(incomingID);
      await tester.pump(_step);
      expect(nativeReads, isEmpty);
      expectNotRead(incomingID);
      await tester.pump(_step);
      expect(nativeReads, isEmpty);
      await tester.pump(_completionTick);
      await tester.pump();
      expect(_progress(tester, incomingID), 1);
      expect(logic.messageArrivals.isEntering(incomingID), isFalse);
      expect(nativeReadContains(selfID), isTrue,
          reason:
              'The normal viewport read resumes after the peer row paints.');
      expect(
          logic.messageList
              .firstWhere((m) => m.clientMsgID == incomingID)
              .isRead,
          isTrue);
    });
  });

  testWidgets('a burst beyond the animation limit cannot read partial rows',
      (tester) async {
    await withChat(tester, () async {
      final ids = List.generate(17, (index) => 'burst-${index + 1}');
      for (var index = 0; index < ids.length; index++) {
        im.recvNewMessage(_message(ids[index], 81 + index, incoming: true));
      }
      await tester.pump();
      expect(logic.messageList.last.clientMsgID, ids.last);
      expect(ids.where(logic.messageArrivals.isEntering), hasLength(16));
      expect(_arrival(ids.last), findsNothing);
      expect(_rowRect(tester, ids.last).height, greaterThan(0));
      expect(nativeReads, isEmpty,
          reason: 'The plain overflow row still shares the conversation gate.');
      await tester.pump(_step);
      expect(nativeReads, isEmpty);
      await tester.pump(_step);
      expect(nativeReads, isEmpty);
      await tester.pump(_step);
      expect(nativeReads, isEmpty);
      await tester.pump(_completionTick);
      await tester.pumpAndSettle();
      expect(ids.any(logic.messageArrivals.isEntering), isFalse);
      expect(nativeReadContains(ids.last), isTrue);
    });
  });
}
