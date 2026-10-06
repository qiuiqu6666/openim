import 'dart:async';

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) {
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
      if (call.method == 'getBlacklist') return Future.value('[]');
      if (call.method == 'setConversationDraft') return Future.value();
      if (call.method == 'changeInputStates') return Future.value();
      throw StateError('Unexpected native call ${call.method}');
    });
    // Get.put invokes the real onInit, including the neutral read subscription.
    conversations = Get.put<ConversationLogic>(ConversationLogic());
  });

  tearDown(() async {
    if (chatOpened && !chat.isClosed) chat.onDelete();
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
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Get.routing.current = '/chat';
    // Keep route state independent from the list row to expose missing handoff.
    Get.routing.args = {
      'conversationInfo': ConversationInfo.fromJson(conversations.list
          .firstWhere((row) => row.conversationID == 'chat')
          .toJson()),
    };
    chat = ChatLogic();
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
    im.conversationChanged([_conversation(message, unread: unread)]);
    im.recvNewMessage(message);
    await tester.pump();
    await tester.pump();
  }

  ConversationInfo getTarget() =>
      conversations.list.firstWhere((row) => row.conversationID == 'chat');

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
      chat.scrollController.jumpTo(1);
      await tester.pump();
      await tester.pump();
      expect(nativeReads, hasLength(1));
      acknowledgements.single.complete();
      await tester.pumpAndSettle();
      expect(getTarget().unreadCount, 0);
      expect(find.text('unread-source:7'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
