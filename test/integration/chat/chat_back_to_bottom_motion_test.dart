import 'package:flutter/material.dart';
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
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/group_features/data/group_feature_runtime.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_list_viewport.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../support/chat/chat_entry_sdk.dart';

Message _historyMessage(int index) => Message.fromJson({
      'clientMsgID': 'history-$index',
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': 'self',
      'recvID': 'peer',
      'senderNickname': 'Self',
      'seq': index + 1,
      'sendTime': 1700000000000 + index * 1000,
      'status': MessageStatus.succeeded,
      'textElem': {'content': '历史消息 $index'},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late List<EntryHistoryCall> histories;
  late ChatLogic logic;
  late bool opened;

  setUp(() async {
    Get.testMode = true;
    final previousVisibilityInterval =
        VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    addTearDown(() => VisibilityDetectorController.instance.updateInterval =
        previousVisibilityInterval);
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await SpUtil().init();
    // No business login or media URLs: only the native test boundary is used.
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    GroupFeatureRuntime.reset();
    Get.put<AppController>(EntryTestApp());
    Get.put<IMController>(EntryTestIM());
    Get.put<ConversationLogic>(EntryTestConversation());
    Get.put<CacheController>(EntryTestCache());
    histories = [];
    opened = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) async {
      if (call.method == 'getAdvancedHistoryMessageList') {
        final history =
            EntryHistoryCall(Map<String, dynamic>.from(call.arguments as Map));
        histories.add(history);
        return history.result.future;
      }
      if (call.method == 'getBlacklist') return '[]';
      if ({
        'markConversationMessageAsRead',
        'changeInputStates',
        'setConversationDraft',
      }.contains(call.method)) {
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
    GroupFeatureRuntime.reset();
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
  });

  testWidgets('ChatPage back button decelerates and reaches the painted latest',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Get.routing.args = {
      'conversationInfo': ConversationInfo(
        conversationID: 'chat',
        userID: 'peer',
        conversationType: ConversationType.single,
        showName: 'Peer',
        unreadCount: 0,
        groupAtType: GroupAtType.atNormal,
        latestMsg: _historyMessage(79),
      ),
    };
    logic = Get.put<ChatLogic>(ChatLogic(), tag: GetTags.chat);
    opened = true;
    await tester.idle();
    expect(histories, hasLength(1));
    histories.single.complete(List.generate(80, _historyMessage));
    try {
      // Mount the production page and its production button callback unchanged.
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
                translations: TranslationService(),
                locale: const Locale('zh', 'CN'),
                theme: ThemeData(platform: TargetPlatform.android),
                home: ChatPage(),
              )));
      await tester.pumpAndSettle();
      expect(find.byType(ChatPage), findsOneWidget);
      expect(find.byType(ChatListView), findsOneWidget);
      final position = logic.scrollController.position;
      logic.scrollController.jumpTo(position.minScrollExtent + 16);
      await tester.pumpAndSettle();
      expect(logic.newMessages.awayFromLatest.value, isFalse,
          reason: 'Small movement stays inside the latest-message tolerance.');
      expect(find.byType(NewMessageIndicator), findsNothing,
          reason: 'A small movement must not show the return button.');
      for (final (ratio, visible) in [
        (0.55, true),
        (0.48, true),
        (0.4, false),
      ]) {
        logic.scrollController.jumpTo(
            position.minScrollExtent + position.viewportDimension * ratio);
        await tester.pumpAndSettle();
        expect(find.byType(NewMessageIndicator),
            visible ? findsOneWidget : findsNothing);
      }
      logic.scrollController.jumpTo(900);
      await tester.pumpAndSettle();
      expect(logic.newMessages.awayFromLatest.value, isTrue);
      expect(find.byType(NewMessageIndicator), findsOneWidget);

      await tester.tap(find.byType(NewMessageIndicator));
      await tester.pump();
      await tester.pump();
      final start = logic.scrollController.offset;
      expect(start - logic.scrollController.position.minScrollExtent,
          greaterThan(1));
      await tester.pump(const Duration(milliseconds: 100));
      final early = logic.scrollController.offset;
      await tester.pump(const Duration(milliseconds: 100));
      final later = logic.scrollController.offset;
      final firstMovement = start - early;
      final secondMovement = early - later;
      expect(firstMovement, greaterThan(0));
      expect(secondMovement, lessThan(firstMovement),
          reason:
              'The ease-out return slows down as it approaches the latest row.');
      expect(later - logic.scrollController.position.minScrollExtent,
          greaterThan(1));
      expect(find.byType(NewMessageIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(logic.scrollController.offset,
          closeTo(logic.scrollController.position.minScrollExtent, 1));
      final latestMessage = logic.messageList.last;
      expect(latestMessage.clientMsgID, 'history-79');
      final viewport = tester.getRect(find.byType(ChatListView));
      final latestKey = logic.itemKey(latestMessage);
      final latestFinder = find.byWidgetPredicate(
          (widget) => widget is ChatItemView && widget.key == latestKey);
      expect(latestFinder, findsOneWidget);
      final latest = tester.getRect(latestFinder);
      expect(latest.top, greaterThanOrEqualTo(viewport.top - 1));
      expect(latest.bottom, lessThanOrEqualTo(viewport.bottom + 1));
      expect(logic.newMessages.awayFromLatest.value, isFalse);
      expect(find.byType(NewMessageIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!logic.isClosed) logic.onDelete();
      await tester.pump();
    }
  });

  testWidgets('leaving a group reparents the existing message viewport',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Get.routing.args = {
      'conversationInfo': ConversationInfo(
          conversationID: 'chat',
          userID: 'peer',
          conversationType: ConversationType.single,
          showName: 'Group',
          unreadCount: 0,
          groupAtType: GroupAtType.atNormal),
    };
    logic = Get.put<ChatLogic>(ChatLogic(), tag: GetTags.chat);
    opened = true;
    await tester.idle();
    histories.single.complete(List.generate(80, _historyMessage));
    await tester.idle();
    // History is seeded through the existing SDK fixture; change only the
    // group presentation to exercise the production membership branches.
    logic.conversationInfo
      ..conversationType = ConversationType.superGroup
      ..groupID = 'dissolved-group';
    try {
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
              translations: TranslationService(),
              locale: const Locale('zh', 'CN'),
              home: ChatPage())));
      await tester.pumpAndSettle();
      final timelineState = tester.state(find.byType(ChatListView));
      logic.scrollController.jumpTo(500);
      await tester.pumpAndSettle();
      final viewportState = tester.state(find.byType(ChatListViewport));
      logic.isInGroup.value = false;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.state(find.byType(ChatListView)), same(timelineState));
      expect(logic.scrollController.positions, hasLength(1));
      expect(tester.state(find.byType(ChatListViewport)), same(viewportState));
      // The disabled composer changes viewport height; anchoring can adjust
      // the offset slightly, but must never reset to the latest message.
      expect(logic.scrollController.offset, greaterThan(400));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!logic.isClosed) logic.onDelete();
      await tester.pump();
    }
  });
}
