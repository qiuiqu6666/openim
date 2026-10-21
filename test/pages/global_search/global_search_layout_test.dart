import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/global_search/global_search_logic.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_page.dart';
import 'package:openim/pages/global_search/cloud/global_keyword_search_api.dart';
import 'package:openim/pages/chat/history_search/cloud/search_http_client.dart';
import 'package:openim/pages/global_search/global_search_view.dart';
import 'package:openim/pages/official_account/widgets/official_account_name_label.dart';
import 'package:openim/pages/group_features/identity/group_name_label.dart';
import 'package:openim_common/openim_common.dart';

const _previewOutput = String.fromEnvironment('GLOBAL_SEARCH_PREVIEW');
bool _previewFontsLoaded = false;

class _Source extends GlobalSearchSource {
  final previews = <ConversationInfo>[].obs;
  @override
  Iterable<ConversationInfo> get currentConversations => previews;
  final calls = <String, int>{};
  Completer<List<FriendInfo>>? pendingFriends;
  bool failFiles = false;
  List<FriendInfo>? friendResults;
  List<GroupInfo>? groupResults;
  List<ConversationInfo>? conversationResults;

  void _count(String section) =>
      calls.update(section, (count) => count + 1, ifAbsent: () => 1);

  @override
  Future<List<FriendInfo>> friends(String query) async {
    _count('contacts');
    if (pendingFriends != null) return pendingFriends!.future;
    return friendResults ?? [FriendInfo(userID: 'friend', nickname: '冬')];
  }

  @override
  Future<List<GroupInfo>> groups(String query) async {
    _count('groups');
    return groupResults ?? [GroupInfo(groupID: 'group', groupName: '搜索群聊')];
  }

  @override
  Future<List<ConversationInfo>> conversations(String query) async {
    _count('conversations');
    return conversationResults ??
        [
          ConversationInfo(
              conversationID: 'group-conversation',
              groupID: 'group',
              conversationType: ConversationType.superGroup,
              showName: '有草稿的群会话',
              draftText: '明天下午一起讨论新方案',
              unreadCount: 0),
        ];
  }

  @override
  Future<List<SearchResultItems>> messages(String query, bool files) async {
    _count(files ? 'files' : 'messages');
    if (!files && failFiles) throw StateError('offline');
    return files
        ? [_result('群聊测试', 0, files: true)]
        : List.generate(9, (i) => _result(i == 0 ? '群聊测试' : '测试群聊 $i', i));
  }
}

SearchResultItems _result(String name, int index, {bool files = false}) =>
    SearchResultItems.fromJson({
      'conversationID': 'group-$index',
      'conversationType': ConversationType.superGroup,
      'showName': name,
      'messageCount': 7,
      'messageList': [
        {
          'clientMsgID': 'message-$index',
          'contentType': files ? MessageType.file : MessageType.text,
          'sessionType': ConversationType.superGroup,
          'sendID': 'friend',
          'recvID': 'group-$index',
          'senderNickname': '冬',
          'textElem': {'content': '@冬 帮我看看这份资料，这是一段用于预览的较长聊天摘要'},
          'fileElem': {'fileName': '团队报告.pdf', 'fileSize': 128000},
        }
      ],
    });

Finder get _header => find.byKey(const ValueKey('global-search-header'));
Finder get _results => find.byType(ListView);
Finder _section(int id) => find.byKey(ValueKey('global-search-section-$id'));
Finder _row(String title) => find.byWidgetPredicate((widget) =>
    widget is ListTile &&
    (widget.title is Text && (widget.title! as Text).data == title ||
        widget.title is OfficialAccountNameLabel &&
            (widget.title! as OfficialAccountNameLabel).name == title ||
        widget.title is GroupNameLabel &&
            (widget.title! as GroupNameLabel).name == title));
Future<GlobalSearchLogic> _mount(WidgetTester tester, _Source source,
    {GlobalKeywordSearchApi? keywordApi,
    bool dark = false,
    Size size = const Size(375, 812),
    double scale = 1,
    GlobalKey? boundary}) async {
  Get.testMode = true;
  Styles.isDark = dark;
  final logic =
      Get.put(GlobalSearchLogic(source: source, keywordApi: keywordApi));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (_previewOutput.isNotEmpty && !_previewFontsLoaded) {
    await tester.runAsync(_loadPreviewFonts);
    _previewFontsLoaded = true;
  }
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) {
        final brightness = dark ? Brightness.dark : Brightness.light;
        final app = GetMaterialApp(
            debugShowCheckedModeBanner: false,
            translations: TranslationService(),
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: ThemeData(
                fontFamily: _previewOutput.isEmpty ? null : 'SearchLayoutFont',
                brightness: brightness,
                colorScheme: ColorScheme.fromSeed(
                        seedColor: const Color(0xFF0089FF),
                        brightness: brightness,
                        surface: dark ? const Color(0xFF202A36) : Colors.white)
                    .copyWith(
                        onSurface: dark
                            ? const Color(0xFFE8EDF5)
                            : const Color(0xFF0C1C33))),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    padding: const EdgeInsets.only(top: 24, bottom: 34),
                    textScaler: TextScaler.linear(scale)),
                child: child!),
            home: GlobalSearchPage());
        return boundary == null
            ? app
            : RepaintBoundary(key: boundary, child: app);
      }));
  await tester.pumpAndSettle();
  return logic;
}

Future<void> _search(WidgetTester tester, {String query = '1'}) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  Get.find<GlobalSearchLogic>().focusNode.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String category) async {
  final labels = [
    StrRes.globalSearchContacts,
    StrRes.groupChat,
    'globalSearchConversations'.tr,
    StrRes.globalSearchChatHistory
  ];
  final scrollable =
      find.descendant(of: _results, matching: find.byType(Scrollable)).first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(_section(labels.indexOf(category) + 1), 80,
      scrollable: scrollable);
  await tester.pumpAndSettle();
  expect(find.byType(ChoiceChip), findsNothing);
}

void _expectTopSection(WidgetTester tester, int id, String firstTitle) {
  final viewport = tester.getRect(_results);
  final section = tester.getRect(_section(id));
  final row = tester.getRect(_row(firstTitle));
  expect(section.top, greaterThanOrEqualTo(viewport.top - 1));
  expect(section.bottom, lessThanOrEqualTo(row.top));
  expect(row.bottom, lessThan(viewport.bottom));
  final title = find.descendant(of: _section(id), matching: find.byType(Text));
  expect(tester.getRect(title).top, greaterThanOrEqualTo(section.top));
  expect(tester.getRect(title).bottom, lessThanOrEqualTo(section.bottom));
}

void main() {
  testWidgets('channels have their own result section and subscriber counts', (tester) async {
    final source = _Source()
      ..friendResults = []
      ..conversationResults = []
      ..groupResults = [
        GroupInfo(groupID: 'g', groupName: '普通群'),
        GroupInfo(groupID: 'c', groupName: '新闻频道', memberCount: 2,
          ex: '{"conversationKind":"channel"}'),
      ];
    await _mount(tester, source);
    await _search(tester);
    expect(find.byKey(const ValueKey('global-search-section-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('global-search-section-5')), findsOneWidget);
    expect(find.text('频道'), findsOneWidget);
    expect(find.text('新闻频道'), findsOneWidget);
    expect(find.text('2 位订阅者'), findsOneWidget);
    expect(find.text('普通群'), findsOneWidget);
  });
  testWidgets('footer reflects remaining cloud history and completion',
      (tester) async {
    final logic = await _mount(tester, _Source());
    await _search(tester);
    final scrollable =
        find.descendant(of: _results, matching: find.byType(Scrollable)).first;
    final end = find.byKey(const ValueKey('global-search-no-more'));
    await tester.scrollUntilVisible(end, 200, scrollable: scrollable);
    expect(find.text('chatSearchNoMore'.tr), findsOneWidget);
    expect(
        find.byKey(const ValueKey('global-history-cloud-more')), findsNothing);
    logic.cloudHasMore.value = true;
    await tester.pumpAndSettle();
    expect(end, findsNothing);
    expect(find.byKey(const ValueKey('global-history-cloud-more')),
        findsOneWidget);
    logic.cloudHasMore.value = false;
    logic.failures.add(4);
    await tester.pumpAndSettle();
    expect(end, findsNothing);
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });

  testWidgets('group results show live last message instead of group ID',
      (tester) async {
    OpenIM.iMManager.userID = 'me';
    final source = _Source();
    ConversationInfo preview(String text) => ConversationInfo(
        conversationID: 'sg_group',
        groupID: 'group',
        conversationType: ConversationType.superGroup,
        latestMsg: Message(
            contentType: MessageType.text,
            sendID: 'me',
            textElem: TextElem(content: text)));
    source.previews.add(preview('最后一条消息'));
    await _mount(tester, source);
    await _search(tester);
    await _select(tester, StrRes.groupChat);
    expect(find.text('最后一条消息'), findsOneWidget);
    expect(find.text('group'), findsNothing);
    source.previews.assignAll([preview('新收到的消息')]);
    await tester.pumpAndSettle();
    expect(find.text('新收到的消息'), findsOneWidget);
    source.previews.clear();
    await tester.pumpAndSettle();
    expect(find.text('新收到的消息'), findsNothing);
    expect(find.text('group'), findsNothing);
  });

  testWidgets('contact and conversation badges use identity and keep remarks',
      (tester) async {
    final source = _Source()
      ..friendResults = [
        FriendInfo(userID: '99Message', nickname: '99Message', remark: '公告备注'),
        FriendInfo(userID: 'ordinary', nickname: '99Message'),
        FriendInfo(
            userID: 'server-official',
            nickname: '运营通知',
            ex: '{"accountType":"official","officialRole":"message"}'),
      ]
      ..conversationResults = [
        ConversationInfo(
            conversationID: 'si_99Pay_self',
            userID: '99Pay',
            showName: '支付通知',
            conversationType: ConversationType.single),
        ConversationInfo(
            conversationID: 'group-99Message',
            groupID: '99Message',
            userID: '99Message',
            showName: '99Message群',
            ex: '{"accountType":"official"}',
            conversationType: ConversationType.superGroup),
      ];
    Finder badges() => find.byWidgetPredicate((widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage)
            .assetName
            .endsWith('official_account_verified.png'));
    await _mount(tester, source);
    await _search(tester);
    await _select(tester, StrRes.globalSearchContacts);
    expect(find.text('公告备注'), findsOneWidget);
    final ordinary = find.byWidgetPredicate((widget) =>
        widget is OfficialAccountNameLabel && widget.userID == 'ordinary');
    expect(ordinary, findsOneWidget);
    expect(find.descendant(of: ordinary, matching: find.text('99Message')),
        findsOneWidget);
    expect(badges(), findsNWidgets(3));
    expect(find.descendant(of: ordinary, matching: badges()), findsNothing);
    await _select(tester, 'globalSearchConversations'.tr);
    expect(badges(), findsAtLeastNWidgets(1));
    expect(find.descendant(of: _row('99Message群'), matching: badges()),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cloud history groups conversations and opens scoped results',
      (tester) async {
    final source = _Source()
      ..friendResults = []
      ..groupResults = []
      ..conversationResults = [];
    source.previews.assignAll([
      ConversationInfo(
          conversationID: 'sg_a',
          groupID: 'a',
          conversationType: ConversationType.superGroup,
          showName: '匹配群聊'),
      ConversationInfo(
          conversationID: 'si_b',
          userID: 'b',
          conversationType: ConversationType.single,
          showName: '匹配单聊'),
    ]);
    final keywordApi = GlobalKeywordSearchApi(
        client: SearchHttpClient(
      session: () =>
          (user: 'self', token: 'im', server: 'https://example.test'),
      post: (_, __, ___) async => {
        'errCode': 0,
        'data': {
          'items': [
            for (final entry in [('sg_a', 3), ('sg_a', 2), ('si_b', 1)])
              {
                'conversationID': entry.$1,
                'seq': entry.$2,
                'clientMsgID': 'm${entry.$2}',
                'sendID': 'sender',
                'sendTime': 1000,
                'contentType': 101,
                'summary': '匹配内容'
              }
          ],
          'nextCursor': '',
          'hasMore': false,
        }
      },
    ));
    await _mount(tester, source, keywordApi: keywordApi);
    await _search(tester, query: '会议');
    expect(find.text('匹配群聊'), findsOneWidget);
    expect(find.text('匹配单聊'), findsOneWidget);
    expect(find.text('匹配内容'), findsNWidgets(2));
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.token = null;
    await tester.tap(find.text('匹配群聊'));
    await tester.pumpAndSettle();
    final page = tester
        .widget<ChatHistorySearchPage>(find.byType(ChatHistorySearchPage));
    expect(page.conversationID, 'sg_a');
    expect(page.initialQuery, '会议');
    expect(page.isGroup, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('empty result titles stay centered as previews appear: $dark',
        (tester) async {
      final source = _Source()
        ..friendResults = []
        ..conversationResults = [
          ConversationInfo(
              conversationID: 'empty',
              showName: '空摘要会话',
              conversationType: ConversationType.single),
        ];
      await _mount(tester, source, dark: dark);
      await _search(tester);
      for (final title in ['搜索群聊', '空摘要会话']) {
        final row = _row(title);
        final text = find.descendant(of: row, matching: find.text(title));
        final avatar =
            find.descendant(of: row, matching: find.byType(AvatarView));
        expect(tester.widget<ListTile>(row).subtitle, isNull);
        expect(tester.getCenter(text).dy,
            closeTo(tester.getCenter(avatar).dy, .5));
        expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      }
      source.previews.add(ConversationInfo(
          conversationID: 'sg_group',
          groupID: 'group',
          conversationType: ConversationType.superGroup,
          latestMsg: Message(
              contentType: MessageType.text,
              textElem: TextElem(content: '新收到的消息'))));
      await tester.pumpAndSettle();
      expect(find.text('新收到的消息'), findsOneWidget);
      expect(tester.widget<ListTile>(_row('搜索群聊')).subtitle, isNotNull);
      source.previews.clear();
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('搜索群聊')).dy,
          closeTo(tester.getCenter(_row('搜索群聊')).dy, .5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('first result and category headers are fully visible: $dark',
        (tester) async {
      final source = _Source();
      await _mount(tester, source, dark: dark);
      await _search(tester);
      _expectTopSection(tester, 1, '冬');
      await _select(tester, StrRes.globalSearchChatHistory);
      _expectTopSection(tester, 4, '群聊测试');
      final headerRect = tester.getRect(_header);
      await tester.drag(_results, const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(tester.getRect(_header), headerRect);
      await _select(tester, 'globalSearchConversations'.tr);
      _expectTopSection(tester, 3, '有草稿的群会话');
      await _select(tester, StrRes.globalSearchChatHistory);
      _expectTopSection(tester, 4, '群聊测试');
      expect(source.calls.values.every((count) => count == 1), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('all group search identities use circular avatars: $dark',
        (tester) async {
      await _mount(tester, _Source(), dark: dark);
      await _search(tester);
      for (final category in [
        StrRes.groupChat,
        'globalSearchConversations'.tr,
        StrRes.globalSearchChatHistory,
      ]) {
        await _select(tester, category);
        final avatars = tester.widgetList<AvatarView>(find.byType(AvatarView));
        expect(avatars, isNotEmpty);
        expect(
            avatars
                .where((avatar) => avatar.isGroup)
                .every((avatar) => avatar.isCircle == true),
            isTrue);
        for (final element in find.byType(AvatarView).evaluate()) {
          expect(
              find.descendant(
                  of: find.byElementPredicate((e) => e == element),
                  matching: find.byType(ClipOval)),
              findsOneWidget);
        }
      }
      expect(tester.takeException(), isNull);
    });

    for (final size in [
      const Size(320, 720),
      const Size(812, 375),
      const Size(1024, 768),
    ]) {
      testWidgets(
          'large text keeps categories and first row bounded: $dark $size',
          (tester) async {
        await _mount(tester, _Source(), dark: dark, size: size, scale: 2);
        await _search(tester);
        await _select(tester, StrRes.globalSearchChatHistory);
        _expectTopSection(tester, 4, '群聊测试');
        expect(find.byType(ChoiceChip), findsNothing);
        expect(find.byType(GlassAppBar), findsNothing);
        final cancel = find.byKey(const ValueKey('chat-history-search-cancel'));
        expect(cancel, findsOneWidget);
        expect(tester.getRect(cancel).right, lessThanOrEqualTo(size.width));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('entry focuses search and tapping blank space dismisses keyboard',
      (tester) async {
    final logic = await _mount(tester, _Source());
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('globalSearchScopeHint'.tr), findsOneWidget);
    expect(logic.index.value, 1);
    expect(logic.focusNode.hasFocus, isTrue);
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    expect(logic.focusNode.hasFocus, isFalse);
    expect(find.byKey(const ValueKey('chat-history-search-cancel')),
        findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'fast results visible at 350ms while history takes 5s dark=$dark',
        (tester) async {
      final pending = Completer<dynamic>();
      final keywordApi = GlobalKeywordSearchApi(
          client: SearchHttpClient(
        session: () =>
            (user: 'self', token: 'im', server: 'https://example.test'),
        post: (_, __, ___) => pending.future,
      ));
      final logic = await _mount(tester, _Source(),
          keywordApi: keywordApi, dark: dark, scale: 1.5);
      await tester.enterText(find.byType(TextField), '会议');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_row('冬'), findsOneWidget);
      expect(_row('有草稿的群会话'), findsOneWidget);
      expect(logic.pendingSections, contains(4));
      expect(
          find.byKey(const ValueKey('global-search-progress')), findsOneWidget);
      final pendingHeaderSize = tester.getSize(_header);
      expect(_section(4), findsNothing);
      expect(find.text('chatHistoryLoading'.tr), findsNothing);
      expect(logic.pendingSections, isNot(contains(1)));
      await tester.pump(const Duration(milliseconds: 4650));
      pending.complete({
        'errCode': 0,
        'data': {'items': [], 'nextCursor': '', 'hasMore': false}
      });
      await tester.pumpAndSettle();
      expect(logic.pendingSections, isEmpty);
      expect(
          find.byKey(const ValueKey('global-search-progress')), findsNothing);
      expect(tester.getSize(_header), pendingHeaderSize);
      logic.cloudLoading.value = true;
      await tester.pump();
      expect(
          find.byKey(const ValueKey('global-search-progress')), findsOneWidget);
      expect(_row('冬'), findsOneWidget);
      logic.cloudLoading.value = false;
      await tester.pump();
      expect(
          find.byKey(const ValueKey('global-search-progress')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading slot stays stable and clear returns to empty search',
      (tester) async {
    final source = _Source()..pendingFriends = Completer<List<FriendInfo>>();
    final logic = await _mount(tester, source);
    final before = tester.getSize(_header);
    expect(
        find.byKey(const ValueKey('chat-history-search-clear')), findsNothing);
    await tester.enterText(find.byType(TextField), '1');
    await tester.pump();
    expect(find.byKey(const ValueKey('global-search-loading-1')), findsNothing);

    expect(find.byType(ListTile), findsNothing);
    for (var id = 1; id <= 4; id++) {
      expect(_section(id), findsNothing);
    }
    expect(find.text('chatHistoryLoading'.tr), findsNothing);
    await tester.pump(const Duration(milliseconds: 350));
    expect(logic.loading.value, isTrue);
    expect(tester.getSize(_header).height, greaterThan(before.height));
    source.pendingFriends!
        .complete([FriendInfo(userID: 'friend', nickname: '冬')]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('global-search-loading-1')), findsNothing);
    expect(tester.getSize(_header).height, greaterThan(before.height));
    await tester.tap(find.byKey(const ValueKey('chat-history-search-clear')));
    await tester.pumpAndSettle();
    expect(tester.getSize(_header), before);
    expect(logic.query.value, isEmpty);
    expect(logic.loading.value, isFalse);
    expect(find.byKey(const ValueKey('global-search-progress')), findsNothing);
    expect(find.byType(ListTile), findsNothing);
    expect(
        find.byKey(const ValueKey('chat-history-search-clear')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial section failure keeps its heading and retry works',
      (tester) async {
    final source = _Source()..failFiles = true;
    await _mount(tester, source);
    await _search(tester);
    await _select(tester, StrRes.globalSearchChatHistory);
    expect(_section(4), findsOneWidget);
    expect(find.text('globalSearchFailed'.tr), findsOneWidget);
    source.failFiles = false;
    await tester.tap(find.widgetWithText(TextButton, 'chatSearchRetry'.tr));
    await tester.pumpAndSettle();
    _expectTopSection(tester, 4, '群聊测试');
    expect(find.text('globalSearchFailed'.tr), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('export actual search results ${dark ? 'dark' : 'light'}',
        (tester) async {
      final boundary = GlobalKey();
      final previewConversation = ConversationInfo(
          conversationID: 'sg_group',
          groupID: 'group',
          conversationType: ConversationType.superGroup,
          showName: '太6了123123',
          latestMsg: Message(
              contentType: MessageType.text,
              textElem: TextElem(content: '[视频]')));
      final source = _Source()
        ..friendResults = [FriendInfo(userID: 'friend', nickname: '测试1234')]
        ..groupResults = [
          GroupInfo(groupID: 'group', groupName: '太6了123123'),
          GroupInfo(groupID: 'empty-one', groupName: '123123'),
          GroupInfo(groupID: 'empty-two', groupName: '123123'),
        ]
        ..conversationResults = [
          previewConversation,
          for (final id in ['empty-one', 'empty-two'])
            ConversationInfo(
                conversationID: 'sg_$id',
                groupID: id,
                showName: '123123',
                conversationType: ConversationType.superGroup),
        ];
      source.previews.add(previewConversation);
      await _mount(tester, source, dark: dark, boundary: boundary);
      await _search(tester, query: '123');
      await _export(
          tester, boundary, dark ? 'dark-overview' : 'light-overview');
      await _select(tester, StrRes.globalSearchChatHistory);
      await _export(tester, boundary, dark ? 'dark' : 'light');
      expect(tester.takeException(), isNull);
    },
        skip: _previewOutput.isEmpty,
        variant: TargetPlatformVariant(
            {TargetPlatform.android, TargetPlatform.iOS}));
  }
}

Future<void> _loadPreviewFonts() async {
  final chinese = File('C:/Windows/Fonts/msyh.ttc');
  if (await chinese.exists()) {
    final bytes = ByteData.sublistView(await chinese.readAsBytes());
    await (FontLoader('SearchLayoutFont')..addFont(Future.value(bytes))).load();
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
  await (FontLoader('packages/font_awesome_flutter/FontAwesomeSolid')
        ..addFont(rootBundle
            .load('packages/font_awesome_flutter/lib/fonts/fa-solid-900.ttf')))
      .load();
}

Future<void> _export(
    WidgetTester tester, GlobalKey key, String themeName) async {
  final platform =
      Theme.of(tester.element(find.byType(GlobalSearchPage))).platform.name;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File(
          '$_previewOutput/global-search-results-$themeName-$platform.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
