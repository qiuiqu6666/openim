import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/contacts_view.dart';
import 'package:openim/pages/contacts/friend_list/friend_list_logic.dart';
import 'package:openim/pages/contacts/friend_list/friend_list_view.dart';
import 'package:openim/pages/contacts/presence_store.dart';
import 'package:openim/pages/contacts/star_friend_store.dart';
import 'package:openim/pages/official_account/widgets/official_account_name_label.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

ISUserInfo _friend(String id, String name, {String? remark, String? ex}) =>
    IMUtils.setAzPinyinAndTag(ISUserInfo.fromJson({
      'userID': id,
      'nickname': name,
      if (remark != null) 'remark': remark,
      if (ex != null) 'ex': ex,
    })) as ISUserInfo;

class _DirectoryLogic extends GetxController implements ContactsLogic {
  @override
  final friends = <ISUserInfo>[].obs;
  @override
  final friendsLoading = false.obs;
  @override
  final presence = PresenceStore();
  @override
  final stars = StarFriendStore();
  @override
  int get friendApplicationCount => 0;
  @override
  int get groupApplicationCount => 0;
  ISUserInfo? openedFriend;

  @override
  void viewFriend(ISUserInfo friend) => openedFriend = friend;
  @override
  void setPresenceVisible(String id, bool visible) {}
  @override
  void searchContacts() {}
  @override
  void newFriend() {}
  @override
  void newGroup() {}
  @override
  void myGroup() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FriendListLogic extends GetxController implements FriendListLogic {
  @override
  final friendList = <ISUserInfo>[].obs;
  ISUserInfo? openedFriend;
  @override
  void viewFriendInfo(ISUserInfo info) => openedFriend = info;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _name(String id) => find.byWidgetPredicate(
    (widget) => widget is OfficialAccountNameLabel && widget.userID == id);

Finder _presenceText(String id, String text) => find.descendant(
    of: find.byKey(ValueKey('contact-presence-$id')),
    matching: find.text(text));

Finder _badge() => find.byWidgetPredicate((widget) =>
    widget is Image &&
    widget.image is AssetImage &&
    (widget.image as AssetImage)
        .assetName
        .endsWith('official_account_verified.png'));

Future<void> _mount(
    WidgetTester tester, Widget page, Brightness brightness) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = brightness == Brightness.dark;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(brightness: brightness),
      home: page,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    FriendDisplayPreferences.setOnlineStatus(true);
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(() {
    Styles.isDark = false;
    VisibilityDetectorController.instance.updateInterval =
        const Duration(milliseconds: 500);
    Get.reset();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'official contacts keep online display through offline cache and updates: $brightness',
        (tester) async {
      const officialIDs = ['assistant', '99Message', '99Pay'];
      final logic = _DirectoryLogic()
        ..friends.assignAll([
          _friend('assistant', 'AI助理'),
          _friend('99Message', '99Message'),
          _friend('99Pay', '99Pay'),
          _friend('ordinary', 'AI助理'),
        ]);
      addTearDown(logic.presence.dispose);
      addTearDown(logic.stars.dispose);
      try {
        logic.presence.users.assignAll({
          for (final id in [...officialIDs, 'ordinary'])
            id: UserPresence(false, null),
        });
        await _mount(tester, ContactsPage(logic: logic), brightness);
        void expectOfficialBadges() {
          for (final id in officialIDs) {
            expect(find.descendant(of: _name(id), matching: _badge()),
                findsOneWidget,
                reason: '$id keeps its official badge without SDK metadata.');
          }
          expect(_badge(), findsNWidgets(3));
          expect(find.descendant(of: _name('ordinary'), matching: _badge()),
              findsNothing,
              reason: 'A personal contact named AI助理 is not official.');
        }

        void expectOfficialOnline() {
          expectOfficialBadges();
          for (final id in officialIDs) {
            expect(_presenceText(id, 'presenceOnline'.tr), findsOneWidget,
                reason: '$id remains available using its stable identity.');
          }
          expect(
              _presenceText('ordinary', 'presenceOffline'.tr), findsOneWidget,
              reason: 'An official-looking nickname does not grant presence.');
        }

        expectOfficialOnline();
        for (final id in officialIDs) {
          expect(logic.presence.users[id]!.online, isFalse);
          // Exercise the same cache transition used by SDK offline callbacks.
          logic.presence.users[id] = UserPresence(true, null);
          logic.presence.markOffline(id);
        }
        await tester.pumpAndSettle();
        expectOfficialOnline();
        for (final id in officialIDs) {
          expect(logic.presence.users[id]!.online, isFalse);
          expect(logic.presence.users[id]!.lastSeenAt, isNotNull);
          logic.presence.remove(id);
        }
        await tester.pumpAndSettle();
        expectOfficialOnline();
        for (final id in officialIDs) {
          expect(logic.presence.users.containsKey(id), isFalse);
        }

        FriendDisplayPreferences.setOnlineStatus(false);
        await tester.pumpAndSettle();
        for (final id in officialIDs) {
          expect(_presenceText(id, 'presenceOnline'.tr), findsNothing);
        }
        expect(_presenceText('ordinary', 'presenceOffline'.tr), findsNothing);
        expectOfficialBadges();
        expect(FriendDisplayPreferences.showOnlineStatus, isFalse);
        FriendDisplayPreferences.setOnlineStatus(true);
        await tester.pumpAndSettle();
        expectOfficialOnline();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        FriendDisplayPreferences.setOnlineStatus(true);
        logic.presence.dispose();
        logic.stars.dispose();
      }
    });

    testWidgets('directory badges keep remarks stars and row tap: $brightness',
        (tester) async {
      final official = _friend('99Message', '99Message', remark: '公告备注');
      final ordinary = _friend('ordinary', '99Message');
      final metadata = _friend('server-official', '运营通知',
          ex: '{"accountType":"official","officialRole":"message"}');
      final logic = _DirectoryLogic()
        ..friends.assignAll([official, ordinary, metadata]);
      logic.stars.apply(StarFriend.fromJson({
        'friendUserID': '99Message',
        'starred': true,
        'version': 1,
        'updatedAt': 1,
      }));
      addTearDown(logic.presence.dispose);
      addTearDown(logic.stars.dispose);
      await _mount(tester, ContactsPage(logic: logic), brightness);
      expect(find.text('公告备注'), findsOneWidget);
      expect(find.text('99Message'), findsOneWidget);
      expect(_badge(), findsNWidgets(2));
      expect(find.descendant(of: _name('ordinary'), matching: _badge()),
          findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      await tester.tap(find.text('公告备注'));
      expect(logic.openedFriend, same(official));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      logic.presence.dispose();
      logic.stars.dispose();
    });
  }

  testWidgets('legacy friend directory uses stable identity beside the remark',
      (tester) async {
    final official = _friend('99Pay', '99Pay', remark: '支付备注');
    final logic = _FriendListLogic()
      ..friendList.assignAll([official, _friend('ordinary', '99Pay')]);
    Get.put<FriendListLogic>(logic);
    await _mount(tester, FriendListPage(), Brightness.light);
    expect(_badge(), findsOneWidget);
    expect(find.text('支付备注'), findsOneWidget);
    expect(find.descendant(of: _name('ordinary'), matching: _badge()),
        findsNothing);
    await tester.tap(find.text('支付备注'));
    expect(logic.openedFriend, same(official));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
