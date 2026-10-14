import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/history/chat_history_prefetcher.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/updates/conversation_latest_sync.dart';
import 'package:openim/pages/conversation/unread/conversation_unread_sync.dart';
import 'package:openim/pages/group_features/data/group_feature_runtime.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/chat/chat_entry_list.dart';
import '../../support/chat/chat_entry_sdk.dart';

class _FirstPageHome extends GetxController implements HomeLogic {
  _FirstPageHome(this.conversationsAtFirstPage);

  @override
  final List<ConversationInfo> conversationsAtFirstPage;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Message _message(String id, int sequence, {bool incoming = true}) =>
    Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': incoming ? 'peer' : 'self',
      'recvID': incoming ? 'self' : 'peer',
      'seq': sequence,
      'sendTime': sequence,
      'status': MessageStatus.succeeded,
      'textElem': {'content': id},
    });

ConversationInfo _conversation(Message latest,
        {int unread = 0, String id = 'chat'}) =>
    ConversationInfo(
      conversationID: id,
      userID: id == 'chat' ? 'peer' : 'other-peer',
      conversationType: ConversationType.single,
      showName: 'Peer',
      groupAtType: GroupAtType.atNormal,
      latestMsg: latest,
      latestMsgSendTime: latest.sendTime,
      draftTextTime: 0,
      unreadCount: unread,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late EntryTestIM im;
  late ConversationLogic conversations;
  late ChatLogic chat;
  late List<EntryHistoryCall> histories;
  late List<MethodCall> nativeReads;
  late List<Completer<void>> acknowledgements;
  late List<List<String>> paintedIDs;
  late bool chatOpened;
  late Map<String, ConversationInfo> storedRows;
  late List<String> calls;
  late List<MethodCall> recoveryReads;
  late Completer<void> recoveryResult;

  int unreadSource() => conversations.list
      .fold(0, (total, row) => total + conversations.getUnreadCount(row));

  Widget badgeSource() => Directionality(
      textDirection: TextDirection.ltr,
      child: Obx(() => Text('unread-source:${unreadSource()}')));

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    GroupFeatureRuntime.reset();
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
    Get.put<AppController>(EntryTestApp());
    im = Get.put<IMController>(EntryTestIM()) as EntryTestIM;
    Get.put<CacheController>(EntryTestCache());
    final initial = _conversation(_message('history-29', 30, incoming: false));
    Get.put<HomeLogic>(_FirstPageHome([
      initial,
      _conversation(_message('other-unread', 1), id: 'other', unread: 7),
    ]));
    histories = [];
    nativeReads = [];
    acknowledgements = [];
    paintedIDs = [];
    chatOpened = false;
    storedRows = {
      for (final row in Get.find<HomeLogic>().conversationsAtFirstPage)
        row.conversationID: row,
    };
    calls = [];
    recoveryReads = [];
    recoveryResult = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) {
      calls.add(call.method);
      if (call.method == 'getAdvancedHistoryMessageList') {
        final history =
            EntryHistoryCall(Map<String, dynamic>.from(call.arguments as Map));
        histories.add(history);
        return history.result.future;
      }
      if (call.method == 'markConversationMessageAsRead') {
        nativeReads.add(call);
        final acknowledgement = Completer<void>();
        acknowledgements.add(acknowledgement);
        return acknowledgement.future;
      }
      if (call.method == 'markMessagesAsReadByMsgID') {
        recoveryReads.add(call);
        return recoveryResult.future;
      }
      if (call.method == 'getConversationIDBySessionType') {
        return Future.value('chat');
      }
      if (call.method == 'getConversationListSplit') {
        return Future.value(
            jsonEncode(storedRows.values.map((row) => row.toJson()).toList()));
      }
      if (call.method == 'getMultipleConversation') {
        final ids = (call.arguments as Map)['conversationIDList'] as List;
        return Future.value(jsonEncode([
          for (final id in ids)
            if (storedRows[id] != null) storedRows[id]!.toJson(),
        ]));
      }
      if (call.method == 'getBlacklist') return Future.value('[]');
      if (call.method == 'setConversationDraft') return Future.value();
      if (call.method == 'changeInputStates') return Future.value();
      throw StateError('Unexpected native call ${call.method}');
    });
  });

  tearDown(() async {
    if (chatOpened && !chat.isClosed) chat.onDelete();
    if (!conversations.isClosed) conversations.onDelete();
    if (!recoveryResult.isCompleted) recoveryResult.complete();
    for (final acknowledgement in acknowledgements) {
      if (!acknowledgement.isCompleted) acknowledgement.complete();
    }
    for (final history in histories) {
      history.complete([]);
    }
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    GroupFeatureRuntime.reset();
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
  });

  Future<void> mountChat(WidgetTester tester) async {
    // Initialize timer-owning subscriptions inside the widget test's clock.
    im.conversationChangedSubject.listen((rows) {
      for (final row in rows) {
        storedRows[row.conversationID] = row;
      }
    });
    conversations = Get.put<ConversationLogic>(ConversationLogic());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Get.routing.current = '/chat';
    // Keep route state independent from the list row to expose missing handoff.
    Get.routing.args = {
      'conversationInfo': ConversationInfo.fromJson(conversations.list
          .firstWhere((row) => row.conversationID == 'chat')
          .toJson()),
    };
    chat = ChatLogic(receiptNow: tester.binding.clock.now);
    chatOpened = true;
    chat.onInit();
    await tester.idle();
    expect(histories, hasLength(1));
    histories.single.complete(List.generate(
        30, (index) => _message('history-$index', index + 1, incoming: false)));
    await tester.pumpWidget(Stack(textDirection: TextDirection.ltr, children: [
      buildChatEntryList(chat,
          commonList: true,
          rowHeight: (message) =>
              message.clientMsgID == 'viewed-tall' ? 520 : 48,
          observeViewport: (ids, _) => paintedIDs.add(List.of(ids))),
      Positioned(top: 0, left: 0, child: badgeSource()),
    ]));
    await tester.pumpAndSettle();
    expect(nativeReads, isEmpty);
  }

  Future<void> receive(WidgetTester tester, Message message,
      {required int unread}) async {
    storedRows['chat'] = _conversation(message, unread: unread);
    im.conversationChanged([_conversation(message, unread: unread)]);
    im.recvNewMessage(message);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // The production feed coalesces metadata callbacks for 80 ms. Assert the
    // published row after that batch, while the read ACK is still pending.
    await tester.pump(const Duration(milliseconds: 80));
  }

  ConversationInfo getTarget() =>
      conversations.list.firstWhere((row) => row.conversationID == 'chat');

  for (final duplicateTotal in [false, true]) {
    testWidgets(
        'return reconciles increased unread after ACK, duplicate total: $duplicateTotal',
        (tester) async {
      await mountChat(tester);
      if (duplicateTotal) {
        im.unreadMsgCountEventSubject.add(7);
        await tester.pump();
        await tester.pump(ConversationUnreadSync.settleDelay);
        await tester.pumpAndSettle();
      }
      final latest = _message('viewed-tall', 31);
      await receive(tester, latest, unread: 1);
      expect(nativeReads, hasLength(1));
      Get.routing.current = '/home';
      chat.onDelete();
      await tester.pumpWidget(badgeSource());
      im.conversationChanged([_conversation(latest, unread: 2)]);
      await tester.pump(const Duration(milliseconds: 80));
      expect(getTarget().unreadCount, 2);
      acknowledgements.single.complete();
      await tester.pump();
      storedRows['chat'] = _conversation(latest, unread: 0);
      im.conversationChanged([_conversation(latest, unread: 0)]);
      if (duplicateTotal) im.unreadMsgCountEventSubject.add(7);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(ConversationLatestSync.settleDelay);
      await tester.pumpAndSettle();
      expect(calls, contains('getMultipleConversation'));
      expect(getTarget().unreadCount, 0);
      expect(recoveryReads, isEmpty);
    });
  }

  for (final newArrival in [false, true]) {
    testWidgets(
        'failed read after return recovers only captured IDs, new arrival: $newArrival',
        (tester) async {
      await mountChat(tester);
      final seen = _message('viewed-tall', 31);
      await receive(tester, seen, unread: 1);
      expect(paintedIDs.last, contains('viewed-tall'));
      Get.routing.current = '/home';
      chat.onDelete();
      await tester.pumpWidget(badgeSource());
      final latest = newArrival ? _message('unseen-after-exit', 32) : seen;
      if (newArrival) {
        im.conversationChanged([_conversation(latest, unread: 2)]);
        await tester.pump(const Duration(milliseconds: 80));
      }
      acknowledgements.single
          .completeError(PlatformException(code: 'NETWORK_FAILURE'));
      await tester.pump();
      await tester.pump();
      expect(recoveryReads, hasLength(1));
      expect((recoveryReads.single.arguments as Map)['messageIDList'],
          ['viewed-tall']);
      storedRows['chat'] = _conversation(latest, unread: newArrival ? 1 : 0);
      recoveryResult.complete();
      await tester.pumpAndSettle();
      await tester.pump(ConversationLatestSync.settleDelay);
      await tester.pumpAndSettle();
      expect(nativeReads, hasLength(1));
      expect(getTarget().unreadCount, newArrival ? 1 : 0);
      expect(getTarget().latestMsg!.clientMsgID, latest.clientMsgID);
    });
  }

  testWidgets(
      'received latest reaches the feed without a conversation callback',
      (tester) async {
    await mountChat(tester);
    final latest = _message('newest-without-metadata', 31);
    storedRows['chat'] = _conversation(latest, unread: 1);
    im.recvNewMessage(latest);
    await tester.pump();
    await tester.pump(ConversationLatestSync.settleDelay);
    await tester.pump();
    expect(calls, contains('getMultipleConversation'));
    expect(chat.messageList.last.clientMsgID, latest.clientMsgID);
    expect(getTarget().latestMsg!.clientMsgID, latest.clientMsgID);
    expect(getTarget().latestMsgSendTime, 31);
    expect(getTarget().unreadCount, 1);
    expect(conversations.getContent(getTarget()), 'newest-without-metadata');
    // A repeated viewport notification may still be waiting for the ordinary
    // single-chat read batch. Let its clock expire while the native ACK stays
    // pending, and verify it joins the existing read rather than sending twice.
    await tester.pump(const Duration(milliseconds: 250));
    expect(nativeReads, hasLength(1));
  });

  testWidgets(
      'leaving chat reconciles the persisted latest call without events',
      (tester) async {
    await mountChat(tester);
    final latest = _message('local-call', 0)
      ..sendTime = 31
      ..contentType = MessageType.custom
      ..customElem = CustomElem(
          data: jsonEncode({
        'customType': CustomMessageType.call,
        'data': {'type': 'audio', 'state': 'timeout', 'duration': 0},
      }));
    storedRows['chat'] = _conversation(latest);
    Get.routing.current = '/conversations';
    await tester.pumpWidget(badgeSource());
    chat.onDelete();
    await tester.pump();
    await tester.pump(ConversationLatestSync.settleDelay);
    await tester.pump();
    expect(calls, contains('getMultipleConversation'));
    expect(getTarget().latestMsg!.clientMsgID, 'local-call');
    expect(getTarget().latestMsgSendTime, 31);
    expect(conversations.getContent(getTarget()), contains(StrRes.callVoice));
    expect(getTarget().unreadCount, 0);
  });

  testWidgets('viewed tall inbound clears list unread after returning and ACK',
      (tester) async {
    await mountChat(tester);
    await receive(tester, _message('viewed-tall', 31), unread: 1);
    final viewport = tester.getRect(find.byType(ChatListView));
    final painted =
        tester.getRect(find.byKey(const ValueKey('viewed-tall')).first);
    expect(painted.height, greaterThan(viewport.height));
    expect(painted.overlaps(viewport), isTrue);
    expect(paintedIDs.last, contains('viewed-tall'));
    expect(nativeReads, hasLength(1));
    expect((nativeReads.single.arguments as Map)['conversationID'], 'chat');
    expect(getTarget().unreadCount, 1);
    expect(find.text('unread-source:8'), findsOneWidget);

    Get.routing.current = '/conversations';
    await tester.pumpWidget(badgeSource());
    chat.onDelete();
    acknowledgements.single.complete();
    await tester.pumpAndSettle();
    // There is deliberately no zero-unread ConversationChanged SDK event.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(getTarget().unreadCount, 0);
    expect(
        conversations.list
            .firstWhere((row) => row.conversationID == 'other')
            .unreadCount,
        7);
    expect(find.text('unread-source:7'), findsOneWidget);
    expect(nativeReads, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('GetX disposal flushes a painted read inside the batch window',
      (tester) async {
    await mountChat(tester);
    await receive(tester, _message('viewed-tall', 31), unread: 1);
    expect(nativeReads, hasLength(1));
    acknowledgements.single.complete();
    await tester.pump();

    final latest = _message('viewed-before-back', 32);
    await receive(tester, latest, unread: 1);
    expect(paintedIDs.last, contains(latest.clientMsgID));
    expect(nativeReads, hasLength(1),
        reason: 'The second painted target is waiting for the 250ms batch');

    Get.routing.current = '/conversations';
    chat.onDelete();
    await tester.pumpWidget(badgeSource());
    expect(chat.isClosed, isTrue);
    expect(nativeReads, hasLength(2),
        reason: 'Closing the real GetX controller must flush the seen target');
    storedRows['chat'] = _conversation(latest, unread: 0);
    acknowledgements.last.complete();
    await tester.pumpAndSettle();
    await tester.pump(ConversationLatestSync.settleDelay);
    await tester.pumpAndSettle();
    expect(getTarget().unreadCount, 0);

    final unseen = _message('unseen-after-back', 33);
    im.conversationChanged([_conversation(unseen, unread: 1)]);
    await tester.pump(const Duration(milliseconds: 80));
    expect(getTarget().unreadCount, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(nativeReads, hasLength(2));
  });

  testWidgets('new offscreen arrival survives earlier ACK and chat close',
      (tester) async {
    await mountChat(tester);
    await receive(tester, _message('viewed-tall', 31), unread: 1);
    expect(nativeReads, hasLength(1));
    chat.scrollController.jumpTo(700);
    await tester.pumpAndSettle();
    expect(chat.newMessages.awayFromLatest.value, isTrue);
    await receive(tester, _message('not-viewed', 32), unread: 2);
    expect(chat.messageList.last.clientMsgID, 'not-viewed');
    expect(paintedIDs.last, isNot(contains('not-viewed')));
    expect(nativeReads, hasLength(1));
    acknowledgements.single.complete();
    await tester.pumpAndSettle();
    expect(getTarget().latestMsg!.clientMsgID, 'not-viewed');
    expect(getTarget().unreadCount, 2);

    Get.routing.current = '/conversations';
    await tester.pumpWidget(badgeSource());
    chat.onDelete();
    await tester.pumpAndSettle();
    await tester.pump(ConversationLatestSync.settleDelay);
    await tester.pumpAndSettle();
    expect(nativeReads, hasLength(1));
    expect(getTarget().unreadCount, 2);
    expect(find.text('unread-source:9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('viewed seq-zero message clears delayed metadata after return',
      (tester) async {
    await mountChat(tester);
    final message = _message('viewed-tall', 0)..sendTime = 30;
    // Native timeline delivery precedes the conversation metadata callback.
    im.recvNewMessage(message);
    await tester.pump();
    await tester.pump();
    expect(paintedIDs.last, contains('viewed-tall'));
    expect(chat.conversationInfo.latestMsg!.clientMsgID, 'history-29');
    expect(nativeReads, hasLength(1));
    acknowledgements.single.complete();
    await tester.pumpAndSettle();
    Get.routing.current = '/conversations';
    await tester.pumpWidget(badgeSource());
    chat.onDelete();
    im.conversationChanged([_conversation(message, unread: 1)]);
    await tester.pumpAndSettle();
    expect(getTarget().latestMsg!.clientMsgID, 'viewed-tall');
    expect(getTarget().unreadCount, 0);
    expect(find.text('unread-source:7'), findsOneWidget);
    expect(nativeReads, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-time seq-zero unseen successor stays unread after return',
      (tester) async {
    await mountChat(tester);
    im.recvNewMessage(_message('viewed-tall', 0)..sendTime = 30);
    await tester.pump();
    await tester.pump();
    expect(paintedIDs.last, contains('viewed-tall'));
    expect(nativeReads, hasLength(1));
    acknowledgements.single.complete();
    await tester.pumpAndSettle();
    Get.routing.current = '/conversations';
    await tester.pumpWidget(badgeSource());
    chat.onDelete();
    final unseen = _message('unseen-after-return', 0)..sendTime = 30;
    im.conversationChanged([_conversation(unseen, unread: 1)]);
    await tester.pumpAndSettle();
    expect(getTarget().latestMsg!.clientMsgID, 'unseen-after-return');
    expect(getTarget().unreadCount, 1);
    expect(find.text('unread-source:8'), findsOneWidget);
    expect(nativeReads, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final inactive in ['covered route', 'inactive app']) {
    testWidgets('painted inbound is not acknowledged in $inactive',
        (tester) async {
      await mountChat(tester);
      if (inactive == 'covered route') {
        Get.routing.current = '/covered';
      } else {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      }
      await receive(tester, _message('viewed-tall', 31), unread: 1);
      if (inactive == 'covered route') {
        expect(paintedIDs.last, contains('viewed-tall'));
      } else {
        // The production viewport stops publishing visibility while inactive.
        expect(paintedIDs.last, isNot(contains('viewed-tall')));
      }
      expect(nativeReads, isEmpty);
      expect(getTarget().unreadCount, 1);
      Get.routing.current = '/chat';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      chat.scrollController.jumpTo(20);
      await tester.pump();
      // A tall row is read only once its bottom edge is back in the viewport.
      chat.scrollController.jumpTo(0);
      await tester.pump();
      // The resumed viewport can request a history catch-up before reading.
      for (final history in histories.skip(1)) {
        history.complete([
          ...List.generate(
              30,
              (index) =>
                  _message('history-$index', index + 1, incoming: false)),
          storedRows['chat']!.latestMsg!,
        ]);
      }
      await tester.pumpAndSettle();
      expect(nativeReads, hasLength(1));
      acknowledgements.single.complete();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(getTarget().unreadCount, 0);
      expect(find.text('unread-source:7'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
