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
import '../../support/chat/chat_entry_list.dart';
import '../../support/chat/chat_entry_sdk.dart';
import '../../pages/chat/history/message_window_ingress_test.dart' show window;

Message message(int seq, {String peer = 'peer'}) => Message.fromJson({
      'clientMsgID': '$peer-$seq',
      'seq': seq,
      'sendTime': 10000 - seq,
      'status': MessageStatus.succeeded,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': peer,
      'recvID': 'self',
      'textElem': {'content': 'message $seq'},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late EntryTestIM im;
  late List<EntryHistoryCall> calls;
  late List<ChatLogic> owners;
  AdvancedMessage? local;
  var localCalls = 0;
  ChatLogic open(String id, {String peer = 'peer'}) {
    Get.routing.args = {
      'conversationInfo': ConversationInfo(
          conversationID: id,
          userID: peer,
          conversationType: ConversationType.single,
          showName: peer,
          unreadCount: 0,
          groupAtType: GroupAtType.atNormal)
    };
    final logic = ChatLogic();
    owners.add(logic);
    logic.onInit();
    return logic;
  }

  setUp(() {
    Get.testMode = true;
    ChatHistoryCache.clear();
    ChatHistoryPrefetcher.shared.clear();
    calls = [];
    owners = [];
    local = null;
    localCalls = 0;
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self');
    Get.put<AppController>(EntryTestApp());
    im = Get.put<IMController>(EntryTestIM()) as EntryTestIM;
    Get.put<ConversationLogic>(EntryTestConversation());
    Get.put<CacheController>(EntryTestCache());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getLocalHistorySnapshot') {
        localCalls++;
        return jsonEncode((local ?? AdvancedMessage(messageList: [])).toJson());
      }
      if (call.method == 'getAdvancedHistoryMessageList') {
        final c =
            EntryHistoryCall(Map<String, dynamic>.from(call.arguments as Map));
        calls.add(c);
        return c.result.future;
      }
      if (call.method == 'getBlacklist') return '[]';
      return null;
    });
  });
  tearDown(() {
    for (final o in owners) {
      if (!o.isClosed) o.onDelete();
    }
    for (final c in calls) {
      c.complete([]);
    }
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'navigation prewarm publishes synchronously before first route build',
      (tester) async {
    im.imSdkStatus(IMSdkStatus.synchronizing);
    local = AdvancedMessage(
        window: window(40),
        messageList: List.generate(40, (i) => message(i + 1)));
    ChatHistoryPrefetcher.shared
        .prepare(ConversationInfo(conversationID: 'chat'));
    await tester.idle();
    expect(localCalls, 1);
    final logic = open('chat');
    expect(logic.initialWindowReady.value, isTrue,
        reason: 'A warm proof must not yield to another skeleton frame');
    expect(logic.messageList.last.seq, 40);
    await tester.pumpWidget(buildChatEntryList(logic, commonList: true));
    expect(find.text('peer-40'), findsOneWidget);
    expect(localCalls, 1);
    expect(calls.length, 1);
    calls.single.complete(local!.messageList!, window: window(40));
    await tester.pump();
    logic.onDelete();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'covered current conversation publishes while other conversations sync',
      (tester) async {
    im.imSdkStatus(IMSdkStatus.synchronizing);
    local = AdvancedMessage(
        window: window(40),
        messageList: List.generate(40, (i) => message(i + 1)));
    final logic = open('chat');
    await tester.pumpWidget(buildChatEntryList(logic, commonList: true));
    await tester.pump();
    expect(logic.initialWindowReady.value, isTrue);
    expect(logic.messageList.last.seq, 40);
    expect(calls.single.result.isCompleted, isFalse);
    expect(find.text('peer-40'), findsOneWidget);
    calls.single.complete(local!.messageList!, window: window(40));
    await tester.pump();
    logic.onDelete();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('snapshot 4951-5000 and live 5003,5001,5002 never expose a gap',
      (tester) async {
    final logic = open('chat');
    await tester.pumpWidget(buildChatEntryList(logic, commonList: true));
    im.recvNewMessage(message(5003));
    await tester.pump();
    expect(logic.initialWindowReady.value, isFalse);
    calls.first.complete(List.generate(50, (i) => message(4951 + i)),
        window: window(5000));
    await tester.pump();
    expect(logic.messageList.last.seq, 5000);
    im.recvNewMessage(message(5001));
    im.recvNewMessage(message(5002));
    await tester.pump(const Duration(milliseconds: 16));
    expect(logic.messageList.map((m) => m.seq),
        List.generate(53, (i) => 4951 + i));
    expect(logic.messageList.map((m) => m.clientMsgID).toSet().length, 53);
    logic.onDelete();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('A then B then A keeps each late snapshot with its own route',
      (tester) async {
    final a = open('A');
    await tester.idle();
    a.onDelete();
    final b = open('B', peer: 'other');
    await tester.pumpWidget(buildChatEntryList(b));
    await tester.idle();
    calls[1].complete(List.generate(40, (i) => message(i + 1, peer: 'other')),
        window: window(40, id: 'B'));
    await tester.pump();
    calls[0].complete(List.generate(40, (i) => message(i + 1)),
        window: window(40, id: 'A'));
    await tester.pump();
    expect(b.messageList.every((m) => m.sendID == 'other'), isTrue);
    b.onDelete();
    final again = open('A');
    await tester.pumpWidget(buildChatEntryList(again));
    calls.last.complete(List.generate(40, (i) => message(i + 1)),
        window: window(40, id: 'A'));
    await tester.pump();
    expect(again.messageList.length, 40);
    expect(again.messageList.last.seq, 40);
    again.onDelete();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('continuous growth stays bounded and preserves reading anchor',
      (tester) async {
    local = AdvancedMessage(
        window: window(40),
        messageList: List.generate(40, (i) => message(i + 1)));
    final logic = open('chat');
    await tester.pumpWidget(buildChatEntryList(logic, commonList: true));
    await tester.pump();
    calls.first.complete(local!.messageList!, window: window(40));
    await tester.pumpAndSettle();
    logic.scrollController.jumpTo(160);
    await tester.pump();
    final anchor = tester.getTopLeft(find.text('peer-35'));
    for (var start = 41; start <= 1040; start += 80) {
      for (var seq = start; seq < start + 80 && seq <= 1040; seq++) {
        im.recvNewMessage(message(seq));
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getTopLeft(find.text('peer-35')), anchor);
    expect(logic.messageList.length,
        lessThanOrEqualTo(680)); // at most one batch at the hold boundary
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    logic.onDelete();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
