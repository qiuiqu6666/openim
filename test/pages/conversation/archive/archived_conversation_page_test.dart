import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/archive/archived_conversation_page.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/conversation/editing/conversation_edit_action_bar.dart';
import 'package:openim/pages/conversation/editing/conversation_selection_indicator.dart';
import 'package:openim/pages/conversation/widgets/conversation_feed_row.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../support/conversation_live_fixture.dart';

const _archivePreviewOutput =
    String.fromEnvironment('ARCHIVED_CONVERSATION_PREVIEW');
bool _archivePreviewFontsLoaded = false;

class _ArchiveLogic extends GetxController
    with ConversationLiveFixture
    implements ConversationLogic {
  @override
  final list = <ConversationInfo>[].obs;
  @override
  final folders = <ChatFolder>[].obs;
  @override
  final states = <String, ChatConversationState>{}.obs;
  @override
  final organizerLoading = false.obs;
  @override
  final organizerError = RxnString();
  @override
  final popCtrl = CustomPopupMenuController();
  final markedIds = <String>[];
  final organizerWrites = <({String id, String? folderID, bool archived})>[];
  final pinnedWrites = <({String id, bool pinned})>[];
  final openedIds = <String>[];
  Completer<void>? markGate;
  Completer<void>? refreshGate;
  bool failUnarchive = false;
  bool failMarkRead = false;
  String? refreshFailure;
  int refreshCount = 0;

  void seed(String id,
      {bool group = false, bool archived = true, String? folderID}) {
    list.add(ConversationInfo(
      conversationID: id,
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
      userID: group ? null : 'friend-$id',
      groupID: group ? 'group-$id' : null,
      showName: id,
      unreadCount: 2,
      latestMsg: Message.fromJson({
        'contentType': MessageType.text,
        'sendID': 'sender-$id',
        'textElem': {'content': '真实消息预览'},
      }),
    ));
    states[id] = ChatConversationState.fromJson({
      'conversationID': id,
      'folderID': folderID,
      'archived': archived,
      'version': 1,
    });
  }

  @override
  bool get isSessionActive => true;
  @override
  bool get reInstall => false;
  @override
  String? get imSdkStatus => null;
  @override
  bool get isFailedSdkStatus => false;
  @override
  bool isArchived(ConversationInfo info) =>
      states[info.conversationID]?.archived == true;
  @override
  bool isGroupChat(ConversationInfo info) => info.isGroupChat;
  @override
  bool isNotDisturb(ConversationInfo info) => info.recvMsgOpt == 2;
  @override
  String? folderID(ConversationInfo info) =>
      states[info.conversationID]?.folderID;
  @override
  String getShowName(ConversationInfo info) => info.showName ?? '';
  @override
  String getContent(ConversationInfo info) => IMUtils.parseMsg(info.latestMsg!);
  @override
  String getTime(ConversationInfo info) => '18:29';
  @override
  int getUnreadCount(ConversationInfo info) => info.unreadCount;
  @override
  String? getPrefixTag(ConversationInfo info) => '';

  @override
  Future<void> refreshOrganizer() async {
    refreshCount++;
    organizerLoading.value = true;
    organizerError.value = null;
    try {
      await refreshGate?.future;
      organizerError.value = refreshFailure;
    } finally {
      organizerLoading.value = false;
    }
  }

  @override
  Future<void> markConversationRead(ConversationInfo info) async {
    markedIds.add(info.conversationID);
    await markGate?.future;
    if (failMarkRead) throw StateError('读取失败，请重试');
    info.unreadCount = 0;
    list.refresh();
  }

  @override
  Future<bool> updateOrganizer(ConversationInfo info,
      {required String? folderID, required bool archived}) async {
    organizerWrites
        .add((id: info.conversationID, folderID: folderID, archived: archived));
    if (failUnarchive) return false;
    states[info.conversationID] = ChatConversationState.fromJson({
      'conversationID': info.conversationID,
      'folderID': folderID,
      'archived': archived,
      'version': (states[info.conversationID]?.version ?? 0) + 1,
    });
    return true;
  }

  @override
  Future<void> setPinned(ConversationInfo info, bool pinned) async {
    pinnedWrites.add((id: info.conversationID, pinned: pinned));
    info.isPinned = pinned;
    list.refresh();
  }

  @override
  Future<void> setNotDisturb(ConversationInfo info, bool enabled) async {
    info.recvMsgOpt = enabled ? 2 : 0;
    list.refresh();
  }

  @override
  Future<void> deleteConversation(ConversationInfo info) async {
    list.removeWhere((item) => item.conversationID == info.conversationID);
    states.remove(info.conversationID);
  }

  @override
  void toChat({
    bool offUntilHome = true,
    String? userID,
    String? groupID,
    String? nickname,
    String? faceURL,
    int? sessionType,
    ConversationInfo? conversationInfo,
    Message? searchMessage,
  }) {
    openedIds.add(conversationInfo!.conversationID);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void onClose() {
    popCtrl.dispose();
    super.onClose();
  }
}

Finder _row(String id) => find.byWidgetPredicate((widget) =>
    widget is ConversationFeedRow && widget.info.conversationID == id);

bool _selected(WidgetTester tester, String id) => tester
    .widget<ConversationSelectionIndicator>(find.descendant(
      of: _row(id),
      matching: find.byType(ConversationSelectionIndicator),
    ))
    .selected;

Future<void> _pumpPage(WidgetTester tester, _ArchiveLogic logic,
    {bool dark = false,
    bool groupChats = false,
    GlobalKey? boundaryKey}) async {
  addTearDown(() async {
    final navigators = tester
        .stateList<NavigatorState>(find.byType(Navigator, skipOffstage: false));
    if (navigators.isNotEmpty) {
      navigators.first.popUntil((route) => route.isFirst);
    }
    EasyLoading.dismiss(animation: false);
    // Clean a failed peek through frames, without awaiting its pending Future
    // from another fake-async zone and blocking the rest of this test file.
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  Styles.isDark = dark;
  Get.put<ConversationLogic>(logic);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        fontFamily: _archivePreviewFontsLoaded ? 'ArchivePreviewFont' : null,
      ),
      builder: EasyLoading.init(),
      home: RepaintBoundary(
        key: boundaryKey,
        child: ArchivedConversationPage(groupChats: groupChats),
      ),
    ),
  ));
  await tester.pump();
}

Future<void> _disposePage(WidgetTester tester) async {
  EasyLoading.dismiss(animation: false);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _enablePeekHistory() async {
  SharedPreferences.setMockInitialValues({});
  await DataSp.init();
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': 'archive-viewer',
    'chatToken': 'archive-preview-token',
    'imToken': 'archive-preview-im-token',
  }));
  ChatHistoryCache.clear();
  const channel = MethodChannel('flutter_openim_sdk');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    expect(call.method, 'getAdvancedHistoryMessageList');
    return jsonEncode(AdvancedMessage(
      messageList: [
        Message.fromJson({
          'clientMsgID': 'archive-preview-message',
          'contentType': MessageType.text,
          'sessionType': ConversationType.single,
          'sendID': 'friend-swipe-me',
          'recvID': 'archive-viewer',
          'senderNickname': '联系人',
          'sendTime': 1,
          'seq': 1,
          'status': MessageStatus.succeeded,
          'isRead': false,
          'textElem': {'content': '归档 SDK 历史消息'},
          'exMap': {'showTime': false},
        }),
      ],
      isEnd: true,
      errCode: 0,
    ).toJson());
  });
  addTearDown(() {
    ChatHistoryCache.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}

void main() {
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'archive-viewer';
  });
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });

  for (final dark in [false, true]) {
    for (final group in [false, true]) {
      testWidgets('archive navigation and empty scope ($dark, $group)',
          (tester) async {
        final logic = _ArchiveLogic();
        await _pumpPage(tester, logic, dark: dark, groupChats: group);
        await tester.pumpAndSettle();
        expect(logic.refreshCount, 1);
        expect(find.text('已归档'), findsOneWidget);
        expect(find.text(group ? '暂无归档群聊' : '暂无归档会话'), findsOneWidget);
        final appBar = tester.widget<AppBar>(
            find.byWidgetPredicate((widget) => widget is AppBar));
        expect(appBar.centerTitle, isFalse);
        expect(appBar.elevation, 0);
        expect(appBar.backgroundColor, Colors.transparent);
        expect(appBar.flexibleSpace, isA<LiquidGlassSurface>());
        expect((appBar.flexibleSpace! as LiquidGlassSurface).tint,
            dark ? AppTokens.backgroundDark : AppTokens.surfaceLight);
        expect(find.text('搜索'), findsNothing);
        expect(find.text('全部'), findsNothing);
        expect(find.byType(BottomNavigationBar), findsNothing);

        // The archived feed deliberately has the reference's compact natural
        // row height, no divider, and a surface even for dark unpinned rows.
        logic.seed('normal-row', group: group);
        logic.seed('pinned-row', group: group);
        logic.list.last.isPinned = true;
        logic.list.refresh();
        await tester.pumpAndSettle();
        for (final id in ['normal-row', 'pinned-row']) {
          final row = _row(id);
          final feed = tester.widget<ConversationFeedRow>(row);
          expect(feed.archivedLayout, isTrue);
          expect(feed.showDivider, isFalse);
          expect(tester.getSize(row).height, 64);
          final material = tester.widget<Material>(
              find.descendant(of: row, matching: find.byType(Material)).first);
          expect(
              material.color,
              id == 'pinned-row'
                  ? AppTokens.surfaceAlt(dark: dark)
                  : AppTokens.surface(dark: dark));
          expect(
              find.descendant(
                of: row,
                matching: find.byWidgetPredicate(
                    (widget) => widget is Positioned && widget.bottom == 0),
              ),
              findsNothing);
        }
        await tester.tap(find.byTooltip('编辑'));
        await tester.pumpAndSettle();
        for (final id in ['normal-row', 'pinned-row']) {
          expect(tester.getSize(_row(id)).height, 64);
          expect(tester.widget<ConversationFeedRow>(_row(id)).showDivider,
              isFalse);
        }
        await _disposePage(tester);
      });
    }
  }

  for (final group in [false, true]) {
    testWidgets('all read operates only on current archived scope ($group)',
        (tester) async {
      final logic = _ArchiveLogic()
        ..seed('archived-one', group: group)
        ..seed('archived-two', group: group)
        ..seed('other-archive', group: !group)
        ..seed('main-feed', group: group, archived: false);
      await _pumpPage(tester, logic, groupChats: group);
      await tester.pumpAndSettle();
      expect(_row('archived-one'), findsOneWidget);
      expect(_row('archived-two'), findsOneWidget);
      expect(_row('other-archive'), findsNothing);
      expect(_row('main-feed'), findsNothing);
      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
      expect(find.text('取消归档'), findsOneWidget);
      expect(find.text('全部已读'), findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey('conversation-edit-mark-read')));
      await tester.pumpAndSettle();
      expect(logic.markedIds, ['archived-one', 'archived-two']);
      expect(
          logic.list
              .firstWhere((info) => info.conversationID == 'other-archive')
              .unreadCount,
          2);
      expect(
          logic.list
              .firstWhere((info) => info.conversationID == 'main-feed')
              .unreadCount,
          2);
      expect(find.byType(ConversationEditActionBar), findsNothing);
      await _disposePage(tester);
    });
  }

  testWidgets('selected read keeps unselected archived conversation unread',
      (tester) async {
    final logic = _ArchiveLogic()
      ..seed('selected')
      ..seed('untouched');
    await _pumpPage(tester, logic);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(_row('selected'));
    await tester.pump();
    expect(_selected(tester, 'selected'), isTrue);
    expect(find.text('标记已读'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('conversation-edit-mark-read')));
    await tester.pumpAndSettle();
    expect(logic.markedIds, ['selected']);
    expect(logic.list.last.unreadCount, 2);
    expect(logic.openedIds, isEmpty);
    await _disposePage(tester);
  });

  testWidgets(
      'unarchive updates real organizer state and retains original folder',
      (tester) async {
    final logic = _ArchiveLogic()
      ..seed('selected', folderID: 'existing-folder')
      ..seed('untouched');
    await _pumpPage(tester, logic);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(_row('selected'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('conversation-edit-archive')));
    await tester.pumpAndSettle();
    expect(logic.organizerWrites,
        [(id: 'selected', folderID: 'existing-folder', archived: false)]);
    expect(logic.states['selected']!.archived, isFalse);
    expect(logic.states['selected']!.folderID, 'existing-folder');
    expect(_row('selected'), findsNothing);
    expect(_row('untouched'), findsOneWidget);
    expect(find.byType(ConversationEditActionBar), findsNothing);
    await _disposePage(tester);
  });

  testWidgets('failed mark read retains unread data and selected row for retry',
      (tester) async {
    final logic = _ArchiveLogic()
      ..seed('selected')
      ..seed('untouched');
    logic.failMarkRead = true;
    await _pumpPage(tester, logic);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(_row('selected'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('conversation-edit-mark-read')));
    await tester.pumpAndSettle();
    expect(_selected(tester, 'selected'), isTrue);
    expect(logic.list.first.unreadCount, 2);
    expect(logic.list.last.unreadCount, 2);
    expect(
        tester
            .widget<ConversationEditActionBar>(
                find.byType(ConversationEditActionBar))
            .busy,
        isFalse);
    EasyLoading.dismiss(animation: false);
    await tester.pump();
    logic.failMarkRead = false;
    await tester.tap(find.byKey(const ValueKey('conversation-edit-mark-read')));
    await tester.pumpAndSettle();
    expect(logic.markedIds, ['selected', 'selected']);
    expect(logic.list.first.unreadCount, 0);
    expect(logic.list.last.unreadCount, 2);
    expect(find.byType(ConversationEditActionBar), findsNothing);
    await _disposePage(tester);
  });

  testWidgets('failed unarchive preserves selected row for retry',
      (tester) async {
    final logic = _ArchiveLogic()..seed('retry-me', folderID: 'keep-folder');
    logic.failUnarchive = true;
    await _pumpPage(tester, logic);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(_row('retry-me'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('conversation-edit-archive')));
    await tester.pumpAndSettle();
    expect(_row('retry-me'), findsOneWidget);
    expect(_selected(tester, 'retry-me'), isTrue);
    expect(logic.states['retry-me']!.archived, isTrue);
    expect(
        tester
            .widget<ConversationEditActionBar>(
                find.byType(ConversationEditActionBar))
            .busy,
        isFalse);
    logic.failUnarchive = false;
    await tester.tap(find.byKey(const ValueKey('conversation-edit-archive')));
    await tester.pumpAndSettle();
    expect(logic.organizerWrites, hasLength(2));
    expect(_row('retry-me'), findsNothing);
    expect(find.text('暂无归档会话'), findsOneWidget);
    await _disposePage(tester);
  });

  testWidgets(
      'pending batch action blocks changing selection or leaving edit mode',
      (tester) async {
    final gate = Completer<void>();
    final logic = _ArchiveLogic()
      ..seed('selected')
      ..seed('ignored');
    logic.markGate = gate;
    await _pumpPage(tester, logic);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(_row('selected'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('conversation-edit-mark-read')));
    await tester.pump();
    expect(
        tester
            .widget<ConversationEditActionBar>(
                find.byType(ConversationEditActionBar))
            .busy,
        isTrue);
    await tester.tap(_row('ignored'));
    await tester.tap(find.text('完成'));
    await tester.pump();
    expect(_selected(tester, 'selected'), isTrue);
    expect(_selected(tester, 'ignored'), isFalse);
    expect(find.byType(ConversationEditActionBar), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(logic.markedIds, ['selected']);
    expect(logic.list.last.unreadCount, 2);
    await _disposePage(tester);
  });

  testWidgets(
      'archived swipe actions and more sheet preserve supported behavior',
      (tester) async {
    await _enablePeekHistory();
    final logic = _ArchiveLogic()..seed('swipe-me');
    await _pumpPage(tester, logic);
    await tester.pumpAndSettle();
    final slidable =
        tester.widget<Slidable>(find.byKey(const ValueKey('swipe-me')));
    expect(slidable.startActionPane, isNull);
    await tester.drag(_row('swipe-me'), const Offset(-260, 0));
    await tester.pumpAndSettle();
    for (final label in ['更多', '取消归档', '删除']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('分组'), findsNothing);
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(logic.pinnedWrites, isEmpty);
    expect(logic.organizerWrites, isEmpty);
    await tester.longPress(_row('swipe-me'));
    await tester.pumpAndSettle();
    expect(find.text('归档 SDK 历史消息'), findsOneWidget);
    expect(logic.markedIds, isEmpty);
    expect(logic.openedIds, isEmpty);
    await tester
        .tap(find.byKey(const ValueKey('conversation-peek-action-togglePin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('conversation-peek-card')), findsNothing);
    expect(logic.pinnedWrites, [(id: 'swipe-me', pinned: true)]);
    expect(logic.list.single.isPinned, isTrue);
    expect(logic.states['swipe-me']!.archived, isTrue);
    expect(_row('swipe-me'), findsOneWidget);
    await _disposePage(tester);
  });

  testWidgets('archive removal and return never reuse a detached sliding row',
      (tester) async {
    final logic = _ArchiveLogic()
      ..seed('removed', folderID: 'keep-folder')
      ..seed('shifted')
      ..seed('other');
    final removed = logic.list[0];
    final shifted = logic.list[1];
    final other = logic.list[2];
    await _pumpPage(tester, logic);
    await tester.pumpAndSettle();
    SlidableController slideFor(String id) =>
        tester.widget<Slidable>(find.byKey(ValueKey(id))).controller!;
    final originalSlide = slideFor('shifted');

    await tester.drag(_row('removed'), const Offset(-260, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消归档'));
    await tester.pumpAndSettle();
    expect(_row('removed'), findsNothing);
    expect(logic.states['removed']!.folderID, 'keep-folder');
    final shiftedSlide = slideFor('shifted');
    expect(shiftedSlide, isNot(same(originalSlide)));
    await tester.drag(_row('shifted'), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(shiftedSlide.ratio, isNot(0));
    await tester.tap(_row('shifted'));
    await tester.pumpAndSettle();
    expect(shiftedSlide.ratio, 0);
    expect(logic.openedIds, isEmpty);
    expect(tester.takeException(), isNull);

    await logic.updateOrganizer(removed,
        folderID: 'keep-folder', archived: true);
    logic.list.assignAll([other, shifted, removed]);
    await tester.pumpAndSettle();
    final returnedSlide = slideFor('shifted');
    expect(returnedSlide, isNot(same(shiftedSlide)));
    await tester.drag(_row('shifted'), const Offset(-260, 0));
    await tester.pumpAndSettle();
    expect(returnedSlide.ratio, isNot(0));
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(returnedSlide.ratio, 0);
    expect(logic.openedIds, isEmpty);
    expect(logic.states['removed']!.archived, isTrue);
    await _disposePage(tester);
  });

  testWidgets('initial loading and refresh failure provide an explicit retry',
      (tester) async {
    final gate = Completer<void>();
    final logic = _ArchiveLogic();
    logic.refreshGate = gate;
    logic.refreshFailure = '加载失败';
    await _pumpPage(tester, logic);
    expect(find.byKey(const ValueKey('archived-conversation-loading')),
        findsOneWidget);
    expect(find.text('暂无归档会话'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('archived-conversation-retry')),
        findsOneWidget);
    logic.refreshFailure = null;
    logic.refreshGate = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(logic.refreshCount, 2);
    expect(find.text('暂无归档会话'), findsOneWidget);
    await _disposePage(tester);
  });

  testWidgets(
      'cached archived rows remain visible while organizer refresh waits',
      (tester) async {
    final gate = Completer<void>();
    final logic = _ArchiveLogic()..seed('cached');
    logic.refreshGate = gate;
    await _pumpPage(tester, logic);
    expect(_row('cached'), findsOneWidget);
    expect(find.byKey(const ValueKey('archived-conversation-loading')),
        findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    await _disposePage(tester);
  });

  testWidgets('render real archived page in light and dark, normal and editing',
      (tester) async {
    expect(File(_archivePreviewOutput).isAbsolute, isTrue,
        reason: 'The preview output must be an absolute path.');
    tester.view.physicalSize = const Size(375, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final path in [
        'C:/Windows/Fonts/msyh.ttf',
        'C:/Windows/Fonts/msyh.ttc'
      ]) {
        final font = File(path);
        if (!await font.exists()) continue;
        final fontBytes = ByteData.sublistView(await font.readAsBytes());
        // Give the real page and its themed action labels a CJK font in tests.
        await (FontLoader('ArchivePreviewFont')
              ..addFont(Future.value(fontBytes)))
            .load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
        _archivePreviewFontsLoaded = true;
        break;
      }
    });
    final logic = _ArchiveLogic()
      ..seed('winter')
      ..seed('dual');
    logic.list.first
      ..showName = '冬'
      ..isPinned = true
      ..unreadCount = 0
      ..latestMsg = Message.fromJson({
        'contentType': MessageType.text,
        'sendID': 'friend-winter',
        'textElem': {'content': '周末一起吃饭吗？'},
      });
    logic.list.last
      ..showName = 'dual'
      ..unreadCount = 0
      ..latestMsg = Message.fromJson({
        'contentType': MessageType.text,
        'sendID': 'friend-dual',
        'textElem': {'content': '好的，到时候见。'},
      });
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final captures = <ui.Image>[];
    const panel = Size(375, 600);
    for (var column = 0; column < 2; column++) {
      final key = GlobalKey();
      await _pumpPage(tester, logic, dark: column == 1, boundaryKey: key);
      await tester.pumpAndSettle();
      for (var row = 0; row < 2; row++) {
        if (row == 1) {
          await tester.tap(find.byTooltip('编辑'));
          await tester.pumpAndSettle();
          await tester.tap(_row('dual'));
          await tester.pumpAndSettle();
        }
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final capture = (await tester.runAsync(() => boundary.toImage()))!;
        captures.add(capture);
        expect(capture.width, panel.width.toInt());
        expect(capture.height, panel.height.toInt());
        canvas.drawImageRect(
          capture,
          Offset.zero & panel,
          Rect.fromLTWH(column * panel.width, row * panel.height, panel.width,
              panel.height),
          Paint(),
        );
      }
    }
    await _disposePage(tester);
    final picture = recorder.endRecording();
    await tester.runAsync(() async {
      final image = await picture.toImage(750, 1200);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File(_archivePreviewOutput);
      await output.parent.create(recursive: true);
      await output.writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      for (final capture in captures) {
        capture.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  }, skip: _archivePreviewOutput.isEmpty);
}
