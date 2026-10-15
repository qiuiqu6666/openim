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
import 'package:rxdart/rxdart.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/navigation/contacts_header.dart';
import '../contacts/search/support/contacts_inline_fixture.dart';
import '../../support/conversation_live_fixture.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/core/session/connection/api_connection_health.dart';
import 'package:openim/pages/conversation/archive/archived_conversation_page.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/conversation/editing/conversation_edit_action_bar.dart';
import 'package:openim/pages/conversation/editing/conversation_selection_indicator.dart';
import 'package:openim/pages/home/glass_bottom_nav_bar.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim/pages/home/home_view.dart';
import 'package:openim_common/openim_common.dart';

class _Home extends GetxController implements HomeLogic {
  @override
  final unhandledCount = 0.obs;
  @override
  void switchTab(dynamic index) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController implements IMController {
  @override
  IMSdkStatus get currentConnectionStatus => IMSdkStatus.connectionSucceeded;
  @override
  ApiConnectionHealth? get apiConnectionHealth => null;
  @override
  final userInfo = UserFullInfo(userID: 'viewer', nickname: 'Viewer').obs;
  @override
  final imSdkStatusSubject =
      ReplaySubject<({IMSdkStatus status, bool reInstall, int? progress})>(
          maxSize: 1);
  @override
  void onClose() {
    imSdkStatusSubject.close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conversations extends GetxController
    with ConversationLiveFixture
    implements ConversationLogic {
  @override
  final list = <ConversationInfo>[].obs;
  @override
  final folders = <ChatFolder>[].obs;
  @override
  final organizerLoading = false.obs;
  @override
  final organizerError = RxnString();
  @override
  final popCtrl = CustomPopupMenuController();
  final archivedIds = <String>{};
  final markedIds = <String>[];
  Completer<void>? markGate;
  bool sessionActive = true;
  @override
  bool get isSessionActive => sessionActive;
  @override
  String? get imSdkStatus => null;
  @override
  bool get isFailedSdkStatus => false;
  @override
  bool get reInstall => false;
  @override
  bool isArchived(ConversationInfo info) =>
      archivedIds.contains(info.conversationID);
  @override
  bool isGroupChat(ConversationInfo info) => info.isGroupChat;
  @override
  bool isNotDisturb(ConversationInfo info) => false;
  @override
  String? folderID(ConversationInfo info) => null;
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
  Future<void> markConversationRead(ConversationInfo info) async {
    markedIds.add(info.conversationID);
    await markGate?.future;
    info.unreadCount = 0;
    list.refresh();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void onClose() {
    popCtrl.dispose();
    super.onClose();
  }
}

ConversationInfo _conversation(int index) => ConversationInfo(
      conversationID: 'conversation-$index',
      conversationType: ConversationType.single,
      userID: 'friend-$index',
      showName: '联系人 $index',
      unreadCount: 2,
      latestMsg: Message.fromJson({
        'contentType': MessageType.text,
        'sendID': 'friend-$index',
        'textElem': {'content': '你好'},
      }),
    );

const _searchPreview =
    String.fromEnvironment('CONVERSATION_INLINE_SEARCH_PREVIEW');
bool _searchFontsLoaded = false;

Future<void> _snapshotSearch(
    WidgetTester tester, GlobalKey key, String name) async {
  if (_searchPreview.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_searchPreview/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _mountHome(WidgetTester tester, _Conversations conversations,
    {required bool dark, GlobalKey? boundary, ContactsLogic? contacts}) async {
  Get.testMode = true;
  OpenIM.iMManager.userID = 'viewer';
  Styles.isDark = dark;
  addTearDown(() {
    Styles.isDark = false;
    Get.reset();
  });
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Get.put<HomeLogic>(_Home());
  Get.put<IMController>(_IM());
  Get.put<ConversationLogic>(conversations);
  if (contacts != null) Get.put<ContactsLogic>(contacts);

  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          fontFamily: _searchFontsLoaded ? 'InlineSearchPreviewFont' : null),
      builder: (_, child) => MediaQuery(
        data: const MediaQueryData(
          size: Size(375, 812),
          padding: EdgeInsets.only(top: 24, bottom: 34),
        ),
        child: child!,
      ),
      home: boundary == null
          ? const HomePage()
          : RepaintBoundary(key: boundary, child: const HomePage()),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'entire search field responds while the SDK session is recovering',
      (tester) async {
    final conversations = _Conversations()
      ..sessionActive = false
      ..list.addAll([_conversation(1), _conversation(2)]);
    await _mountHome(tester, conversations, dark: false);
    final entry = find.byKey(const ValueKey('conversation-search-entry'));
    final input = find.byKey(const ValueKey('chat-history-search-input'));
    final cancel = find.byKey(const ValueKey('chat-history-search-cancel'));
    for (final position in [.05, .5, .95]) {
      final rect = tester.getRect(entry);
      await tester
          .tapAt(Offset(rect.left + rect.width * position, rect.center.dy));
      await tester.pumpAndSettle();
      expect(input, findsOneWidget);
      expect(find.byTooltip('编辑'), findsNothing);
      expect(
          tester.getTopLeft(input).dy, closeTo(rect.top - kToolbarHeight, 1));
      expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(entry, findsOneWidget);
      expect(find.byTooltip('编辑'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final dark in [false, true]) {
    testWidgets(
        'contacts search hides navigation and back restores its tab ($dark)',
        (tester) async {
      final contacts = InlineContactsFixture();
      addTearDown(() => contacts.onDelete());
      await _mountHome(tester, _Conversations(),
          dark: dark, contacts: contacts);
      await tester.tap(find.text('通讯录'));
      await tester.pumpAndSettle();
      expect(find.byType(ContactsHeader), findsOneWidget);
      final route = Get.currentRoute;
      final input = find.byKey(const ValueKey('chat-history-search-input'));
      final inputState = tester.state(input);
      await tester.tap(find.byKey(const ValueKey('contacts-search-button')));
      await tester.pumpAndSettle();
      expect(find.byType(GlassBottomNavBar), findsNothing);
      expect(find.byType(ContactsHeader), findsNothing);
      expect(tester.state(input), same(inputState));
      expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
      expect(Get.currentRoute, route);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(Get.currentRoute, route);
      expect(find.byType(GlassBottomNavBar), findsOneWidget);
      expect(find.byType(ContactsHeader), findsOneWidget);
      expect(tester.state(input), same(inputState));
      expect(tester.widget<TextField>(input).readOnly, isTrue);
      expect(contacts.legacySearches, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      contacts.presence.dispose();
      contacts.stars.dispose();
    });
    for (final groups in [false, true]) {
      testWidgets(
          'home search hides navigation and system back restores it ($dark, $groups)',
          (tester) async {
        if (_searchPreview.isNotEmpty && !_searchFontsLoaded) {
          await tester.runAsync(() async {
            final font = File('C:/Windows/Fonts/msyh.ttc');
            if (await font.exists()) {
              await (FontLoader('InlineSearchPreviewFont')
                    ..addFont(font.readAsBytes().then(ByteData.sublistView)))
                  .load();
              await (FontLoader('MaterialIcons')
                    ..addFont(
                        rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                  .load();
              _searchFontsLoaded = true;
            }
          });
        }
        final conversations = _Conversations()
          ..list.addAll([_conversation(1), _conversation(2)]);
        final boundary = GlobalKey();
        await _mountHome(tester, conversations, dark: dark, boundary: boundary);
        if (groups) {
          await tester.tap(find.text('群聊'));
          await tester.pumpAndSettle();
        }
        final route = Get.currentRoute;
        final theme = dark ? 'dark' : 'light';
        final scope = groups ? 'groups' : 'messages';
        await _snapshotSearch(tester, boundary, '$scope-$theme-before');
        await tester
            .tap(find.byKey(const ValueKey('conversation-search-entry')));
        await tester.pumpAndSettle();
        expect(Get.currentRoute, route);
        expect(find.byType(GlassBottomNavBar), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
        await _snapshotSearch(tester, boundary, '$scope-$theme-search');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(Get.currentRoute, route);
        expect(find.byType(TextField), findsOneWidget);
        expect(
            tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
        expect(find.byType(GlassBottomNavBar), findsOneWidget);
        await _snapshotSearch(tester, boundary, '$scope-$theme-restored');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
    testWidgets(
        'home swaps its navigation for selected conversation actions ($dark)',
        (tester) async {
      final conversations = _Conversations()
        ..list.addAll([_conversation(1), _conversation(2)]);
      await _mountHome(tester, conversations, dark: dark);
      expect(find.byType(GlassBottomNavBar), findsOneWidget);
      final navigationRect = tester.getRect(find.byType(BottomNavigationBar));
      final firstRow = find.byKey(const ValueKey('conversation-1'));
      final initialRowRect = tester.getRect(firstRow);

      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassBottomNavBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      for (final label in ['群聊', '通讯录', '我的']) {
        expect(find.text(label), findsNothing);
      }
      expect(find.text('消息'), findsOneWidget); // The main title stays visible.
      expect(find.text('全部已读'), findsOneWidget);
      expect(find.text('归档'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      final bar = find.byType(ConversationEditActionBar);
      expect(
          tester.widget<ConversationEditActionBar>(bar).hasSelection, isFalse);
      final readAction =
          find.byKey(const ValueKey('conversation-edit-mark-read'));
      final actionRect = tester.getRect(readAction);
      expect(actionRect.top, closeTo(navigationRect.top, .01));
      expect(actionRect.bottom, closeTo(navigationRect.bottom, .01));
      expect(tester.getRect(firstRow).top, initialRowRect.top);
      expect(tester.getRect(firstRow).height, initialRowRect.height);
      expect(
          tester
              .widget<TextButton>(
                  find.byKey(const ValueKey('conversation-edit-archive')))
              .onPressed,
          isNull);

      await tester.tap(firstRow);
      await tester.pumpAndSettle();
      expect(
          tester.widget<ConversationEditActionBar>(bar).hasSelection, isTrue);
      expect(find.text('标记已读'), findsOneWidget);
      expect(
          tester
              .widget<ConversationSelectionIndicator>(find.descendant(
                  of: firstRow,
                  matching: find.byType(ConversationSelectionIndicator)))
              .selected,
          isTrue);
      expect(
          tester
              .widget<TextButton>(
                  find.byKey(const ValueKey('conversation-edit-archive')))
              .onPressed,
          isNotNull);

      await tester.tap(readAction);
      await tester.pumpAndSettle();
      expect(conversations.markedIds, ['conversation-1']);
      expect(conversations.list[0].unreadCount, 0);
      expect(conversations.list[1].unreadCount, 2);
      expect(find.byType(ConversationEditActionBar), findsNothing);
      expect(find.byType(GlassBottomNavBar), findsOneWidget);
      expect(tester.getRect(find.byType(BottomNavigationBar)), navigationRect);

      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationEditActionBar), findsNothing);
      expect(find.byType(GlassBottomNavBar), findsOneWidget);
      expect(find.text('群聊'), findsOneWidget);
      expect(find.text('通讯录'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);

      // Dispose while publishing an editing bar to exercise both lifecycle owners.
      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('done leaves read batch running and blocks duplicates ($dark)',
        (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final conversations = _Conversations()
        ..list.addAll([_conversation(1), _conversation(2), _conversation(3)])
        ..markGate = gate;
      await _mountHome(tester, conversations, dark: dark);
      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('conversation-edit-mark-read')));
      await tester.pumpAndSettle();
      expect(conversations.markedIds, hasLength(3));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(conversations.markingAllRead.value, isTrue);
      expect(find.byType(GlassBottomNavBar), findsOneWidget);
      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ConversationEditActionBar>(
                  find.byType(ConversationEditActionBar))
              .busy,
          isTrue);
      gate.complete();
      await tester.pumpAndSettle();
      expect(conversations.list.every((c) => c.unreadCount == 0), isTrue);
      expect(find.byType(ConversationEditActionBar), findsOneWidget,
          reason: 'Old batch does not close a newer edit session');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'archive uses the root route and hides the home navigation ($dark)',
        (tester) async {
      final normal = _conversation(1);
      final archived = _conversation(2);
      final conversations = _Conversations()
        ..list.addAll([normal, archived])
        ..archivedIds.add(archived.conversationID);
      await _mountHome(tester, conversations, dark: dark);
      final navigationRect = tester.getRect(find.byType(BottomNavigationBar));
      expect(find.byKey(ValueKey(normal.conversationID)), findsOneWidget);
      expect(find.byKey(ValueKey(archived.conversationID)), findsNothing);

      await tester.tap(find.text('归档'));
      await tester.pumpAndSettle();
      expect(find.byType(ArchivedConversationPage), findsOneWidget);
      expect(find.text('已归档'), findsOneWidget);
      expect(find.byKey(ValueKey(archived.conversationID)), findsOneWidget);
      expect(find.byKey(ValueKey(normal.conversationID)), findsNothing);
      expect(find.byType(GlassBottomNavBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(ConversationEditActionBar), findsNothing);
      for (final label in ['消息', '群聊', '通讯录', '我的']) {
        expect(find.text(label), findsNothing);
      }

      await tester.tap(find.byTooltip('编辑'));
      await tester.pumpAndSettle();
      final bar = find.byType(ConversationEditActionBar);
      expect(bar, findsOneWidget);
      expect(tester.widget<ConversationEditActionBar>(bar).unarchive, isTrue);
      expect(find.byType(GlassBottomNavBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      for (final label in ['消息', '群聊', '通讯录', '我的']) {
        expect(find.text(label), findsNothing);
      }
      await tester.tap(find.byKey(ValueKey(archived.conversationID)));
      await tester.pumpAndSettle();
      expect(
          tester.widget<ConversationEditActionBar>(bar).hasSelection, isTrue);

      // Popping while editing must dispose the archive bar, then restore Home.
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(ArchivedConversationPage), findsNothing);
      expect(find.byType(ConversationEditActionBar), findsNothing);
      expect(find.byType(GlassBottomNavBar), findsOneWidget);
      expect(tester.getRect(find.byType(BottomNavigationBar)), navigationRect);
      expect(find.byKey(ValueKey(normal.conversationID)), findsOneWidget);
      expect(find.text('归档'), findsOneWidget);
      expect(conversations.list, [normal, archived]);
      expect(conversations.isArchived(archived), isTrue);
      for (final label in ['群聊', '通讯录', '我的']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
