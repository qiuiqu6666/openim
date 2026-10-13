import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

import 'chat_entry_list.dart';
import 'chat_entry_sdk.dart';

Message recoveryMessage(String id, int seq) => Message.fromJson({
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

class RecoveryRoute extends PageRouteBuilder<void> {
  RecoveryRoute() : super(pageBuilder: (_, __, ___) => const SizedBox.shrink());
  bool current = true;
  @override
  bool get isCurrent => current;
}

class ChatRecoveryFixture {
  static const channel = MethodChannel('flutter_openim_sdk');
  final calls = <EntryHistoryCall>[];
  final nativeCalls = <MethodCall>[];
  late EntryTestIM im;
  ChatLogic? logic;
  final route = RecoveryRoute();

  ConversationInfo conversation({Message? latest}) => ConversationInfo(
        conversationID: 'chat',
        userID: 'peer',
        conversationType: ConversationType.single,
        showName: 'Peer',
        unreadCount: latest == null ? 0 : 1,
        groupAtType: GroupAtType.atNormal,
        latestMsg: latest,
      );

  Future<void> initialize() async {
    Get.testMode = true;
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    ChatHistoryCache.clear();
    ChatHistoryPrefetcher.shared.clear();
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self');
    Get.put<AppController>(EntryTestApp());
    im = Get.put<IMController>(EntryTestIM()) as EntryTestIM;
    Get.put<ConversationLogic>(EntryTestConversation());
    Get.put<CacheController>(EntryTestCache());
    im.imSdkStatus(IMSdkStatus.syncEnded);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
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
  }

  Future<ChatLogic> open(WidgetTester tester) async {
    Get.routing.args = {'conversationInfo': conversation()};
    final owner = logic = ChatLogic();
    owner.onInit();
    owner.bindMessageRoute(route);
    await tester.idle();
    calls.single.complete([recoveryMessage('initial', 1)], isEnd: false);
    await tester.pumpWidget(buildChatEntryList(owner));
    await tester.pump();
    return owner;
  }

  void cover(bool covered) {
    route.current = !covered;
    logic!.bindMessageRoute(route);
    // Production binding happens inside the route's build frame.
    WidgetsBinding.instance.scheduleFrame();
  }

  void announce(String id, int seq) =>
      im.conversationChanged([conversation(latest: recoveryMessage(id, seq))]);

  Future<void> dispose(WidgetTester tester) async {
    if (logic?.isClosed == false) logic!.onDelete();
    for (final call in calls) {
      call.complete([]);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    Get.reset();
    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}

void recoveryScenario(
    String name, Future<void> Function(WidgetTester, ChatRecoveryFixture) run) {
  testWidgets(name, (tester) async {
    final fixture = ChatRecoveryFixture();
    await fixture.initialize();
    try {
      await run(tester, fixture);
    } finally {
      await fixture.dispose(tester);
    }
  });
}
