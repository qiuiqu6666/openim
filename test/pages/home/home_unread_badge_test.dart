import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim/pages/home/home_view.dart';
import 'package:openim_common/openim_common.dart';

import '../../support/conversation_live_fixture.dart';

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
  bool isNotDisturb(ConversationInfo info) => info.recvMsgOpt == 2;
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void onClose() {
    popCtrl.dispose();
    super.onClose();
  }
}

ConversationInfo _row(String id,
        {bool group = true, int unread = 1, int? receive = 0}) =>
    ConversationInfo(
      conversationID: id,
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
      groupID: group ? id : null,
      userID: group ? null : id,
      showName: id,
      recvMsgOpt: receive,
      unreadCount: unread,
      latestMsg: Message.fromJson({
        'contentType': MessageType.text,
        'sendID': id,
        'textElem': {'content': '消息'},
      }),
    );

Future<void> _mountHome(WidgetTester tester, _Conversations conversations,
    {required bool dark}) async {
  Get.testMode = true;
  OpenIM.iMManager.userID = 'viewer';
  Styles.isDark = dark;
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    Styles.isDark = false;
    Get.reset();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
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
      home: const HomePage(),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _navBadges() => find.descendant(
    of: find.byType(BottomNavigationBar),
    matching: find.byType(UnreadCountView));

List<int> _positiveNavCounts(WidgetTester tester) => tester
    .widgetList<UnreadCountView>(_navBadges())
    .where((badge) => badge.count > 0)
    .map((badge) => badge.count)
    .toList();

void main() {
  testWidgets('return from a chat shows the latest message in the retained tab',
      (tester) async {
    final old = _row('peer', group: false, unread: 0)
      ..latestMsg!.textElem!.content = '看到了';
    final conversations = _Conversations()..list.add(old);
    await _mountHome(tester, conversations, dark: false);
    expect(find.text('看到了'), findsOneWidget);

    final navigator = Navigator.of(tester.element(find.byType(HomePage)),
        rootNavigator: true);
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Chat route'))));
    await tester.pumpAndSettle();
    final latest = _row('peer', group: false, unread: 0)
      ..latestMsg!.textElem!.content = '真服了';
    conversations.list.assignAll([latest]);
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('真服了'), findsOneWidget);
    expect(find.text('看到了'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('home unread badges follow notification scope ($dark)',
        (tester) async {
      final single = _row('single', group: false, unread: 3);
      final normal = _row('normal-group', unread: 4);
      final defaultReception = _row('default-group', receive: null, unread: 6);
      final muted = _row('muted-group', receive: 2, unread: 200);
      final rejected = _row('rejected-group', receive: 1, unread: 300);
      final archived = _row('archived-group', unread: 800);
      final conversations = _Conversations()
        ..list.addAll(
            [single, normal, defaultReception, muted, rejected, archived])
        ..archivedIds.add(archived.conversationID);
      await _mountHome(tester, conversations, dark: dark);

      expect(_positiveNavCounts(tester), [3, 10]);
      expect(find.descendant(of: _navBadges(), matching: find.text('99+')),
          findsNothing);

      await tester.tap(find.descendant(
          of: find.byType(BottomNavigationBar), matching: find.text('群聊')));
      await tester.pumpAndSettle();
      final mutedRow = find.byKey(ValueKey(muted.conversationID));
      expect(mutedRow, findsOneWidget);
      expect(
          find.descendant(of: mutedRow, matching: find.byType(UnreadCountView)),
          findsNothing);
      expect(
          find.descendant(
              of: mutedRow, matching: find.byIcon(Icons.notifications_off)),
          findsOneWidget);
      expect(_positiveNavCounts(tester), [3, 10]);

      muted.recvMsgOpt = 0;
      conversations.list.refresh();
      await tester.pumpAndSettle();
      expect(_positiveNavCounts(tester), [3, 210]);
      expect(find.descendant(of: _navBadges(), matching: find.text('99+')),
          findsOneWidget);

      muted.recvMsgOpt = 2;
      single.unreadCount = 0;
      normal.unreadCount = 0;
      defaultReception.unreadCount = 0;
      conversations.list.refresh();
      await tester.pumpAndSettle();
      expect(_positiveNavCounts(tester), isEmpty);
      expect(muted.unreadCount, 200);
      expect(rejected.unreadCount, 300);
      expect(archived.unreadCount, 800);
      expect(find.descendant(of: _navBadges(), matching: find.text('99+')),
          findsNothing);
      expect(mutedRow, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
