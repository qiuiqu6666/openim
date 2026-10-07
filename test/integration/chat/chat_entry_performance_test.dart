import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/history/chat_history_prefetcher.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/chat/chat_entry_list.dart';
import '../../support/chat/chat_entry_sdk.dart';
import 'chat_new_message_cases.dart';
import 'chat_keyboard_scroll_cases.dart';

Message _entryMessage(String id, {int time = 1}) => Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': 'peer',
      'recvID': 'self',
      'seq': time,
      'sendTime': time,
      'status': MessageStatus.succeeded,
      'textElem': {'content': id},
    });

ConversationInfo _entryConversation(
        {String id = 'chat', bool private = false, Message? latest}) =>
    ConversationInfo(
      conversationID: id,
      userID: 'peer',
      conversationType: ConversationType.single,
      showName: 'Peer',
      unreadCount: 0,
      groupAtType: GroupAtType.atNormal,
      isPrivateChat: private,
      latestMsg: latest,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdkChannel = MethodChannel('flutter_openim_sdk');
  late EntryTestIM im;
  late List<EntryHistoryCall> calls;
  late List<ChatLogic> controllers;
  late List<Map<String, dynamic>> draftCalls;

  ChatLogic open([ConversationInfo? conversation]) {
    // Get.arguments reads Routing.args; invoking the real onInit here lets the
    // test inspect entry work before any route's first frame/onReady runs.
    Get.routing.args = {
      'conversationInfo': conversation ?? _entryConversation()
    };
    final logic = ChatLogic();
    controllers.add(logic);
    logic.onInit();
    return logic;
  }

  Future<ChatLogic> mountHistoryChat(WidgetTester tester,
      {ConversationInfo? conversation,
      bool commonList = false,
      bool showInput = false,
      double Function(Message)? rowHeight,
      void Function(List<String>, double)? observeViewport}) async {
    final logic = open(conversation);
    await tester.idle();
    calls.last.complete(List.generate(
        30, (index) => _entryMessage('history-$index', time: index + 1)));
    await tester.pumpWidget(buildChatEntryList(logic,
        commonList: commonList,
        showInput: showInput,
        rowHeight: rowHeight,
        observeViewport: observeViewport));
    await tester.pump();
    expect(logic.scrollController.hasClients, isTrue);
    expect(logic.scrollController.offset,
        logic.scrollController.position.minScrollExtent);
    return logic;
  }

  Future<void> scrollAway(WidgetTester tester, ChatLogic logic) async {
    logic.scrollController.jumpTo(160);
    await tester.pump();
    expect(logic.newMessages.awayFromLatest.value, isTrue);
  }

  setUp(() {
    Get.testMode = true;
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    calls = [];
    controllers = [];
    draftCalls = [];
    Get.put<AppController>(EntryTestApp());
    im = Get.put<IMController>(EntryTestIM()) as EntryTestIM;
    Get.put<ConversationLogic>(EntryTestConversation());
    Get.put<CacheController>(EntryTestCache());
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, (call) async {
      if (call.method == 'getAdvancedHistoryMessageList') {
        final history =
            EntryHistoryCall(Map<String, dynamic>.from(call.arguments as Map));
        calls.add(history);
        return history.result.future;
      }
      if (call.method == 'getBlacklist') return '[]';
      if (call.method == 'setConversationDraft') {
        draftCalls.add(Map<String, dynamic>.from(call.arguments as Map));
      }
      return null;
    });
  });

  tearDown(() async {
    ChatHistoryPrefetcher.shared.clear();
    for (final logic in controllers.reversed) {
      if (!logic.isClosed) logic.onDelete();
    }
    for (final call in calls) {
      call.complete([]);
    }
    ChatHistoryCache.clear();
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdkChannel, null);
  });

  testWidgets('large offline gap preserves the reader and exposes newer paging',
      (tester) async {
    final logic = await mountHistoryChat(tester, commonList: true);
    await scrollAway(tester, logic);
    final oldIDs = logic.messageList.map((m) => m.clientMsgID).toSet();
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    im.imSdkStatus(IMSdkStatus.syncStart);
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.idle();
    calls.last.complete(
        List.generate(40, (i) => _entryMessage('recovered-$i', time: 1000 + i)),
        isEnd: false);
    await tester.pump();
    await tester.pump();
    final retainedOld =
        logic.messageList.where((m) => oldIDs.contains(m.clientMsgID)).length;
    print(
        'RECOVERY_AUDIT scrolled-away=true old_rows_retained=$retainedOld rows=${logic.messageList.length} pending_arrival_count=${logic.newMessages.unseenCount.value} has_older=${logic.historyHasMore.value}');
    expect(retainedOld, 30);
    expect(logic.messageList.length, 30);
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.historyNewerHasMore.value, isTrue);
    expect(logic.viewingHistory.value, isTrue);
    expect(tester.takeException(), isNull);
    logic.onDelete();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('10000 arrivals retain only the latest automatic window',
      (tester) async {
    final logic = open();
    await tester.idle();
    calls.last.complete([_entryMessage('initial')]);
    await tester.pump();
    final watch = Stopwatch()..start();
    for (var i = 0; i < 10000; i++) {
      im.recvNewMessage(_entryMessage('burst-$i', time: i + 2));
    }
    print(
        'UX_AUDIT live route: ${logic.messageList.length} retained rows after 10000 arrivals; callback-only elapsed ${watch.elapsedMilliseconds} ms (no per-arrival frames)');
    expect(logic.messageList.length, 600);
    expect(logic.messageList.last.clientMsgID, 'burst-9999');
    expect(logic.historyHasMore.value, isTrue);
    logic.onDelete();
    await tester.pump(const Duration(milliseconds: 100));
  });
  testWidgets(
      '10000 arrivals while reading retain the anchor and bound the buffer',
      (tester) async {
    final logic = await mountHistoryChat(tester, commonList: true);
    await scrollAway(tester, logic);
    final oldIDs = logic.messageList.map((m) => m.clientMsgID).toSet();
    for (var i = 0; i < 10000; i++) {
      im.recvNewMessage(_entryMessage('away-$i', time: 1000 + i));
    }
    expect(logic.messageList.length, 600);
    expect(logic.scrollingCacheMessageList.length, 100);
    expect(logic.scrollingCacheMessageList.last.clientMsgID, 'away-9999');
    expect(
        logic.messageList.where((m) => oldIDs.contains(m.clientMsgID)).length,
        30);
    expect(logic.viewingHistory.value, isTrue);
    expect(logic.newMessages.unseenCount.value, 10000);
    await tester.pump();
    await tester.pump();
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    expect(logic.newMessages.unseenCount.value, 10000);
    expect(tester.takeException(), isNull);
    logic.onDelete();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('entry starts one history query before the first route frame',
      (tester) async {
    final logic = open();
    final first = logic.onScrollToBottomLoad();
    final second = logic.onScrollToBottomLoad();
    await tester.idle();

    expect(identical(first, second), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.arguments['conversationID'], 'chat');
    expect(calls.single.arguments['count'], 40);
    expect(calls.single.arguments['startClientMsgID'], '');
    expect(logic.initialHistoryLoading.value, isTrue);
    calls.single.complete([_entryMessage('history')]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(logic.messageList.single.clientMsgID, 'history');
    expect(logic.initialHistoryLoading.value, isFalse);
    expect(logic.historyError.value, isNull);
    expect(tester.takeException(), isNull);
    logic.onDelete();
  });

  testWidgets('live selection follows SDK deletion, recall and history clear',
      (tester) async {
    final logic = open();
    await tester.idle();
    final messages = [
      _entryMessage('selection-delete', time: 1),
      _entryMessage('selection-revoke', time: 2),
      _entryMessage('selection-keep', time: 3),
    ];
    calls.single.complete(messages);
    await tester.pump();
    logic.messageSelection.enter(messages.first);
    logic.messageSelection.toggleAll();
    expect(logic.messageSelection.count, 3);
    im.messageDeleted(messages.first);
    await tester.pump();
    expect(logic.messageSelection.count, 2);
    im.recvMessageRevoked(RevokedInfo(clientMsgID: 'selection-revoke'));
    await tester.pump();
    expect(logic.messageSelection.selectedMessages.single.clientMsgID,
        'selection-keep');
    logic.clearAllMessage();
    expect(logic.messageSelection.count, 0);
    expect(logic.messageSelection.allSelected, isFalse);
    logic.onDelete();
  });

  testWidgets('cache and latest seed show immediately and replace once',
      (tester) async {
    ChatHistoryCache.write('self', 'chat', [_entryMessage('cached')]);
    final latest = _entryMessage('latest', time: 2);
    final logic = open(_entryConversation(latest: latest));
    expect(logic.messageList.map((m) => m.clientMsgID), ['cached', 'latest']);
    final emissions = <List<String?>>[];
    final subscription = logic.messageList.listen(
        (rows) => emissions.add(rows.map((m) => m.clientMsgID).toList()));
    await tester.idle();
    calls.single.complete([_entryMessage('sdk'), latest]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(logic.messageList.map((m) => m.clientMsgID), ['sdk', 'latest']);
    expect(emissions, [
      ['sdk', 'latest']
    ]);
    await subscription.cancel();
    logic.onDelete();
  });

  testWidgets('private conversation ignores and removes cache and latest seed',
      (tester) async {
    ChatHistoryCache.write('self', 'chat', [_entryMessage('cached')]);
    final logic = open(_entryConversation(
        private: true, latest: _entryMessage('latest', time: 2)));
    expect(logic.messageList, isEmpty);
    expect(ChatHistoryCache.read('self', 'chat'), isEmpty);
    await tester.idle();
    expect(calls, hasLength(1));
    calls.single.complete([_entryMessage('fresh')]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(logic.messageList.single.clientMsgID, 'fresh');
    logic.onDelete();
    expect(ChatHistoryCache.read('self', 'chat'), isEmpty);
  });

  testWidgets('sync started before entry refreshes once after the first query',
      (tester) async {
    im.imSdkStatus(IMSdkStatus.syncStart);
    final logic = open();
    expect(logic.syncStatus.value, IMSdkStatus.syncStart);
    await tester.idle();
    im.imSdkStatus(IMSdkStatus.syncEnded);
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.idle();
    expect(calls, hasLength(1));
    calls.first.complete([_entryMessage('before-sync')]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(calls, hasLength(2));
    expect(calls.last.arguments['startClientMsgID'], '');
    calls.last.complete([_entryMessage('after-sync', time: 2)]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(calls, hasLength(2));
    expect(logic.messageList.single.clientMsgID, 'after-sync');
    expect(logic.syncStatus.value, IMSdkStatus.syncEnded);
    logic.onDelete();
  });

  testWidgets('clear rejects late history and a previously queued sync refresh',
      (tester) async {
    ChatHistoryCache.write('self', 'chat', [_entryMessage('cached')]);
    final logic = open();
    await tester.idle();
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.idle();
    logic.clearAllMessage();
    calls.single.complete([_entryMessage('late-history')]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, hasLength(1));
    expect(logic.messageList, isEmpty);
    expect(logic.historyLoading.value, isFalse);
    expect(logic.historyHasMore.value, isFalse);
    expect(ChatHistoryCache.read('self', 'chat'), isEmpty);
    logic.onDelete();
  });

  testWidgets(
      'closing cancels callbacks and listeners and rejects late history',
      (tester) async {
    final logic = open();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(im.onRecvNewMessage, isNotNull);
    expect(im.onRecvC2CReadReceipt, isNotNull);
    expect(im.onSignalingMessage, isNotNull);
    expect(im.imSdkStatusPublishSubject.hasListener, isTrue);
    expect(im.deletedMessages.hasListener, isTrue);
    final ownedCallback = im.onRecvNewMessage!;
    logic.onDelete();
    expect(im.onRecvNewMessage, isNull);
    expect(im.onRecvC2CReadReceipt, isNull);
    expect(im.onSignalingMessage, isNull);
    expect(im.imSdkStatusPublishSubject.hasListener, isFalse);
    expect(im.deletedMessages.hasListener, isFalse);
    expect(im.revokedMessages.hasListener, isFalse);
    expect(im.conversationChangedSubject.hasListener, isFalse);
    ownedCallback(_entryMessage('late-callback'));
    calls.single.complete([_entryMessage('late-history')]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(logic.messageList, isEmpty);
    expect(ChatHistoryCache.read('self', 'chat'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the previous route preserves successor route callbacks',
      (tester) async {
    final first = open(_entryConversation(id: 'first'));
    await tester.pumpWidget(const SizedBox.shrink());
    final second = open(_entryConversation(id: 'second'));
    await tester.pumpWidget(const SizedBox.shrink());
    final messageCallback = im.onRecvNewMessage;
    final receiptCallback = im.onRecvC2CReadReceipt;
    final signalingCallback = im.onSignalingMessage;
    first.onDelete();
    expect(identical(im.onRecvNewMessage, messageCallback), isTrue);
    expect(identical(im.onRecvC2CReadReceipt, receiptCallback), isTrue);
    expect(identical(im.onSignalingMessage, signalingCallback), isTrue);
    messageCallback!(_entryMessage('received-by-successor'));
    expect(first.messageList, isEmpty);
    expect(second.messageList.single.clientMsgID, 'received-by-successor');
    calls[0].complete([_entryMessage('old-route-result')]);
    calls[1].complete([]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(first.messageList, isEmpty);
    expect(second.messageList.single.clientMsgID, 'received-by-successor');
    second.onDelete();
    expect(im.onRecvNewMessage, isNull);
    expect(im.onSignalingMessage, isNull);
  });

  testWidgets('account cache clear cannot be repopulated by an old route query',
      (tester) async {
    final logic = open();
    await tester.idle();
    ChatHistoryCache.clear();
    calls.single.complete([_entryMessage('arrived-after-logout')]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    logic.onDelete();
    expect(ChatHistoryCache.read('self', 'chat'), isEmpty);
  });

  testWidgets('sync and returning to the bottom merge buffered IDs only once',
      (tester) async {
    final logic = open();
    await tester.idle();
    calls.single.complete([_entryMessage('old')]);
    await tester.pumpWidget(const SizedBox.shrink());
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.idle();
    logic.scrollingCacheMessageList.addAll([
      _entryMessage('shared', time: 2),
      _entryMessage('new-buffered', time: 3),
    ]);
    calls.last.complete([_entryMessage('shared', time: 2)]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(logic.scrollingCacheMessageList.map((m) => m.clientMsgID),
        ['new-buffered']);
    // An overlapping callback must not produce duplicate widget/message keys.
    logic.scrollingCacheMessageList.add(_entryMessage('shared', time: 2));
    logic.onScrollToTop();
    expect(logic.messageList.map((m) => m.clientMsgID),
        ['shared', 'new-buffered']);
    expect(logic.scrollingCacheMessageList, isEmpty);
    logic.onDelete();
  });

  testWidgets('closing before the first frame makes scheduled onReady harmless',
      (tester) async {
    final logic = open();
    await tester.idle();
    logic.onDelete();
    calls.single.complete([]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing preserves the final draft after input resources dispose',
      (tester) async {
    final logic = open();
    logic.inputCtrl.text = 'final draft';
    logic.onDelete();
    await tester.idle();
    expect(draftCalls, hasLength(1));
    expect(draftCalls.single['conversationID'], 'chat');
    expect(jsonDecode(draftCalls.single['draftText'])['text'], 'final draft');
  });

  testWidgets('an old route never saves its queued draft to a new account',
      (tester) async {
    final logic = open();
    logic.inputCtrl.text = 'old account draft';
    logic.onDelete();
    OpenIM.iMManager.userID = 'another-account';
    await tester.idle();
    expect(draftCalls, isEmpty);
  });

  testWidgets('cold route takes the history read started before navigation',
      (tester) async {
    final info = _entryConversation();
    ChatHistoryPrefetcher.shared.prepare(info);
    await tester.idle();
    expect(calls, hasLength(1));
    final logic = open(info);
    await tester.idle();
    expect(calls, hasLength(1));
    calls.single.complete([_entryMessage('prepared')]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(logic.messageList.map((m) => m.clientMsgID), ['prepared']);
    logic.onDelete();
  });

  testWidgets('already prepared local history appears on the first route frame',
      (tester) async {
    final info = _entryConversation();
    ChatHistoryPrefetcher.shared.prepare(info);
    await tester.idle();
    calls.single.complete([_entryMessage('prepared')]);
    await tester.idle();
    final logic = open(info);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(calls, hasLength(1));
    expect(logic.messageList.map((m) => m.clientMsgID), ['prepared']);
    logic.onDelete();
  });

  testWidgets('a deleted conversation cannot be cached again by an old route',
      (tester) async {
    final logic = open();
    await tester.idle();
    calls.single.complete([_entryMessage('old')]);
    await tester.pumpWidget(const SizedBox.shrink());
    ChatHistoryCache.removeConversation('self', 'chat');
    logic.onDelete();
    expect(ChatHistoryCache.read('self', 'chat'), isEmpty);
  });

  testWidgets('a renewed token prevents the old route from caching on close',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'chatToken': 'first-token',
      'imToken': 'im-token',
    }));
    final logic = open();
    await tester.idle();
    calls.single.complete([_entryMessage('old-session')]);
    await tester.pumpWidget(const SizedBox.shrink());
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'chatToken': 'renewed-token',
      'imToken': 'im-token',
    }));
    logic.onDelete();
    expect(ChatHistoryCache.read('self', 'chat'), isEmpty);
    await DataSp.removeLoginCertificate();
  });

  testWidgets('live messages enter mounted history immediately without jumping',
      (tester) async {
    final logic = await mountHistoryChat(tester);
    await scrollAway(tester, logic);
    final offset = logic.scrollController.offset;

    im.recvNewMessage(_entryMessage('live-first', time: 31));
    im.recvNewMessage(_entryMessage('live-second', time: 32));
    expect(logic.messageList.map((message) => message.clientMsgID),
        containsAll(['live-first', 'live-second']));
    expect(logic.newMessages.unseenCount.value, 2);
    expect(logic.scrollingCacheMessageList, isEmpty);

    await tester.pump();
    expect(logic.scrollController.offset, offset);
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    expect(tester.takeException(), isNull);
    logic.onDelete();
  });

  testWidgets(
      'new-message count excludes duplicates own typing and other chats',
      (tester) async {
    final logic = await mountHistoryChat(tester);
    await scrollAway(tester, logic);
    im.recvNewMessage(_entryMessage('live', time: 31));
    im.recvNewMessage(_entryMessage('live', time: 31));
    im.recvNewMessage(_entryMessage('own', time: 32)
      ..sendID = 'self'
      ..recvID = 'peer');
    im.recvNewMessage(
        _entryMessage('other-single', time: 33)..sendID = 'another-peer');
    im.recvNewMessage(_entryMessage('other-group', time: 34)
      ..sessionType = ConversationType.superGroup
      ..groupID = 'another-group');
    im.recvNewMessage(
        _entryMessage('typing', time: 35)..contentType = MessageType.typing);

    expect(logic.newMessages.unseenCount.value, 1);
    expect(logic.messageList.where((message) => message.clientMsgID == 'live'),
        hasLength(1));
    expect(logic.messageList.map((message) => message.clientMsgID),
        contains('own'));
    expect(
        logic.messageList.map((message) => message.clientMsgID),
        isNot(anyOf(contains('other-single'), contains('other-group'),
            contains('typing'))));
    expect(logic.scrollingCacheMessageList, isEmpty);
    await tester.pump();
    logic.onDelete();
  });

  testWidgets(
      'viewport callbacks decrease arrivals one by one while still away',
      (tester) async {
    final logic = await mountHistoryChat(tester);
    await scrollAway(tester, logic);
    for (var index = 1; index <= 3; index++) {
      im.recvNewMessage(_entryMessage('live-$index', time: 30 + index));
    }
    expect(logic.newMessages.unseenCount.value, 3);

    logic.onChatViewportChanged(['live-1'], 160);
    expect(logic.newMessages.unseenCount.value, 2);
    logic.onChatViewportChanged(['live-1', 'history-29', 'unknown'], 120);
    expect(logic.newMessages.unseenCount.value, 2);
    logic.onChatViewportChanged(['live-2'], 80);
    expect(logic.newMessages.unseenCount.value, 1);
    logic.onChatViewportChanged(['live-3'], 40);
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.newMessages.awayFromLatest.value, isTrue);

    logic.onChatViewportChanged(['live-3'], 160);
    im.recvNewMessage(_entryMessage('live-1', time: 31));
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    await tester.pump();
    logic.onDelete();
  });

  testWidgets('SDK deletion and revocation remove pending arrivals from count',
      (tester) async {
    final logic = await mountHistoryChat(tester);
    await scrollAway(tester, logic);
    final deleted = _entryMessage('deleted-arrival', time: 31);
    im.recvNewMessage(deleted);
    im.recvNewMessage(_entryMessage('revoked-arrival', time: 32));
    im.recvNewMessage(_entryMessage('remaining-arrival', time: 33));
    expect(logic.newMessages.unseenCount.value, 3);

    im.messageDeleted(deleted);
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 2);
    im.recvMessageRevoked(RevokedInfo(clientMsgID: 'revoked-arrival'));
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 1);
    expect(logic.messageList.map((message) => message.clientMsgID),
        isNot(anyOf(contains('deleted-arrival'), contains('revoked-arrival'))));
    im.recvNewMessage(deleted);
    expect(logic.newMessages.unseenCount.value, 1);
    logic.onChatViewportChanged(['remaining-arrival'], 160);
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    logic.onDelete();
  });

  testWidgets('clearing a chat resets pending arrivals and rejects deleted IDs',
      (tester) async {
    final logic = await mountHistoryChat(tester);
    await scrollAway(tester, logic);
    im.recvNewMessage(_entryMessage('live-first', time: 31));
    im.recvNewMessage(_entryMessage('live-second', time: 32));
    expect(logic.newMessages.unseenCount.value, 2);

    logic.clearAllMessage();
    expect(logic.messageList, isEmpty);
    expect(logic.scrollingCacheMessageList, isEmpty);
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.newMessages.awayFromLatest.value, isFalse);
    im.recvNewMessage(_entryMessage('live-first', time: 31));
    logic.onChatViewportChanged(['live-first'], 0);
    expect(logic.messageList, isEmpty);
    expect(logic.newMessages.unseenCount.value, 0);
    await tester.pump();
    logic.onDelete();
  });

  testWidgets('deleting the only row clears a detached return-to-bottom state',
      (tester) async {
    final logic = open();
    await tester.idle();
    calls.single.complete([]);
    await tester.pumpWidget(const SizedBox.shrink());
    final message = _entryMessage('only-arrival', time: 1);
    logic.messageList.add(message);
    logic.newMessages.updateScrollOffset(100);
    logic.newMessages.recordIncoming(message);
    expect(logic.scrollController.hasClients, isFalse);
    expect(logic.newMessages.unseenCount.value, 1);
    im.messageDeleted(message);
    await tester.pump();
    expect(logic.messageList, isEmpty);
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.newMessages.awayFromLatest.value, isFalse);
    logic.onDelete();
  });

  testWidgets('account switching ignores new messages and old viewport reports',
      (tester) async {
    final logic = await mountHistoryChat(tester);
    await scrollAway(tester, logic);
    im.recvNewMessage(_entryMessage('before-account-change', time: 31));
    final ownedCallback = im.onRecvNewMessage!;
    OpenIM.iMManager.userID = 'another-account';
    ownedCallback(_entryMessage('late-other-account', time: 32));
    logic.onChatViewportChanged(['before-account-change'], 0);

    expect(logic.newMessages.unseenCount.value, 1);
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    expect(logic.messageList.map((message) => message.clientMsgID),
        isNot(contains('late-other-account')));
    await tester.pumpWidget(const SizedBox.shrink());
    logic.onDelete();
    expect(logic.newMessages.unseenCount.value, 0);
  });

  testWidgets('token renewal ignores live messages and late visibility reports',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'chatToken': 'first-token',
      'imToken': 'im-token',
    }));
    final logic = await mountHistoryChat(tester);
    await scrollAway(tester, logic);
    im.recvNewMessage(_entryMessage('before-token-change', time: 31));
    final ownedCallback = im.onRecvNewMessage!;
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'chatToken': 'renewed-token',
      'imToken': 'im-token',
    }));
    ownedCallback(_entryMessage('late-token', time: 32));
    logic.onChatViewportChanged(['before-token-change'], 0);

    expect(logic.newMessages.unseenCount.value, 1);
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    expect(logic.messageList.map((message) => message.clientMsgID),
        isNot(contains('late-token')));
    await tester.pumpWidget(const SizedBox.shrink());
    logic.onDelete();
    expect(logic.newMessages.unseenCount.value, 0);
    await DataSp.removeLoginCertificate();
  });

  testWidgets('closing a mounted chat rejects late callbacks and visibility',
      (tester) async {
    final logic = await mountHistoryChat(tester);
    await scrollAway(tester, logic);
    im.recvNewMessage(_entryMessage('pending-at-close', time: 31));
    final ownedCallback = im.onRecvNewMessage!;
    await tester.pumpWidget(const SizedBox.shrink());
    logic.onDelete();

    ownedCallback(_entryMessage('late-after-close', time: 32));
    logic.onChatViewportChanged(['pending-at-close'], 160);
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.newMessages.awayFromLatest.value, isFalse);
    expect(logic.messageList.map((message) => message.clientMsgID),
        isNot(contains('late-after-close')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'bottom arrivals stay uncounted and return-to-bottom clears count',
      (tester) async {
    final logic = await mountHistoryChat(tester);
    im.recvNewMessage(_entryMessage('bottom-arrival', time: 31));
    expect(logic.messageList.last.clientMsgID, 'bottom-arrival');
    expect(logic.newMessages.unseenCount.value, 0);
    await tester.pump();
    expect(logic.newMessages.awayFromLatest.value, isFalse);
    expect(logic.scrollController.offset,
        logic.scrollController.position.minScrollExtent);

    await scrollAway(tester, logic);
    im.recvNewMessage(_entryMessage('bottom-arrival', time: 31));
    expect(logic.newMessages.unseenCount.value, 0);
    im.recvNewMessage(_entryMessage('away-arrival', time: 32));
    expect(logic.newMessages.unseenCount.value, 1);
    logic.scrollBottom();
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.newMessages.awayFromLatest.value, isFalse);
    expect(logic.scrollController.offset,
        logic.scrollController.position.minScrollExtent);
    expect(logic.scrollingCacheMessageList, isEmpty);
    logic.onDelete();
  });

  testWidgets('pending automatic follow respects a newer user scroll',
      (tester) async {
    final logic = await mountHistoryChat(tester);
    im.recvNewMessage(_entryMessage('arrived-at-latest', time: 31));
    // The SDK event has queued its automatic follow, but it has not run yet.
    // A real controller movement updates the tracker before that frame.
    logic.scrollController.jumpTo(160);
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    await tester.pumpAndSettle();
    expect(logic.scrollController.offset, 160);
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.messageList.last.clientMsgID, 'arrived-at-latest');
    expect(logic.scrollingCacheMessageList, isEmpty);
    logic.onDelete();
  });

  testWidgets('initial unread and SDK history refresh never count as arrivals',
      (tester) async {
    final logic = await mountHistoryChat(tester,
        conversation: _entryConversation()..unreadCount = 10);
    expect(logic.newMessages.unseenCount.value, 0);
    await scrollAway(tester, logic);
    logic.onChatViewportChanged(['history-0'], 160);
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.idle();
    expect(calls, hasLength(2));
    calls.last.complete([
      ...List.generate(
          30, (index) => _entryMessage('history-$index', time: index + 1)),
      _entryMessage('sdk-history-only', time: 31),
    ]);
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'sdk-history-only');
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    expect(logic.scrollController.offset, 160);
    logic.onDelete();
  });

  testWidgets(
      'real chat list visibility reduces live-arrival count without replay',
      (tester) async {
    final logic = await mountHistoryChat(tester, commonList: true);
    logic.scrollController.jumpTo(400);
    await tester.pump();
    im.recvNewMessage(_entryMessage('visible-first', time: 31));
    im.recvNewMessage(_entryMessage('visible-second', time: 32));
    expect(logic.newMessages.unseenCount.value, 2);
    expect(logic.scrollingCacheMessageList, isEmpty);
    await tester.pump();
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 2);
    expect(logic.scrollController.offset, greaterThan(1));

    // In the reversed 48px rows, distance 48 fully exposes index 1 (the
    // earlier arrival), while index 0 is still beyond the bottom edge.
    logic.scrollController
        .jumpTo(logic.scrollController.position.minScrollExtent + 48);
    await tester.pump();
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 1);
    expect(logic.newMessages.awayFromLatest.value, isTrue);

    logic.scrollController.jumpTo(400);
    await tester.pump();
    await tester.pump();
    expect(logic.newMessages.unseenCount.value, 1);
    im.recvNewMessage(_entryMessage('visible-first', time: 31));
    expect(logic.newMessages.unseenCount.value, 1);
    logic.scrollBottom();
    await tester.pumpAndSettle();
    expect(logic.newMessages.unseenCount.value, 0,
        reason: 'pixels=${logic.scrollController.offset}, '
            'min=${logic.scrollController.position.minScrollExtent}, '
            'max=${logic.scrollController.position.maxScrollExtent}, '
            'away=${logic.newMessages.awayFromLatest.value}');
    expect(logic.newMessages.awayFromLatest.value, isFalse);
    expect(tester.takeException(), isNull);
    logic.onDelete();
  });

  testWidgets('real chat list follows new latest boundary after SDK refresh',
      (tester) async {
    final logic = await mountHistoryChat(tester, commonList: true);
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.idle();
    calls.last.complete([
      ...List.generate(
          30, (index) => _entryMessage('history-$index', time: index + 1)),
      _entryMessage('refreshed-latest', time: 31),
    ]);
    await tester.pump();
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'refreshed-latest');
    expect(logic.scrollController.offset,
        logic.scrollController.position.minScrollExtent);
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.newMessages.awayFromLatest.value, isFalse);
    expectMessageInsideChatList(tester, 'refreshed-latest');
    logic.onDelete();
  });

  testWidgets('real chat list stays latest after a live arrival',
      (tester) async {
    final logic = await mountHistoryChat(tester, commonList: true);
    im.recvNewMessage(_entryMessage('bottom-live', time: 31));
    await tester.pump();
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'bottom-live');
    expect(logic.scrollController.offset,
        logic.scrollController.position.minScrollExtent);
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.newMessages.awayFromLatest.value, isFalse);
    expect(logic.scrollingCacheMessageList, isEmpty);
    expectMessageInsideChatList(tester, 'bottom-live');
    logic.onDelete();
  });

  registerChatNewMessageCases(
    mountChat: (tester, {rowHeight, observeViewport}) => mountHistoryChat(
        tester,
        commonList: true,
        rowHeight: rowHeight,
        observeViewport: observeViewport),
    receive: (message) => im.recvNewMessage(message),
    createMessage: (id, time) => _entryMessage(id, time: time),
  );

  registerChatKeyboardScrollCases(
    mountChat: (tester) =>
        mountHistoryChat(tester, commonList: true, showInput: true),
    receive: (message) => im.recvNewMessage(message),
    createMessage: (id, time) => _entryMessage(id, time: time),
  );
}
