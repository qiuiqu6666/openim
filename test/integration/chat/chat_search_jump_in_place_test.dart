import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/history/chat_history_prefetcher.dart';
import 'package:openim/pages/chat/history_search/chat_history_category.dart';
import 'package:openim/pages/chat/history_search/chat_history_results_page.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim/pages/chat/messages/widgets/chat_message_list.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/chat/chat_entry_list.dart';
import '../../support/chat/chat_entry_sdk.dart';

const _channel = MethodChannel('flutter_openim_sdk');
const _chatKey = ValueKey('search-jump-current-chat');
const _draftKey = ValueKey('search-jump-current-draft');
final _today = DateUtils.dateOnly(DateTime.now());
final _day = DateTime(_today.year, _today.month, _today.day - 3);

Message _message(String id,
        {int seq = 80, DateTime? time, String peer = 'peer'}) =>
    Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': peer,
      'recvID': 'self',
      'senderNickname': 'Peer',
      'seq': seq,
      'sendTime':
          (time ?? _day.add(const Duration(hours: 12))).millisecondsSinceEpoch,
      'status': MessageStatus.succeeded,
      'textElem': {'content': id},
    });

List<Message> _latest([int count = 30]) => List.generate(
    count,
    (index) => _message('latest-$index',
        seq: 1000 + index, time: _today.add(Duration(minutes: index))));

class _Routes extends NavigatorObserver {
  final active = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) active.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    active.remove(route);
  }
}

class _ResultSource implements ChatHistorySearchSource {
  _ResultSource(this.target);
  final Message target;
  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async =>
      [target];
}

class _Harness {
  final routes = _Routes();
  final older = <EntryHistoryCall>[];
  final newer = <EntryHistoryCall>[];
  final finds = <MethodCall>[];
  final stored = <String, Message>{};
  late EntryTestIM im;
  ChatLogic? _logic;
  String? _tag;
  ChatLogic get logic => _logic!;
  List<String?> get ids => logic.messageList.map((m) => m.clientMsgID).toList();

  Future<void> initialize() async {
    Get.reset();
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    Get.put<AppController>(EntryTestApp(), permanent: true);
    im = Get.put<IMController>(EntryTestIM(), permanent: true) as EntryTestIM;
    Get.put<ConversationLogic>(EntryTestConversation(), permanent: true);
    Get.put<CacheController>(EntryTestCache(), permanent: true);
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
    OpenIM.iMManager.token = 'search-jump-session';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'getAdvancedHistoryMessageList':
        case 'getAdvancedHistoryMessageListReverse':
          final query = EntryHistoryCall(
              Map<String, dynamic>.from(call.arguments as Map));
          (call.method == 'getAdvancedHistoryMessageList' ? older : newer)
              .add(query);
          return query.result.future;
        case 'findMessageList':
          finds.add(call);
          final params = (call.arguments as Map)['searchParams'] as List;
          final requested = (params.single as Map)['clientMsgIDList'] as List;
          final found = requested.map((id) => stored[id]).whereType<Message>();
          return jsonEncode({
            'findResultItems': [
              {
                'conversationID': 'chat',
                'messageList':
                    found.map((message) => message.toJson()).toList(),
              }
            ],
          });
        case 'getBlacklist':
          return '[]';
        default:
          return null;
      }
    });
  }

  Future<void> mount(WidgetTester tester, List<Message> messages,
      {Brightness brightness = Brightness.light,
      Message? initialSearch,
      bool holdLatest = false,
      List<Message> cacheSeed = const []}) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final message in messages) {
      stored[message.clientMsgID!] = message;
    }
    if (cacheSeed.isNotEmpty) ChatHistoryCache.write('self', 'chat', cacheSeed);
    final arguments = {
      'conversationInfo': ConversationInfo(
        conversationID: 'chat',
        userID: 'peer',
        conversationType: ConversationType.single,
        showName: 'Peer',
        unreadCount: 0,
        groupAtType: GroupAtType.atNormal,
      ),
      if (initialSearch != null) 'searchMessage': initialSearch,
    };
    GetTags.createChatTag();
    _tag = GetTags.chat;
    final wasDark = Styles.isDark;
    Styles.isDark = brightness == Brightness.dark;
    addTearDown(() => Styles.isDark = wasDark);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        navigatorObservers: [routes],
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(brightness: brightness),
        builder: EasyLoading.init(),
        initialRoute: '/search-test-current-chat',
        onGenerateRoute: (_) => _chatRoute(arguments),
        onGenerateInitialRoutes: (_) => [_chatRoute(arguments)],
      ),
    ));
    await tester.idle();
    expect(older, isNotEmpty);
    if (!holdLatest) older.first.complete(messages);
    await pumpFrames(tester);
    if (!holdLatest) expect(logic.scrollController.hasClients, isTrue);
    expect(logic.messageRoute, same(routes.active.single));
  }

  GetPageRoute<void> _chatRoute(Map<String, Object> arguments) =>
      GetPageRoute<void>(
        settings: RouteSettings(
            name: '/search-test-current-chat', arguments: arguments),
        binding:
            BindingsBuilder(() => Get.lazyPut(() => ChatLogic(), tag: _tag)),
        page: () {
          _logic = Get.find<ChatLogic>(tag: _tag);
          return Scaffold(
            key: _chatKey,
            body: SafeArea(
              child: Column(children: [
                Expanded(
                  child: ChatMessageList(
                    logic: logic,
                    messageBuilder: (_, message) => SizedBox(
                      key: ValueKey(message.clientMsgID!),
                      height: message.clientMsgID!.length.isEven ? 91 : 43,
                      child: Center(child: Text(message.clientMsgID!)),
                    ),
                  ),
                ),
                TextField(
                    key: _draftKey,
                    controller: logic.inputCtrl,
                    focusNode: logic.focusNode),
              ]),
            ),
          );
        },
      );

  Future<void> pumpFrames(WidgetTester tester, [int count = 4]) async {
    for (var frame = 0; frame < count; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> selectResult(WidgetTester tester, Message target) async {
    stored[target.clientMsgID!] = target;
    unawaited(Get.to<void>(() => const Scaffold(body: Text('聊天设置')),
        routeName: '/search-test-chat-settings'));
    await tester.pumpAndSettle();
    unawaited(Get.to<void>(() => ChatHistoryResultsPage(
        conversationID: 'chat',
        category: ChatHistoryCategory.date,
        date: _day,
        source: _ResultSource(target))));
    await tester.pumpAndSettle();
    expect(routes.active, hasLength(3));
    await tester
        .tap(find.byKey(ValueKey('chat-history-result-${target.clientMsgID}')));
    await pumpFrames(tester, 20);
    expect(finds, hasLength(1),
        reason: 'The real navigation revalidates the SDK identity.');
    expect(Get.isRegistered<ChatLogic>(tag: _tag), isTrue);
    expect(logic.isClosed, isFalse);
  }

  Future<void> completeAround(WidgetTester tester, Message target) async {
    for (final query in older.where(
        (query) => query.arguments['startClientMsgID'] == target.clientMsgID)) {
      query.complete([
        for (var index = 0; index < 20; index++)
          _message('around-old-$index',
              seq: 60 + index,
              time: _day.add(Duration(hours: 11, minutes: index))),
        target,
      ], isEnd: false);
    }
    for (final query in newer.where(
        (query) => query.arguments['startClientMsgID'] == target.clientMsgID)) {
      query.complete([
        target,
        for (var index = 0; index < 20; index++)
          _message('around-new-$index',
              seq: 81 + index,
              time: _day.add(Duration(hours: 13, minutes: index))),
      ], isEnd: false);
    }
    await pumpFrames(tester, 20);
  }

  Future<void> dispose() async {
    await LoadingView.singleton.dismiss();
    await EasyLoading.dismiss(animation: false);
    ChatHistoryPrefetcher.shared.clear();
    if (_logic != null && !logic.isClosed) logic.onDelete();
    for (final query in [...older, ...newer]) {
      query.complete([]);
    }
    ChatHistoryCache.clear();
    Get.reset();
    if (_tag != null && GetTags.chat == _tag) GetTags.destroyChatTag();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

void _chatTest(
    String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness harness;
  setUp(() async {
    harness = _Harness();
    await harness.initialize();
  });
  tearDown(() => harness.dispose());

  for (final brightness in Brightness.values) {
    _chatTest(
        'loaded search result reuses the real chat, draft and route / ${brightness.name}',
        (tester) async {
      final target = _message('loaded-search-target');
      await harness.mount(tester, [target, ..._latest(180)],
          brightness: brightness);
      final scaffold = tester.state<ScaffoldState>(find.byKey(_chatKey));
      final controller = harness.logic;
      final route = controller.messageRoute;
      final input = controller.inputCtrl;
      await tester.enterText(find.byKey(_draftKey), '搜索返回仍保留草稿');
      expect(find.byKey(ValueKey(target.clientMsgID!)), findsNothing);
      await harness.selectResult(tester, target);
      await tester.pumpAndSettle();
      expect(harness.routes.active, [route]);
      expect(Get.find<ChatLogic>(tag: GetTags.chat), same(controller));
      expect(tester.state<ScaffoldState>(find.byKey(_chatKey)), same(scaffold));
      expect(controller.inputCtrl, same(input));
      expect(input.text, '搜索返回仍保留草稿');
      expectMessageInsideChatList(tester, target.clientMsgID!);
      expect(controller.focusedMessageID.value, target.clientMsgID);
      expect(harness.older, hasLength(1));
      expect(harness.newer, isEmpty);
      expect(harness.finds, hasLength(1));
      await tester.pump(const Duration(seconds: 3));
      expect(controller.focusedMessageID.value, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  _chatTest(
      'unloaded result opens an SDK window and dragging its edges loads both directions',
      (tester) async {
    await harness.mount(tester, _latest());
    final target = _message('unloaded-search-target');
    harness.logic.inputCtrl.text = '上下翻历史也保留草稿';
    await harness.selectResult(tester, target);
    final anchored = [...harness.older, ...harness.newer].where(
        (query) => query.arguments['startClientMsgID'] == target.clientMsgID);
    expect(anchored, hasLength(2));
    for (final query in anchored) {
      expect(query.arguments['conversationID'], 'chat');
      expect(query.arguments['count'], 20);
    }
    await harness.completeAround(tester, target);
    expectMessageInsideChatList(tester, target.clientMsgID!);
    expect(harness.logic.viewingHistory.value, isTrue);
    expect(harness.ids, isNot(contains('latest-29')));
    final arrival = _message('live-during-search-history',
        seq: 2000, time: _today.add(const Duration(hours: 1)));
    harness.im.recvNewMessage(arrival);
    harness.im.recvNewMessage(arrival);
    await tester.pump();
    expect(harness.ids, isNot(contains(arrival.clientMsgID)));
    expect(harness.logic.scrollingCacheMessageList, hasLength(1));

    await tester.drag(find.byType(ChatListView), const Offset(0, 2400));
    await harness.pumpFrames(tester);
    expect(harness.older, hasLength(3),
        reason: 'Touching the older edge pages directly.');
    expect(harness.older.last.arguments['startClientMsgID'], 'around-old-0');
    harness.older.last.complete([
      _message('older-extra',
          seq: 59, time: _day.add(const Duration(hours: 10))),
      harness.logic.messageList.first,
    ]);
    await harness.pumpFrames(tester);
    expect(harness.ids, contains('older-extra'));
    await tester.drag(find.byType(ChatListView), const Offset(0, -4000));
    await harness.pumpFrames(tester);
    expect(harness.newer, hasLength(2),
        reason: 'Touching the newer edge pages directly.');
    expect(harness.newer.last.arguments['startClientMsgID'], 'around-new-19');
    harness.newer.last
        .complete([harness.logic.messageList.last, ..._latest(), arrival]);
    await harness.pumpFrames(tester);
    expect(harness.logic.viewingHistory.value, isFalse);
    expect(harness.logic.scrollingCacheMessageList, isEmpty);
    expect(harness.ids.where((id) => id == arrival.clientMsgID), hasLength(1));
    harness.logic.scrollBottom();
    await tester.pumpAndSettle();
    expectMessageInsideChatList(tester, arrival.clientMsgID!);
    expect(harness.logic.newMessages.unseenCount.value, 0);
    expect(harness.logic.inputCtrl.text, '上下翻历史也保留草稿');
    expect(harness.routes.active, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  _chatTest('chat entry searchMessage supersedes a late initial latest page',
      (tester) async {
    final target = _message('entry-search-target');
    await harness.mount(tester, _latest(),
        initialSearch: target, holdLatest: true);
    expect(harness.older, hasLength(2));
    expect(harness.newer, hasLength(1));
    await harness.completeAround(tester, target);
    expectMessageInsideChatList(tester, target.clientMsgID!);
    expect(harness.logic.focusedMessageID.value, target.clientMsgID);
    final historyIDs = harness.ids;
    harness.older.first.complete(_latest());
    await harness.pumpFrames(tester);
    expect(harness.ids, historyIDs);
    expect(harness.logic.viewingHistory.value, isTrue);
    expect(harness.ids, isNot(contains('latest-29')));
    expect(tester.takeException(), isNull);
  });

  _chatTest(
      'cached entry search target still supersedes the pending initial latest page',
      (tester) async {
    final target = _message('cached-entry-target');
    await harness.mount(tester, _latest(),
        initialSearch: target, holdLatest: true, cacheSeed: [target]);
    expect(harness.older, hasLength(2));
    expect(harness.newer, hasLength(1));
    await harness.completeAround(tester, target);
    expectMessageInsideChatList(tester, target.clientMsgID!);
    expect(harness.logic.focusedMessageID.value, target.clientMsgID);
    final historyIDs = harness.ids;
    harness.older.first.complete(_latest());
    await harness.pumpFrames(tester);
    expect(harness.ids, historyIDs);
    expect(harness.logic.viewingHistory.value, isTrue);
    expect(harness.ids, isNot(contains('latest-29')));
    expect(tester.takeException(), isNull);
  });

  for (final interruption in ['clear', 'close', 'account']) {
    _chatTest('$interruption rejects late search-target history and highlight',
        (tester) async {
      await harness.mount(tester, _latest());
      final target = _message('late-search-target');
      final focus = harness.logic.focusSearchMessage(target);
      await harness.pumpFrames(tester);
      expect(harness.older, hasLength(2));
      expect(harness.newer, hasLength(1));
      if (interruption == 'clear') {
        harness.logic.clearAllMessage();
      } else if (interruption == 'close') {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.logic.onDelete();
      } else {
        OpenIM.iMManager.userID = 'replacement-account';
      }
      await harness.completeAround(tester, target);
      expect(await focus, isFalse);
      expect(harness.logic.focusedMessageID.value, isNull);
      expect(harness.ids, isNot(contains(target.clientMsgID)));
      expect(
          ChatHistoryCache.read('self', 'chat')
              .map((message) => message.clientMsgID),
          isNot(contains(target.clientMsgID)));
      expect(tester.takeException(), isNull);
    });
  }

  _chatTest(
      'expired, deleted and other-chat search targets cannot replace the chat',
      (tester) async {
    await harness.mount(tester, _latest());
    final before = harness.ids;
    final expired = _message('expired-search-target')
      ..attachedInfoElem = AttachedInfoElem(
          isPrivateChat: true,
          hasReadTime: DateTime(2020).millisecondsSinceEpoch,
          burnDuration: 1);
    final deleted = _message('deleted-search-target');
    harness.im.deletedMessages.add(deleted);
    await tester.pump(const Duration(milliseconds: 100));
    for (final target in [
      expired,
      deleted,
      _message('other-chat-target', peer: 'other')
    ]) {
      expect(await harness.logic.focusSearchMessage(target), isFalse);
    }
    expect(harness.ids, before);
    expect(harness.older, hasLength(1));
    expect(harness.newer, isEmpty);
    expect(harness.logic.focusedMessageID.value, isNull);
    expect(tester.takeException(), isNull);
  });
}
