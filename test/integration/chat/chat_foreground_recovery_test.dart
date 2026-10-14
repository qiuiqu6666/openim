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

Message message(String id, int seq) => Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': 'peer',
      'recvID': 'self',
      'seq': seq,
      'sendTime': seq,
      'status': MessageStatus.succeeded,
      'textElem': {'content': id},
    });

ConversationInfo conversation({Message? latest}) => ConversationInfo(
      conversationID: 'chat',
      userID: 'peer',
      conversationType: ConversationType.single,
      showName: 'Peer',
      unreadCount: latest == null ? 0 : 1,
      groupAtType: GroupAtType.atNormal,
      latestMsg: latest,
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late EntryTestIM im;
  late List<EntryHistoryCall> calls;
  ChatLogic? owner;

  Future<ChatLogic> open(WidgetTester tester) async {
    Get.routing.args = {'conversationInfo': conversation()};
    final logic = owner = ChatLogic();
    logic.onInit();
    await tester.idle();
    calls.single.complete([message('before-background', 1)]);
    await tester.pumpWidget(buildChatEntryList(logic));
    await tester.pump();
    return logic;
  }

  Future<void> backgroundAndResume(WidgetTester tester) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.idle();
  }

  setUp(() async {
    Get.testMode = true;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    ChatHistoryCache.clear();
    ChatHistoryPrefetcher.shared.clear();
    calls = [];
    owner = null;
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self');
    Get.put<AppController>(EntryTestApp());
    im = Get.put<IMController>(EntryTestIM()) as EntryTestIM;
    Get.put<ConversationLogic>(EntryTestConversation());
    Get.put<CacheController>(EntryTestCache());
    im.imSdkStatus(IMSdkStatus.syncEnded);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      if (call.method == 'getAdvancedHistoryMessageList' ||
          call.method == 'getAdvancedHistoryMessageListReverse') {
        final history =
            EntryHistoryCall(Map<String, dynamic>.from(call.arguments as Map));
        calls.add(history);
        return history.result.future;
      }
      if (call.method == 'getBlacklist') return '[]';
      return null;
    });
  });

  tearDown(() {
    if (owner?.isClosed == false) owner!.onDelete();
    for (final call in calls) {
      call.complete([]);
    }
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    Get.reset();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
  });

  testWidgets('native wake rereads after resume returned a healthy stale page',
      (tester) async {
    final logic = await open(tester);
    logic.inputCtrl.text = 'keep my draft';
    await backgroundAndResume(tester);
    expect(calls, hasLength(2));
    calls.last.complete([message('before-background', 1)]);
    await tester.pump();
    expect(logic.historyError.value, isNull);

    // SDK persistence catches up after the first resume query, without
    // another sync-finished or individual-message callback.
    im.historyRecoverySignals.add(null);
    await tester.idle();
    expect(calls, hasLength(3));
    calls.last.complete([
      message('before-background', 1),
      message('received-in-background', 2),
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.text('received-in-background'), findsOneWidget);
    expect(logic.inputCtrl.text, 'keep my draft');
    expect(logic.messageList, hasLength(2));
    logic.onDelete();
  });

  testWidgets('late persistence is retried even without SDK delivery callbacks',
      (tester) async {
    final logic = await open(tester);
    expect(logic.newMessages.awayFromLatest.value, isFalse);
    await backgroundAndResume(tester);
    expect(calls.last.arguments['startClientMsgID'], '');
    calls.last.complete([]);
    await tester.pump();
    im.historyRecoverySignals.add(null);
    await tester.idle();
    calls.last.complete([]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, hasLength(4));
    calls.last.complete([message('persisted-later', 2)]);
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'persisted-later');
    expect(logic.historyError.value, isNull);
    logic.onDelete();
  });

  testWidgets('reconnect renews exhausted background recovery attempts',
      (tester) async {
    final logic = await open(tester);
    await backgroundAndResume(tester);
    for (final delay in [1, 3]) {
      calls.last.complete([]);
      await tester.pump();
      await tester.pump(Duration(seconds: delay));
    }
    calls.last.complete([]);
    await tester.pump();
    final count = calls.length;
    await tester.pump(const Duration(seconds: 10));
    expect(calls, hasLength(count));
    im.imSdkStatus(IMSdkStatus.connectionSucceeded);
    await tester.idle();
    expect(calls, hasLength(count + 1));
    calls.last.complete([message('after-reconnect', 2)]);
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'after-reconnect');
    logic.onDelete();
  });

  testWidgets('conversation update repairs a missing delivery after wake',
      (tester) async {
    final logic = await open(tester);
    await backgroundAndResume(tester);
    calls.last.complete([message('before-background', 1)]);
    await tester.pump();
    im.conversationChanged(
        [conversation(latest: message('persisted-later', 2))]);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(3));
    calls.last.complete([
      message('before-background', 1),
      message('persisted-later', 2),
    ]);
    await tester.pump();
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'persisted-later');
    expect(find.text('persisted-later'), findsOneWidget);
    logic.onDelete();
  });

  testWidgets('healthy ended window ignores unrelated global recovery cycles',
      (tester) async {
    final logic = await open(tester);
    for (var cycle = 0; cycle < 3; cycle++) {
      im.imSdkStatus(IMSdkStatus.syncFailed);
      im.historyRecoverySignals.add(null);
      im.imSdkStatus(IMSdkStatus.syncStart);
      im.imSdkStatus(IMSdkStatus.syncEnded);
      await tester.pump(const Duration(seconds: 30));
    }
    expect(calls, hasLength(1));
    expect(logic.historyLoading.value, isFalse);
    expect(logic.historyPagingLoading.value, isFalse);
    expect(logic.messageList.single.clientMsgID, 'before-background');
    logic.onDelete();
  });

  testWidgets('ordinary conversation and message callbacks need no extra read',
      (tester) async {
    final logic = await open(tester);
    im.conversationChanged([conversation(latest: message('live', 2))]);
    await tester.idle();
    im.recvNewMessage(message('live', 2));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(1));
    expect(logic.messageList.last.clientMsgID, 'live');
    logic.onDelete();
  });

  testWidgets('recovery signals during a read coalesce into one fresh query',
      (tester) async {
    final logic = await open(tester);
    await backgroundAndResume(tester);
    im.historyRecoverySignals.add(null);
    im.historyRecoverySignals.add(null);
    await tester.idle();
    expect(calls, hasLength(2));
    calls.last.complete([message('before-background', 1)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, hasLength(3));
    calls.last.complete([message('latest', 3)]);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, hasLength(3));
    expect(logic.messageList.last.clientMsgID, 'latest');
    logic.onDelete();
  });

  testWidgets('sync completion refreshes after a wake during active sync',
      (tester) async {
    final logic = await open(tester);
    im.imSdkStatus(IMSdkStatus.syncStart);
    await tester.idle();
    await backgroundAndResume(tester);
    im.historyRecoverySignals.add(null);
    await tester.idle();
    // Local catch-up is allowed while the SDK's global sync is still running.
    // An empty early read must not prevent a fresh pass at sync completion.
    expect(calls, hasLength(2));
    calls.last.complete([]);
    await tester.pump();
    im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.idle();
    expect(calls, hasLength(3));
    calls.last.complete([message('synced', 2)]);
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'synced');
    logic.onDelete();
  });

  testWidgets('background updates defer the read until the same chat resumes',
      (tester) async {
    final logic = await open(tester);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    im.conversationChanged([conversation(latest: message('background', 2))]);
    im.historyRecoverySignals.add(null);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(1));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.idle();
    expect(calls, hasLength(2));
    calls.last.complete([message('background', 2)]);
    await tester.pump();
    expect(logic.messageList.last.clientMsgID, 'background');
    logic.onDelete();
  });

  testWidgets('historical window stays in place when recovery signals arrive',
      (tester) async {
    final logic = await open(tester);
    final target = message('old-target', -10);
    final seek = logic.jumpToDateMessage(target);
    await tester.idle();
    calls[calls.length - 2].complete([message('older', -11)], isEnd: false);
    calls.last.complete([message('newer', -9)], isEnd: false);
    await tester.pump();
    await tester.pump();
    await seek;
    expect(logic.viewingHistory.value, isTrue);
    final historyIDs = logic.messageList.map((m) => m.clientMsgID).toList();
    final before = calls.length;
    im.historyRecoverySignals.add(null);
    im.conversationChanged([conversation(latest: message('latest', 5))]);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(before));
    expect(logic.messageList.map((m) => m.clientMsgID), historyIDs);
    expect(logic.historyNewerHasMore.value, isTrue);
    logic.onDelete();
  });

  testWidgets('conversation bursts reconcile the newest snapshot once',
      (tester) async {
    final logic = await open(tester);
    for (var seq = 2; seq <= 20; seq++) {
      im.conversationChanged(
          [conversation(latest: message('burst-$seq', seq))]);
    }
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(2));
    calls.last
        .complete(List.generate(20, (i) => message('burst-${i + 1}', i + 1)));
    await tester.pump();
    im.conversationChanged([conversation(latest: message('burst-20', 20))]);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(2));
    expect(logic.messageList.last.clientMsgID, 'burst-20');
    logic.onDelete();
  });

  testWidgets('clearing history cancels a pending conversation repair',
      (tester) async {
    final logic = await open(tester);
    im.conversationChanged([conversation(latest: message('late', 2))]);
    await tester.idle();
    logic.clearAllMessage();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(1));
    expect(logic.messageList, isEmpty);
    logic.onDelete();
  });

  testWidgets('a newer summary during reconciliation gets a fresh follow-up',
      (tester) async {
    final logic = await open(tester);
    im.conversationChanged([conversation(latest: message('first', 2))]);
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(2));
    im.conversationChanged([conversation(latest: message('second', 3))]);
    await tester.pump(const Duration(milliseconds: 200));
    calls.last.complete([message('first', 2)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(3));
    im.conversationChanged([conversation(latest: message('third', 4))]);
    await tester.pump(const Duration(milliseconds: 200));
    calls.last.complete([message('first', 2), message('second', 3)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls, hasLength(4));
    calls.last.complete([message('second', 3), message('third', 4)]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(logic.messageList.last.clientMsgID, 'third');
    expect(calls, hasLength(4));
    logic.onDelete();
  });

  testWidgets('failed foreground reconciliation uses the bounded history retry',
      (tester) async {
    final logic = await open(tester);
    logic.onResumed();
    await tester.idle();
    expect(calls, hasLength(2));
    calls.last.result.completeError(PlatformException(code: 'offline'));
    await tester.pump();
    expect(logic.historyError.value, isNotNull);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, hasLength(3));
    calls.last.complete([message('retried', 2)]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(logic.historyError.value, isNull);
    expect(logic.messageList.single.clientMsgID, 'retried');
    expect(calls, hasLength(3));
    logic.onDelete();
  });

  for (final close in [true, false]) {
    testWidgets(
        'pending recovery stops on ${close ? 'close' : 'account change'}',
        (tester) async {
      final logic = await open(tester);
      im.conversationChanged([conversation(latest: message('late', 2))]);
      await tester.idle();
      if (close) {
        logic.onDelete();
      } else {
        OpenIM.iMManager.userID = 'other';
      }
      im.historyRecoverySignals.add(null);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect(calls, hasLength(1));
      expect(logic.messageList.single.clientMsgID, 'before-background');
    });
  }
}
