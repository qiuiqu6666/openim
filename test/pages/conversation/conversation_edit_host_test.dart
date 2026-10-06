import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import '../../support/conversation_live_fixture.dart';
import 'package:openim/core/controller/im_controller.dart';
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController implements IMController {
  @override
  final userInfo = UserFullInfo(userID: 'viewer', nickname: 'Viewer').obs;
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
  @override
  bool get isSessionActive => true;
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

Future<void> _mountHome(WidgetTester tester, _Conversations conversations,
    {required bool dark}) async {
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

  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: (_, child) => MediaQuery(
        data: const MediaQueryData(
          size: Size(375, 812),
          padding: EdgeInsets.only(top: 24, bottom: 34),
        ),
        child: child!,
      ),
      home: const HomePage(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
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
