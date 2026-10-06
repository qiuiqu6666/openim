import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import '../../../support/conversation_live_fixture.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/presence_store.dart';
import 'package:openim/pages/conversation/archive/archived_conversation_page.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/conversation/conversation_view.dart';
import 'package:openim/pages/conversation/folders/conversation_folder_bar.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_message.dart';
import 'package:openim/pages/conversation/widgets/conversation_feed_row.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('flutter_openim_sdk');
const _account = 'peek-viewer';

ChatFolder _folder(String id, String name) => ChatFolder.fromJson({
      'id': id,
      'name': name,
      'sortOrder': 0,
      'createdAt': 1,
      'updatedAt': 1,
    });

Message _historyMessage(String id, {bool group = false}) => Message.fromJson({
      'clientMsgID': 'history-$id',
      'contentType': MessageType.text,
      'sessionType':
          group ? ConversationType.superGroup : ConversationType.single,
      'sendID': 'friend-$id',
      'recvID': group ? 'group-$id' : _account,
      'groupID': group ? 'group-$id' : null,
      'senderNickname': '消息发送者',
      'sendTime': 1700000000000,
      'seq': 9,
      'status': MessageStatus.succeeded,
      'isRead': false,
      'textElem': {'content': 'SDK 历史消息 $id'},
      'exMap': {'showTime': false},
    });

/// Only the actual OpenIM transport is mocked: the page creates the real
/// loader, preview route and existing chat message renderer.
class _HistoryTransport {
  final calls = <MethodCall>[];
  final historyArguments = <Map<String, dynamic>>[];
  final groupIDs = <String>{};
  int failuresRemaining = 0;
  Completer<void>? gate;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'getGroupsInfo') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final ids = List<String>.from(args['groupIDList'] as List);
        return jsonEncode([
          for (final id in ids) {'groupID': id, 'memberCount': 7},
        ]);
      }
      // Read receipts, unread resets and any other SDK write are prohibited.
      expect(call.method, 'getAdvancedHistoryMessageList');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      historyArguments.add(args);
      await gate?.future;
      if (failuresRemaining > 0) {
        failuresRemaining--;
        return jsonEncode(AdvancedMessage(
                messageList: [], isEnd: true, errCode: 500, errMsg: '网络错误')
            .toJson());
      }
      final id = args['conversationID'] as String;
      return jsonEncode(AdvancedMessage(
        messageList: [_historyMessage(id, group: groupIDs.contains(id))],
        isEnd: true,
        errCode: 0,
      ).toJson());
    });
  }
}

/// Presence stays a real account-owned snapshot; this directory fixture does
/// not subscribe to the SDK or refresh the HTTP service.
class _PresenceContacts extends GetxController implements ContactsLogic {
  @override
  final presence = PresenceStore();

  @override
  void onClose() {
    presence.dispose();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FeedLogic extends GetxController
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
  final openedIDs = <String>[];
  final markedIDs = <String>[];
  final deletedIDs = <String>[];
  final pinWrites = <({String id, bool pinned})>[];
  final muteWrites = <({String id, bool enabled})>[];
  final organizerWrites = <({String id, String? folderID, bool archived})>[];
  bool Function()? previewVisible;
  bool sessionActive = true;

  ConversationInfo seed(String id,
      {bool group = false, bool archived = false, String? folderID}) {
    final info = ConversationInfo(
      conversationID: id,
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
      userID: group ? null : 'friend-$id',
      groupID: group ? 'group-$id' : null,
      showName: group ? '群聊 $id' : '联系人 $id',
      unreadCount: 8,
      recvMsgOpt: 0,
      isPinned: false,
      latestMsgSendTime: 1700000000000,
      latestMsg: Message.fromJson({
        'contentType': MessageType.text,
        'sendID': 'friend-$id',
        'textElem': {'content': '仅供会话行显示'},
      }),
    );
    list.add(info);
    states[id] = ChatConversationState.fromJson({
      'conversationID': id,
      'folderID': folderID,
      'archived': archived,
      'version': 1,
    });
    return info;
  }

  void _expectPreviewDismissed() => expect(previewVisible?.call(), isFalse,
      reason:
          'SDK/organizer actions must run after the preview route is removed');

  @override
  bool get isSessionActive => sessionActive;
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
  void globalSearch() {}
  @override
  void addFriend() {}
  @override
  void addGroup() {}
  @override
  void createGroup() {}
  @override
  Future<void> refreshOrganizer() async {}

  @override
  Future<bool> updateOrganizer(ConversationInfo info,
      {required String? folderID, required bool archived}) async {
    _expectPreviewDismissed();
    organizerWrites
        .add((id: info.conversationID, folderID: folderID, archived: archived));
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
    _expectPreviewDismissed();
    pinWrites.add((id: info.conversationID, pinned: pinned));
    info.isPinned = pinned;
    list.refresh();
  }

  @override
  Future<void> setNotDisturb(ConversationInfo info, bool enabled) async {
    _expectPreviewDismissed();
    muteWrites.add((id: info.conversationID, enabled: enabled));
    info.recvMsgOpt = enabled ? 2 : 0;
    list.refresh();
  }

  @override
  Future<void> deleteConversation(ConversationInfo info) async {
    _expectPreviewDismissed();
    deletedIDs.add(info.conversationID);
    list.removeWhere((row) => row.conversationID == info.conversationID);
    states.remove(info.conversationID);
  }

  @override
  Future<void> markConversationRead(ConversationInfo info) async {
    markedIDs.add(info.conversationID);
    fail('A read-only preview must never mark a conversation read');
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
    _expectPreviewDismissed();
    openedIDs.add(conversationInfo!.conversationID);
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
Finder _action(String name) =>
    find.byKey(ValueKey('conversation-peek-action-$name'));
Finder _folderLabel(String name) => find.descendant(
    of: find.byType(ConversationFolderBar), matching: find.text(name));
final _card = find.byKey(const ValueKey('conversation-peek-card'));

Future<void> _mount(WidgetTester tester, _FeedLogic logic,
    {bool archived = false, bool group = false}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    final navigators = tester
        .stateList<NavigatorState>(find.byType(Navigator, skipOffstage: false));
    if (navigators.isNotEmpty) {
      navigators.first.popUntil((route) => route.isFirst);
    }
    EasyLoading.dismiss(animation: false);
    // Pump the reverse transition rather than awaiting a preview Future created
    // in the test's fake-async zone. Failed expectations must still release its
    // process-wide showing guard before the next test starts.
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  logic.previewVisible = () => _card.evaluate().isNotEmpty;
  Get.put<ConversationLogic>(logic);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: Brightness.light),
      builder: EasyLoading.init(),
      home: archived
          ? ArchivedConversationPage(groupChats: group)
          : ConversationPage(groupChats: group),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _peek(WidgetTester tester, String id) async {
  await tester.longPress(_row(id));
  await tester.pumpAndSettle();
  expect(_card, findsOneWidget);
}

Future<void> _select(WidgetTester tester, String action) async {
  await tester.tap(_action(action));
  await tester.pumpAndSettle();
  expect(_card, findsNothing);
}

Future<void> _dismiss(WidgetTester tester) async {
  // The full-screen dismiss target is behind both cards. Tap its clear corner.
  await tester.tapAt(const Offset(3, 3));
  await tester.pumpAndSettle();
  expect(_card, findsNothing);
}

Future<void> _dispose(WidgetTester tester) async {
  await EasyLoading.dismiss(animation: false);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    Get.testMode = true;
    Styles.isDark = false;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': _account,
      'chatToken': 'peek-chat-token',
      'imToken': 'peek-im-token',
    }));
    OpenIM.iMManager.userID = _account;
    ChatHistoryCache.clear();
  });
  tearDown(() {
    ChatHistoryCache.clear();
    Styles.isDark = false;
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets('official preview is online without changing ordinary presence',
      (tester) async {
    final sdk = _HistoryTransport()..install();
    final logic = _FeedLogic();
    final assistant = logic.seed('assistant')
      ..userID = 'assistant'
      ..showName = 'AI助理';
    final friend = logic.seed('human');
    final contacts = _PresenceContacts();
    Get.put<ContactsLogic>(contacts);
    addTearDown(contacts.presence.dispose);
    addTearDown(() => FriendDisplayPreferences.setOnlineStatus(true));
    final assistantOffline = UserPresence(false, null);
    final friendOffline = UserPresence(false, null);
    contacts.presence.users['assistant'] = assistantOffline;
    contacts.presence.users[friend.userID!] = friendOffline;
    FriendDisplayPreferences.setOnlineStatus(true);
    await _mount(tester, logic);
    final pill = find.byKey(const ValueKey('conversation-peek-title-pill'));

    await _peek(tester, 'assistant');
    final online =
        find.descendant(of: pill, matching: find.text('presenceOnline'.tr));
    expect(online, findsOneWidget);
    expect(tester.widget<Text>(online).style?.color, AppTokens.accent);
    expect(find.descendant(of: pill, matching: find.text('presenceOffline'.tr)),
        findsNothing);
    expect(contacts.presence.users['assistant'], same(assistantOffline));
    expect(assistantOffline.online, isFalse);
    await _dismiss(tester);

    await _peek(tester, 'human');
    expect(find.descendant(of: pill, matching: find.text('presenceOffline'.tr)),
        findsOneWidget);
    expect(find.descendant(of: pill, matching: find.text('presenceOnline'.tr)),
        findsNothing);
    expect(contacts.presence.users[friend.userID], same(friendOffline));
    await _dismiss(tester);

    FriendDisplayPreferences.setOnlineStatus(false);
    await tester.pump();
    await _peek(tester, 'assistant');
    expect(find.descendant(of: pill, matching: find.text('presenceOnline'.tr)),
        findsNothing);
    expect(find.descendant(of: pill, matching: find.text('presenceOffline'.tr)),
        findsNothing);
    expect(assistant.unreadCount, 8);
    expect(friend.unreadCount, 8);
    expect(logic.markedIDs, isEmpty);
    expect(logic.openedIDs, isEmpty);
    expect(sdk.historyArguments, hasLength(3));
    await _dismiss(tester);
    await Get.delete<ContactsLogic>();
    await _dispose(tester);
  });

  for (final archived in [false, true]) {
    for (final group in [false, true]) {
      testWidgets(
          'long press shows SDK history without reading ($archived, $group)',
          (tester) async {
        final sdk = _HistoryTransport();
        if (group) sdk.groupIDs.add('chat');
        sdk.install();
        final logic = _FeedLogic();
        final info = logic.seed('chat', group: group, archived: archived);
        await _mount(tester, logic, archived: archived, group: group);
        await _peek(tester, 'chat');

        expect(find.text('SDK 历史消息 chat'), findsOneWidget);
        expect(find.byType(ConversationPeekMessage), findsOneWidget);
        expect(sdk.historyArguments, hasLength(1));
        expect(sdk.historyArguments.single['conversationID'], 'chat');
        expect(sdk.historyArguments.single['startClientMsgID'], '');
        expect(sdk.historyArguments.single['count'], 30);
        if (group) expect(find.text('7人'), findsOneWidget);
        expect(info.unreadCount, 8);
        expect(logic.markedIDs, isEmpty);
        expect(logic.openedIDs, isEmpty);
        expect(find.text('标记未读'), findsNothing);
        expect(find.text('标记已读'), findsNothing);
        expect(
            _action('addToFolder'), archived ? findsNothing : findsOneWidget);
        await _dismiss(tester);
        expect(info.unreadCount, 8);
        expect(logic.openedIDs, isEmpty);
        expect(logic.organizerWrites, isEmpty);
        await _dispose(tester);
      });
    }

    testWidgets('only tapping the preview card opens its chat ($archived)',
        (tester) async {
      final sdk = _HistoryTransport()..install();
      final logic = _FeedLogic();
      final info = logic.seed('chat', archived: archived);
      await _mount(tester, logic, archived: archived);
      await _peek(tester, 'chat');
      expect(logic.openedIDs, isEmpty);
      await tester.tap(_card);
      await tester.pumpAndSettle();
      expect(_card, findsNothing);
      expect(logic.openedIDs, ['chat']);
      expect(info.unreadCount, 8);
      expect(logic.markedIDs, isEmpty);
      expect(sdk.historyArguments, hasLength(1));
      await _dispose(tester);
    });

    testWidgets(
        'archive toggle preserves existing folder after dismissal ($archived)',
        (tester) async {
      _HistoryTransport().install();
      final logic = _FeedLogic();
      final info = logic.seed('chat', archived: archived, folderID: 'work');
      await _mount(tester, logic, archived: archived);
      await _peek(tester, 'chat');
      expect(find.text(archived ? '取消归档' : '归档'), findsOneWidget);
      await _select(tester, 'archive');
      expect(logic.organizerWrites,
          [(id: 'chat', folderID: 'work', archived: !archived)]);
      expect(logic.isArchived(info), !archived);
      expect(_row('chat'), findsNothing);
      expect(logic.openedIDs, isEmpty);
      expect(info.unreadCount, 8);
      await _dispose(tester);
    });

    testWidgets('pin and mute use live SDK state after dismissal ($archived)',
        (tester) async {
      _HistoryTransport().install();
      final logic = _FeedLogic();
      final info = logic.seed('chat', archived: archived);
      await _mount(tester, logic, archived: archived);
      await _peek(tester, 'chat');
      await _select(tester, 'togglePin');
      expect(logic.pinWrites, [(id: 'chat', pinned: true)]);
      await _peek(tester, 'chat');
      expect(find.text('取消置顶'), findsOneWidget);
      await _select(tester, 'toggleMute');
      expect(logic.muteWrites, [(id: 'chat', enabled: true)]);
      await _peek(tester, 'chat');
      expect(find.text('取消免打扰'), findsOneWidget);
      await _select(tester, 'toggleMute');
      expect(logic.muteWrites,
          [(id: 'chat', enabled: true), (id: 'chat', enabled: false)]);
      expect(logic.isNotDisturb(info), isFalse);
      expect(logic.isArchived(info), archived);
      expect(info.unreadCount, 8);
      expect(logic.markedIDs, isEmpty);
      expect(logic.openedIDs, isEmpty);
      await _dispose(tester);
    });

    testWidgets(
        'delete keeps its confirmation after preview dismissal ($archived)',
        (tester) async {
      _HistoryTransport().install();
      final logic = _FeedLogic()..seed('chat', archived: archived);
      await _mount(tester, logic, archived: archived);
      await _peek(tester, 'chat');
      await _select(tester, 'delete');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(logic.deletedIDs, isEmpty);
      await tester.tap(find.widgetWithText(TextButton, StrRes.cancel));
      await tester.pumpAndSettle();
      expect(_row('chat'), findsOneWidget);
      await _peek(tester, 'chat');
      await _select(tester, 'delete');
      await tester.tap(find.widgetWithText(TextButton, StrRes.delete));
      await tester.pumpAndSettle();
      expect(logic.deletedIDs, ['chat']);
      expect(_row('chat'), findsNothing);
      expect(logic.markedIDs, isEmpty);
      expect(logic.openedIDs, isEmpty);
      await _dispose(tester);
    });

    testWidgets(
        'editing disables long press preview and history requests ($archived)',
        (tester) async {
      final sdk = _HistoryTransport()..install();
      final logic = _FeedLogic();
      final info = logic.seed('chat', archived: archived);
      await _mount(tester, logic, archived: archived);
      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
      await tester.longPress(_row('chat'));
      await tester.pumpAndSettle();
      expect(_card, findsNothing);
      expect(sdk.calls, isEmpty);
      expect(logic.markedIDs, isEmpty);
      expect(logic.openedIDs, isEmpty);
      expect(info.unreadCount, 8);
      await _dispose(tester);
    });
  }

  testWidgets(
      'folder picker starts after dismissal and selected membership can be removed',
      (tester) async {
    _HistoryTransport().install();
    final logic = _FeedLogic()
      ..folders.addAll([_folder('work', '工作'), _folder('life', '生活')]);
    final info = logic.seed('chat', folderID: 'work');
    await _mount(tester, logic);
    await _peek(tester, 'chat');
    expect(_action('removeFromFolder'), findsNothing);
    await _select(tester, 'addToFolder');
    expect(find.text('添加到分组'), findsOneWidget);
    await tester.tap(find.widgetWithText(CupertinoActionSheetAction, '生活'));
    await tester.pumpAndSettle();
    expect(logic.organizerWrites,
        [(id: 'chat', folderID: 'life', archived: false)]);
    expect(logic.folderID(info), 'life');
    await tester.tap(_folderLabel('生活'));
    await tester.pumpAndSettle();
    await _peek(tester, 'chat');
    expect(_action('removeFromFolder'), findsOneWidget);
    await _select(tester, 'removeFromFolder');
    expect(logic.organizerWrites.last,
        (id: 'chat', folderID: null, archived: false));
    expect(logic.folderID(info), isNull);
    expect(_row('chat'), findsNothing);
    expect(info.unreadCount, 8);
    expect(logic.openedIDs, isEmpty);
    await _dispose(tester);
  });

  testWidgets('history failure can retry and cannot open chat until recovered',
      (tester) async {
    final sdk = _HistoryTransport()
      ..failuresRemaining = 1
      ..install();
    final logic = _FeedLogic();
    final info = logic.seed('chat');
    await _mount(tester, logic);
    await _peek(tester, 'chat');
    expect(find.text('加载失败，请重试'), findsOneWidget);
    expect(find.byType(ConversationPeekMessage), findsNothing);
    // The title pill is an unambiguous card hit outside the retry button.
    await tester
        .tap(find.byKey(const ValueKey('conversation-peek-title-pill')));
    await tester.pumpAndSettle();
    expect(_card, findsOneWidget);
    expect(logic.openedIDs, isEmpty);
    await tester.tap(find.byKey(const ValueKey('conversation-peek-retry')));
    await tester.pumpAndSettle();
    expect(find.text('SDK 历史消息 chat'), findsOneWidget);
    expect(sdk.historyArguments, hasLength(2));
    expect(info.unreadCount, 8);
    expect(logic.markedIDs, isEmpty);
    await _dismiss(tester);
    await _dispose(tester);
  });

  testWidgets('dismissing during SDK history ignores its late response',
      (tester) async {
    final pending = Completer<void>();
    final sdk = _HistoryTransport()
      ..gate = pending
      ..install();
    final logic = _FeedLogic();
    final info = logic.seed('chat');
    await _mount(tester, logic);
    await tester.longPress(_row('chat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(_card, findsOneWidget);
    expect(sdk.historyArguments, hasLength(1));
    await _dismiss(tester);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('SDK 历史消息 chat'), findsNothing);
    expect(logic.openedIDs, isEmpty);
    expect(logic.organizerWrites, isEmpty);
    expect(logic.markedIDs, isEmpty);
    expect(info.unreadCount, 8);
    await _dispose(tester);
  });

  for (final endSession in [false, true]) {
    testWidgets(
        'pending preview action is dropped when its owner expires ($endSession)',
        (tester) async {
      _HistoryTransport().install();
      final logic = _FeedLogic();
      final info = logic.seed('chat');
      await _mount(tester, logic);
      await _peek(tester, 'chat');
      await tester.tap(_action('togglePin'));
      // Invalidate while the preview is fading, before its action can execute.
      if (endSession) {
        logic.sessionActive = false;
      } else {
        logic.list.remove(info);
      }
      await tester.pumpAndSettle();
      expect(_card, findsNothing);
      expect(logic.pinWrites, isEmpty);
      expect(logic.markedIDs, isEmpty);
      expect(logic.openedIDs, isEmpty);
      expect(info.isPinned, isFalse);
      expect(info.unreadCount, 8);
      await _dispose(tester);
    });
  }
}
