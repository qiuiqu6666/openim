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
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/chat/chat_entry_list.dart';
import '../../support/chat/chat_entry_sdk.dart';

const _channel = MethodChannel('flutter_openim_sdk');
const _chatKey = ValueKey('current-chat-scaffold');
const _draftKey = ValueKey('current-chat-draft');
const _tip = '07:16';
final _today = DateUtils.dateOnly(DateTime.now());
final _day = DateTime(_today.year, _today.month, _today.day - 3);

Message _message(String id, DateTime time, {int seq = 1}) => Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': 'peer',
      'recvID': 'self',
      'senderNickname': 'Peer',
      'seq': seq,
      'sendTime': time.millisecondsSinceEpoch,
      'status': MessageStatus.succeeded,
      'textElem': {'content': id},
    });

List<Message> _latest({int count = 30}) => List.generate(
    count,
    (index) => _message('latest-$index', _today.add(Duration(minutes: index)),
        seq: 1000 + index));

class _PageObserver extends NavigatorObserver {
  final pages = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) pages.add(route);
  }
}

class _SearchCall {
  _SearchCall(this.arguments);
  final Map<String, dynamic> arguments;
  final result = Completer<String>();

  void complete(List<Message> messages) {
    if (result.isCompleted) return;
    result.complete(jsonEncode(SearchResult(
      totalCount: messages.length,
      searchResultItems: [
        SearchResultItems(conversationID: 'chat', messageList: messages),
      ],
    ).toJson()));
  }
}

extension _FailHistoryCall on EntryHistoryCall {
  void completeError() {
    if (result.isCompleted) return;
    result.completeError(PlatformException(
        code: 'history-unavailable', message: 'SDK history unavailable'));
  }
}

class _Harness {
  final observer = _PageObserver();
  final older = <EntryHistoryCall>[];
  final newer = <EntryHistoryCall>[];
  // The calendar asks for one matching record per day; the subsequent timeline
  // anchor lookup still uses the manually completed 20-record search below.
  final dateProbes = <_SearchCall>[];
  final calendarRecords = <Message>[];
  final searches = <_SearchCall>[];
  final findCalls = <MethodCall>[];
  late EntryTestIM im;
  ChatLogic? _logic;
  late Message tipMessage;
  Future<void>? timelineAction;

  ChatLogic get logic => _logic!;
  List<String?> get ids => logic.messageList.map((m) => m.clientMsgID).toList();

  Future<void> initialize() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    ChatHistoryPrefetcher.shared.clear();
    ChatHistoryCache.clear();
    Get.put<AppController>(EntryTestApp());
    im = Get.put<IMController>(EntryTestIM()) as EntryTestIM;
    Get.put<ConversationLogic>(EntryTestConversation());
    Get.put<CacheController>(EntryTestCache());
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
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
        case 'searchLocalMessages':
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          final query = _SearchCall(
              Map<String, dynamic>.from(arguments['filter'] as Map));
          if (query.arguments['count'] == 1) {
            dateProbes.add(query);
            _completeDateProbe(query);
          } else {
            searches.add(query);
          }
          return query.result.future;
        case 'findMessageList':
          findCalls.add(call);
          return jsonEncode({'totalCount': 0, 'findResultItems': []});
        case 'getBlacklist':
          return '[]';
        default:
          return null;
      }
    });
  }

  void _completeDateProbe(_SearchCall query) {
    final filter = query.arguments;
    expect(filter['conversationID'], 'chat');
    expect(filter['count'], 1);
    expect(filter['messageTypeList'], contains(MessageType.text));
    final end = (filter['searchTimePosition'] as int) * 1000;
    final start = end - (filter['searchTimePeriod'] as int) * 1000;
    expect(end, greaterThan(start));
    final records = <String, Message>{
      for (final message in calendarRecords)
        if (message.clientMsgID != null &&
            message.sendTime != null &&
            message.sendTime! >= start &&
            message.sendTime! <= end)
          message.clientMsgID!: message,
    }.values.toList()
      ..sort((a, b) => b.sendTime!.compareTo(a.sendTime!));
    final page = filter['pageIndex'] as int;
    // Match the SDK's inclusive upper bound and raw-page cursor. The production
    // availability controller filters next-midnight records before selection.
    query.complete(records.skip(page - 1).take(1).toList());
  }

  Future<void> mount(WidgetTester tester, List<Message> messages,
      {Brightness brightness = Brightness.light}) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    calendarRecords.addAll(messages);
    tipMessage = messages.last;
    Get.routing.args = {
      'conversationInfo': ConversationInfo(
        conversationID: 'chat',
        userID: 'peer',
        conversationType: ConversationType.single,
        showName: 'Peer',
        unreadCount: 0,
        groupAtType: GroupAtType.atNormal,
      ),
    };
    _logic = Get.put(ChatLogic(), tag: 'date-jump-in-place-test');
    await tester.idle();
    expect(older, hasLength(1));
    older.single.complete(messages);
    final wasDark = Styles.isDark;
    Styles.isDark = brightness == Brightness.dark;
    addTearDown(() => Styles.isDark = wasDark);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        navigatorObservers: [observer],
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(brightness: brightness),
        builder: EasyLoading.init(),
        home: Builder(builder: (context) {
          return Scaffold(
            key: _chatKey,
            body: SafeArea(
              child: Column(children: [
                ChatItemContainer(
                  id: 'tap-date-tip',
                  timelineStr: _tip,
                  timelineSemanticLabel: 'chatJumpToDate'.tr,
                  onTapTimeline: () {
                    timelineAction = logic.onTapTimeline(context, tipMessage);
                  },
                  timeStr: '07:17',
                  isBubbleBg: true,
                  isISend: true,
                  hasRead: true,
                  isSending: false,
                  isSendFailed: false,
                  child: const Text('最近消息'),
                ),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: logic.onChatScrollNotification,
                    child: Obx(() {
                      final rows = logic.messageList.reversed.toList();
                      final ids = rows.map((m) => m.clientMsgID!).toList();
                      final indices = <String, int>{
                        for (var index = 0; index < ids.length; index++)
                          ids[index]: index,
                      };
                      return ChatListView(
                        controller: logic.scrollController,
                        positionController: logic.messagePositionController,
                        loadOnInit: false,
                        hasMore: false,
                        itemCount: rows.length,
                        messageIDs: ids,
                        onViewportChanged: logic.onChatViewportChanged,
                        findChildIndexCallback: (key) =>
                            key is ValueKey<String> ? indices[key.value] : null,
                        itemBuilder: (_, index) => SizedBox(
                          key: ValueKey(ids[index]),
                          height: ids[index].length.isEven ? 91 : 43,
                          child: Center(child: Text(ids[index])),
                        ),
                      );
                    }),
                  ),
                ),
                TextField(
                  key: _draftKey,
                  controller: logic.inputCtrl,
                  focusNode: logic.focusNode,
                ),
              ]),
            ),
          );
        }),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(logic.scrollController.hasClients, isTrue);
    expect(observer.pages, hasLength(1));
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.text(_tip));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
  }

  Future<void> selectDate(WidgetTester tester,
      {DateTime? date, Message? availableRecord}) async {
    final firstProbe = dateProbes.length;
    if (availableRecord != null) calendarRecords.add(availableRecord);
    await openPicker(tester);
    final selected = date ?? _day;
    var picker =
        tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    if (!DateUtils.isSameMonth(
        picker.initialDate ?? picker.currentDate, selected)) {
      picker.onDisplayedMonthChanged!(DateTime(selected.year, selected.month));
      await tester.pumpAndSettle();
      picker =
          tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    }
    expect(picker.selectableDayPredicate!(selected), isTrue);
    picker.onDateChanged(selected);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    if (availableRecord != null) {
      final nextMidnight =
          DateTime(selected.year, selected.month, selected.day + 1);
      expect(
          dateProbes.skip(firstProbe).where((query) =>
              query.arguments['searchTimePosition'] ==
              nextMidnight.millisecondsSinceEpoch ~/ 1000),
          hasLength(2),
          reason:
              'A remote day is queried for the month and rechecked on tap.');
    }
  }

  Future<void> completeAround(WidgetTester tester, Message target,
      {bool moreNewer = true, int attempts = 1}) async {
    // The two directions may be issued together or in sequence; finish the
    // first page before advancing the widget frame that receives the other.
    final olderRows = List.generate(
        20,
        (index) => _message(
            'old-$index', _day.add(Duration(hours: 8, minutes: index)),
            seq: index + 1));
    final newerRows = List.generate(
        20,
        (index) => _message(
            'newer-$index', _day.add(Duration(days: 1, minutes: index)),
            seq: index + 100));
    for (var frame = 0; frame < 8; frame++) {
      for (final query in older.where((query) =>
          query.arguments['startClientMsgID'] == target.clientMsgID)) {
        query.complete([...olderRows, target], isEnd: false);
      }
      for (final query in newer.where((query) =>
          query.arguments['startClientMsgID'] == target.clientMsgID)) {
        query.complete([target, ...newerRows], isEnd: !moreNewer);
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    final anchored = [...older, ...newer].where(
        (query) => query.arguments['startClientMsgID'] == target.clientMsgID);
    expect(anchored, hasLength(attempts * 2));
    for (final query in anchored) {
      expect(query.arguments['conversationID'], 'chat');
      expect(query.arguments['count'], inInclusiveRange(1, 40));
    }
    await tester.pumpAndSettle();
  }

  Future<void> enterHistory(WidgetTester tester, Message target) async {
    await selectDate(tester, availableRecord: target);
    expect(searches, hasLength(1));
    searches.single.complete([target]);
    await tester.pump(const Duration(milliseconds: 20));
    await completeAround(tester, target);
    expect(logic.viewingHistory.value, isTrue);
    expectMessageInsideChatList(tester, target.clientMsgID!);
  }

  Future<void> dispose() async {
    await LoadingView.singleton.dismiss();
    await EasyLoading.dismiss(animation: false);
    ChatHistoryPrefetcher.shared.clear();
    if (_logic != null && !logic.isClosed) logic.onDelete();
    for (final query in [...older, ...newer]) {
      query.complete([]);
    }
    for (final query in [...dateProbes, ...searches]) {
      query.complete([]);
    }
    ChatHistoryCache.clear();
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
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
    testWidgets(
        'date tip seeks an offscreen loaded message in the same chat / ${brightness.name}',
        (tester) async {
      final target =
          _message('loaded-target', _day.add(const Duration(hours: 23)));
      await harness.mount(tester, [target, ..._latest(count: 180)],
          brightness: brightness);
      final scaffold = tester.state<ScaffoldState>(find.byKey(_chatKey));
      final input = harness.logic.inputCtrl;
      await tester.enterText(find.byKey(_draftKey), '保留未发送草稿');
      expect(find.byKey(ValueKey(target.clientMsgID!)), findsNothing);
      await harness.selectDate(tester);
      await tester.pumpAndSettle();
      await harness.timelineAction;

      expect(find.byKey(ValueKey(target.clientMsgID!)), findsWidgets);
      expectMessageInsideChatList(tester, target.clientMsgID!);
      final position = harness.logic.scrollController.position;
      expect(position.pixels - position.minScrollExtent, greaterThan(100));
      expect(harness.searches, isEmpty);
      expect(harness.findCalls, isEmpty);
      expect(harness.older, hasLength(1));
      expect(harness.newer, isEmpty);
      expect(harness.observer.pages, hasLength(1));
      expect(tester.state<ScaffoldState>(find.byKey(_chatKey)), same(scaffold));
      expect(harness.logic.inputCtrl, same(input));
      expect(input.text, '保留未发送草稿');
      expect(harness.logic.viewingHistory.value, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('SDK date search replaces only the current chat message window',
      (tester) async {
    await harness.mount(tester, _latest());
    final scaffold = tester.state<ScaffoldState>(find.byKey(_chatKey));
    final input = harness.logic.inputCtrl;
    await tester.enterText(find.byKey(_draftKey), '历史定位仍保留草稿');
    final target = _message(
        'sdk-date-target', _day.add(const Duration(hours: 23)),
        seq: 80);

    await harness.enterHistory(tester, target);

    final query = harness.searches.single.arguments;
    final nextDay = DateTime(_day.year, _day.month, _day.day + 1);
    expect(query['conversationID'], 'chat');
    expect(query['searchTimePosition'], nextDay.millisecondsSinceEpoch ~/ 1000);
    expect(query['searchTimePeriod'],
        (nextDay.millisecondsSinceEpoch - _day.millisecondsSinceEpoch) ~/ 1000);
    expect(query['messageTypeList'], contains(MessageType.text));
    expect(query['pageIndex'], 1);
    expect(query['count'], 20);
    expect(harness.ids, isNot(contains('latest-29')));
    expect(harness.ids.where((id) => id == target.clientMsgID), hasLength(1));
    expect(harness.ids.length, lessThanOrEqualTo(81));
    expect(harness.logic.historyNewerHasMore.value, isTrue);
    expect(harness.observer.pages, hasLength(1));
    expect(tester.state<ScaffoldState>(find.byKey(_chatKey)), same(scaffold));
    expect(harness.logic.inputCtrl, same(input));
    expect(input.text, '历史定位仍保留草稿');
    expect(find.byType(CalendarDatePicker), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'history buffers live messages, pages newer, and returns to latest',
      (tester) async {
    await harness.mount(tester, _latest());
    final target = _message(
        'historical-anchor', _day.add(const Duration(hours: 23)),
        seq: 80);
    await harness.enterHistory(tester, target);
    final historicalIDs = harness.ids;
    final before =
        tester.getRect(find.byKey(ValueKey(target.clientMsgID!)).first);
    final arrival = _message(
        'live-while-historical', _today.add(const Duration(hours: 1)),
        seq: 2000);

    harness.im.recvNewMessage(arrival);
    harness.im.recvNewMessage(arrival);
    await tester.pump();
    await tester.pump();

    expect(harness.ids, historicalIDs);
    expect(harness.logic.scrollingCacheMessageList, hasLength(1));
    expect(harness.logic.newMessages.unseenCount.value, 1);
    expect(harness.logic.newMessages.awayFromLatest.value, isTrue);
    final after =
        tester.getRect(find.byKey(ValueKey(target.clientMsgID!)).first);
    expect(after.top, closeTo(before.top, .5));
    expect(after.bottom, closeTo(before.bottom, .5));

    final loadNewer = harness.logic.onScrollToTopLoad();
    await tester.idle();
    expect(harness.newer, hasLength(2));
    expect(harness.newer.last.arguments['startClientMsgID'], 'newer-19');
    harness.newer.last.complete([
      harness.logic.messageList.last,
      _message('newer-next-page', _day.add(const Duration(days: 2)), seq: 200),
    ], isEnd: false);
    await loadNewer;
    await tester.pump();
    expect(harness.ids, contains('newer-next-page'));
    expect(harness.ids, contains(target.clientMsgID));
    expect(harness.ids, isNot(contains(arrival.clientMsgID)));

    harness.logic.scrollBottom();
    await tester.idle();
    expect(harness.older, hasLength(3));
    expect(harness.older.last.arguments['startClientMsgID'], '');
    harness.older.last.complete([..._latest(), arrival]);
    await tester.pumpAndSettle();

    expect(harness.logic.viewingHistory.value, isFalse);
    expect(harness.logic.scrollingCacheMessageList, isEmpty);
    expect(harness.logic.newMessages.unseenCount.value, 0);
    expect(harness.logic.newMessages.awayFromLatest.value, isFalse);
    expect(harness.ids.where((id) => id == arrival.clientMsgID), hasLength(1));
    expect(harness.ids, isNot(contains(target.clientMsgID)));
    expectMessageInsideChatList(tester, arrival.clientMsgID!);
    expect(harness.observer.pages, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('retrying a failed date window positions the selected message',
      (tester) async {
    await harness.mount(tester, _latest());
    final latestIDs = harness.ids;
    final input = harness.logic.inputCtrl;
    input.text = '日期定位重试仍保留草稿';
    final target =
        _message('retry-date-target', _day.add(const Duration(hours: 23)));
    await harness.selectDate(tester, availableRecord: target);
    harness.searches.single.complete([target]);
    await tester.pump(const Duration(milliseconds: 20));
    expect(harness.older, hasLength(2));
    expect(harness.newer, hasLength(1));
    harness.older.last.completeError();
    harness.newer.last.complete([target], isEnd: false);
    await tester.pumpAndSettle();
    await harness.timelineAction;

    expect(harness.ids, latestIDs);
    expect(harness.logic.historyLoading.value, isFalse);
    expect(harness.logic.historyError.value, isNotNull);
    expect(harness.logic.viewingHistory.value, isFalse);
    await EasyLoading.dismiss(animation: false);

    harness.logic.retryHistory();
    await tester.pump(const Duration(milliseconds: 20));
    expect(harness.older, hasLength(3));
    expect(harness.newer, hasLength(2));
    expect(
        harness.older.last.arguments['startClientMsgID'], target.clientMsgID);
    expect(
        harness.newer.last.arguments['startClientMsgID'], target.clientMsgID);
    await harness.completeAround(tester, target, attempts: 2);

    expectMessageInsideChatList(tester, target.clientMsgID!);
    expect(harness.ids, isNot(contains('latest-29')));
    expect(harness.logic.historyLoading.value, isFalse);
    expect(harness.logic.historyError.value, isNull);
    expect(harness.logic.viewingHistory.value, isTrue);
    expect(harness.logic.inputCtrl, same(input));
    expect(input.text, '日期定位重试仍保留草稿');
    expect(harness.searches, hasLength(1));
    expect(harness.observer.pages, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('retrying a failed latest return flushes buffered live messages',
      (tester) async {
    await harness.mount(tester, _latest());
    final target =
        _message('retry-latest-anchor', _day.add(const Duration(hours: 23)));
    await harness.enterHistory(tester, target);
    final historicalIDs = harness.ids;
    harness.logic.inputCtrl.text = '返回最新重试仍保留草稿';

    harness.logic.scrollBottom();
    await tester.idle();
    expect(harness.older, hasLength(3));
    expect(harness.older.last.arguments['startClientMsgID'], '');
    final arrival = _message(
        'live-during-failed-return', _today.add(const Duration(hours: 1)),
        seq: 2000);
    harness.im.recvNewMessage(arrival);
    harness.older.last.completeError();
    await tester.pumpAndSettle();

    expect(harness.ids, historicalIDs);
    expect(harness.logic.historyLoading.value, isFalse);
    expect(harness.logic.historyError.value, isNotNull);
    expect(harness.logic.viewingHistory.value, isTrue);
    expect(harness.logic.scrollingCacheMessageList.single.clientMsgID,
        arrival.clientMsgID);
    expect(harness.logic.newMessages.unseenCount.value, 1);
    expect(harness.ids, isNot(contains(arrival.clientMsgID)));

    harness.logic.retryHistory();
    await tester.idle();
    expect(harness.older, hasLength(4));
    expect(harness.older.last.arguments['startClientMsgID'], '');
    harness.im.recvNewMessage(arrival);
    harness.older.last.complete(_latest());
    await tester.pumpAndSettle();

    expect(harness.logic.viewingHistory.value, isFalse);
    expect(harness.logic.historyLoading.value, isFalse);
    expect(harness.logic.historyError.value, isNull);
    expect(harness.logic.scrollingCacheMessageList, isEmpty);
    expect(harness.logic.newMessages.unseenCount.value, 0);
    expect(harness.logic.newMessages.awayFromLatest.value, isFalse);
    expect(harness.ids.where((id) => id == arrival.clientMsgID), hasLength(1));
    expect(harness.ids, isNot(contains(target.clientMsgID)));
    expectMessageInsideChatList(tester, arrival.clientMsgID!);
    expect(harness.logic.inputCtrl.text, '返回最新重试仍保留草稿');
    expect(harness.observer.pages, hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    harness.logic.onDelete();
  });

  testWidgets('canceling or choosing an empty date preserves the current chat',
      (tester) async {
    await harness.mount(tester, _latest());
    harness.logic.scrollController.jumpTo(200);
    await tester.pump();
    final before = harness.ids;
    final offset = harness.logic.scrollController.offset;
    harness.logic.inputCtrl.text = '取消后仍有草稿';

    await harness.openPicker(tester);
    await tester.tap(find.byKey(const ValueKey('chat-date-picker-cancel')));
    await tester.pumpAndSettle();
    expect(harness.searches, isEmpty);
    expect(harness.ids, before);
    expect(harness.logic.scrollController.offset, offset);

    // The day exists during calendar verification, then disappears before the
    // separately requested timeline anchor returns, as can happen after delete.
    await harness.selectDate(tester,
        availableRecord: _message(
            'removed-before-anchor', _day.add(const Duration(hours: 23))));
    harness.searches.single.complete([]);
    await tester.pumpAndSettle();
    expect(harness.ids, before);
    expect(harness.logic.scrollController.offset, offset);
    expect(harness.logic.inputCtrl.text, '取消后仍有草稿');
    expect(harness.observer.pages, hasLength(1));
    expect(harness.older, hasLength(1));
    expect(harness.newer, isEmpty);
    expect(harness.logic.viewingHistory.value, isFalse);
    expect(find.text('chatDateHistoryEmpty'.tr), findsOneWidget);
    expect(tester.takeException(), isNull);
    await EasyLoading.dismiss(animation: false);
  });

  testWidgets(
      'a user drag cancels a pending date window without replacing chat',
      (tester) async {
    await harness.mount(tester, _latest());
    final latestIDs = harness.ids;
    harness.logic.inputCtrl.text = '拖动取消后保留草稿';
    final target =
        _message('canceled-date-target', _day.add(const Duration(hours: 23)));
    await harness.selectDate(tester, availableRecord: target);
    harness.searches.single.complete([target]);
    await tester.pump(const Duration(milliseconds: 20));
    expect(harness.older, hasLength(2));
    expect(harness.newer, hasLength(1));
    expect(harness.logic.historyLoading.value, isTrue);

    final arrival = _message(
        'live-during-canceled-seek', _today.add(const Duration(hours: 1)),
        seq: 2000);
    harness.im.recvNewMessage(arrival);
    expect(harness.logic.scrollingCacheMessageList, hasLength(1));
    expect(harness.ids, latestIDs);

    await tester.drag(find.byType(ChatListView), const Offset(0, 120));
    await tester.pump();
    harness.older.last.complete([target], isEnd: false);
    harness.newer.last.complete([target], isEnd: false);
    await tester.pumpAndSettle();
    await harness.timelineAction;

    expect(harness.ids, [...latestIDs, arrival.clientMsgID]);
    expect(harness.logic.scrollingCacheMessageList, isEmpty);
    expect(harness.ids, isNot(contains(target.clientMsgID)));
    expect(harness.logic.historyLoading.value, isFalse);
    expect(harness.logic.viewingHistory.value, isFalse);
    expect(harness.logic.inputCtrl.text, '拖动取消后保留草稿');
    expect(harness.observer.pages, hasLength(1));
    await harness.openPicker(tester);
    await tester.tap(find.byKey(const ValueKey('chat-date-picker-cancel')));
    await tester.pumpAndSettle();
    expect(harness.searches, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final close in [false, true]) {
    for (final stage in ['date lookup', 'anchor history']) {
      testWidgets('${close ? 'close' : 'clear'} rejects late $stage results',
          (tester) async {
        await harness.mount(tester, _latest());
        final target =
            _message('stale-date-target', _day.add(const Duration(hours: 23)));
        await harness.selectDate(tester, availableRecord: target);
        expect(harness.searches, hasLength(1));
        if (stage == 'anchor history') {
          harness.searches.single.complete([target]);
          await tester.pump(const Duration(milliseconds: 20));
          expect(harness.older.length, greaterThan(1));
        }

        if (close) {
          await tester.pumpWidget(const SizedBox.shrink());
          harness.logic.onDelete();
        } else {
          harness.logic.clearAllMessage();
        }
        harness.searches.single.complete([target]);
        for (final query in [...harness.older.skip(1), ...harness.newer]) {
          query.complete([target], isEnd: false);
        }
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(harness.ids, isNot(contains(target.clientMsgID)));
        expect(harness.logic.scrollingCacheMessageList, isEmpty);
        expect(harness.observer.pages, hasLength(1));
        expect(ChatHistoryCache.read('self', 'chat').map((m) => m.clientMsgID),
            isNot(contains(target.clientMsgID)));
        if (!close) {
          expect(harness.ids, isEmpty);
          expect(harness.logic.viewingHistory.value, isFalse);
        }
        if (stage == 'date lookup') {
          expect(harness.older, hasLength(1));
          expect(harness.newer, isEmpty);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
