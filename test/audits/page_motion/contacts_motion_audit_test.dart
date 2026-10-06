import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/common_groups/common_groups_page.dart';
import 'package:openim/pages/contacts/common_groups/common_groups_store.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/presence_store.dart';
import 'package:openim/pages/contacts/select_contacts/friend_list/friend_list_logic.dart';
import 'package:openim/pages/contacts/select_contacts/friend_list/group_contact_picker.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/pages/global_search/global_search_logic.dart';
import 'package:openim/pages/global_search/global_search_view.dart';
import 'package:openim/services/common_group_count_service.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../pages/contacts/user_profile_panel/support/profile_panel_fixture.dart';
import '../../pages/contacts/user_profile_panel/support/profile_panel_host.dart';

// These are characterization tests for the motion audit, not assertions that
// the pages have already been fixed. They use real page layouts with local
// transports and keep viewport, keyboard, user input and SDK metadata constant.
class _MotionProfileFixture extends ProfilePanelFixture {
  _MotionProfileFixture() : super(friend: false, group: true);

  @override
  String? get groupID => 'audit-group';
}

class _MotionPickerFriends extends GetxController
    implements SelectContactsFromFriendsLogic {
  @override
  final friendList = <ISUserInfo>[
    ISUserInfo.fromJson({
      'userID': 'audit-friend',
      'nickname': 'Audit friend',
      'tagIndex': 'A',
    }),
  ].obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MotionPresence implements PresenceStore {
  @override
  final users = <String, UserPresence>{}.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MotionPickerContacts extends GetxController implements ContactsLogic {
  @override
  final presence = _MotionPresence();

  @override
  void setPresenceVisible(String id, bool visible) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaggeredSearch extends GlobalSearchSource {
  final friendReply = Completer<List<FriendInfo>>();
  final groupReply = Completer<List<GroupInfo>>();

  @override
  Future<List<FriendInfo>> friends(String query) => friendReply.future;

  @override
  Future<List<GroupInfo>> groups(String query) => groupReply.future;

  @override
  Future<List<ConversationInfo>> conversations(String query) async => [
        ConversationInfo(
          conversationID: 'audit-conversation',
          userID: 'audit-peer',
          conversationType: ConversationType.single,
          showName: 'Existing conversation result',
        ),
      ];

  @override
  Future<List<SearchResultItems>> messages(String query, bool files) async =>
      [];
}

class _CommonGroupsService extends CommonGroupCountService {
  final refreshing = Completer<CommonGroupListPage>();
  int calls = 0;

  static CommonGroupListPage page() => CommonGroupListPage(
        items: List.generate(
          30,
          (index) => GroupInfo(
            groupID: 'audit-group-$index',
            groupName: 'Audit group $index',
            memberCount: 5,
          ),
        ),
        nextCursor: '',
        hasMore: false,
      );

  @override
  Future<CommonGroupListPage> list(
    String peerUserID, {
    int limit = 30,
    String cursor = '',
    CancelToken? cancelToken,
  }) =>
      ++calls == 1 ? Future.value(page()) : refreshing.future;
}

Future<void> _mount(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(colorSchemeSeed: AppTokens.accent),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 24, bottom: 34),
          textScaler: TextScaler.noScaling,
        ),
        child: child!,
      ),
      home: page,
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(() {
    Get.testMode = true;
    Styles.isDark = false;
  });
  tearDown(() {
    Get.reset();
    Styles.isDark = false;
  });

  testWidgets(
      'audit: group account row inserts and retracts below a stable avatar',
      (tester) async {
    // The optional profile surface reads the SDK's late userID before its
    // no-IM-controller guard. Supply only local identity; no SDK login occurs.
    OpenIM.iMManager.userID = 'audit-viewer';
    final fixture = _MotionProfileFixture()
      ..groupAccount.value = null
      ..joinGroupTime.value = 1790878326000
      ..inviterID.value = 'fixed-inviter'
      ..inviterName.value = '固定邀请人';
    final moments = profileMomentsRepository();
    addTearDown(moments.dispose);
    await mountProfilePanel(tester, fixture: fixture, moments: moments);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    final avatar = find.descendant(
      of: find.byKey(const ValueKey('user_profile_identity')),
      matching: find.byType(AvatarView),
    );
    final joinDate = find.text(StrRes.joinGroupDate);
    final inviter = find.text('固定邀请人');
    final initialAvatar = tester.getRect(avatar);
    final initialJoin = tester.getRect(joinDate);
    final initialInviter = tester.getRect(inviter);

    // This is the same disclosure transition as a group HTTP reply. All group
    // SDK join-date/inviter fields have already been supplied before the frame.
    fixture.groupAccount.value = '@ab12cd34ef';
    await tester.pump();
    final disclosedJoin = tester.getRect(joinDate);
    final disclosedInviter = tester.getRect(inviter);
    expect(tester.getRect(avatar), initialAvatar);
    expect(disclosedJoin.top, greaterThan(initialJoin.top));
    expect(disclosedInviter.top, greaterThan(initialInviter.top));

    // GroupProfileAccountState.refresh revokes the previous account before the
    // lookup. A same-result reply then recreates the same conditional row.
    fixture.groupAccount.value = null;
    await tester.pump();
    expect(tester.getRect(joinDate), initialJoin);
    expect(tester.getRect(inviter), initialInviter);
    fixture.groupAccount.value = '@ab12cd34ef';
    await tester.pump();
    expect(tester.getRect(joinDate), disclosedJoin);
    expect(tester.getRect(inviter), disclosedInviter);
    debugPrint('[contacts-motion] account row: join delta='
        '${disclosedJoin.top - initialJoin.top}, inviter delta='
        '${disclosedInviter.top - initialInviter.top}, avatar delta=0');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('audit: late search sections displace an existing result',
      (tester) async {
    final source = _StaggeredSearch();
    final logic = Get.put(GlobalSearchLogic(source: source));
    addTearDown(() {
      if (!source.friendReply.isCompleted) {
        source.friendReply.complete([]);
      }
      if (!source.groupReply.isCompleted) {
        source.groupReply.complete([]);
      }
    });
    await _mount(tester, GlobalSearchPage());
    logic.searchCtrl.text = 'audit';
    final searching = logic.search();
    await tester.pump();
    final header = find.byKey(const ValueKey('global-search-header'));
    final conversation = find.byKey(const ValueKey('global-search-section-3'));
    final initialHeader = tester.getRect(header);
    final initialConversation = tester.getRect(conversation);

    source.friendReply.complete([
      FriendInfo(userID: 'audit-friend', nickname: 'Late friend result'),
    ]);
    await tester.pump();
    final withFriend = tester.getRect(conversation);
    expect(withFriend.top, greaterThan(initialConversation.top));
    expect(tester.getRect(header), initialHeader);
    source.groupReply.complete([
      GroupInfo(groupID: 'audit-group', groupName: 'Late group result'),
    ]);
    await searching;
    await tester.pump();
    final withGroup = tester.getRect(conversation);
    expect(withGroup.top, greaterThan(withFriend.top));
    expect(tester.getRect(header), initialHeader);
    expect(logic.query.value, 'audit');
    expect(logic.index.value, 0);
    debugPrint('[contacts-motion] search result: friend delta='
        '${withFriend.top - initialConversation.top}, group delta='
        '${withGroup.top - withFriend.top}, header delta=0');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('audit: common-group refresh collapses the current scroll offset',
      (tester) async {
    final service = _CommonGroupsService();
    final store = CommonGroupsStore('peer',
        service: service, currentUser: () => 'audit-viewer');
    addTearDown(store.dispose);
    addTearDown(() {
      if (!service.refreshing.isCompleted) {
        service.refreshing.complete(_CommonGroupsService.page());
      }
    });
    await _mount(tester, CommonGroupsPage(peerUserID: 'peer', store: store));
    await tester.pumpAndSettle();
    final controller =
        tester.widget<ListView>(find.byType(ListView)).controller!;
    controller.jumpTo(400);
    await tester.pump();
    final oldOffset = controller.offset;
    expect(oldOffset, 400);

    // _CommonGroupsPageState._open invokes this refresh after startChat returns.
    // Calling the store directly isolates the exact list/scroll behavior from
    // unrelated navigation and real SDK traffic.
    final refreshing = store.refresh();
    await tester.pump();
    expect(store.items, isEmpty);
    expect(controller.offset, lessThan(oldOffset));
    final emptyOffset = controller.offset;
    service.refreshing.complete(_CommonGroupsService.page());
    await refreshing;
    await tester.pumpAndSettle();
    expect(controller.offset, emptyOffset);
    debugPrint('[contacts-motion] common groups: before=$oldOffset, '
        'while refreshing=$emptyOffset, after=${controller.offset}');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('audit: create-group presence recenters only the friend name',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    final oldOnline = FriendDisplayPreferences.showOnlineStatus;
    FriendDisplayPreferences.setOnlineStatus(true);
    final visibility = VisibilityDetectorController.instance;
    final oldInterval = visibility.updateInterval;
    visibility.updateInterval = Duration.zero;
    addTearDown(() {
      visibility.updateInterval = oldInterval;
      FriendDisplayPreferences.setOnlineStatus(oldOnline);
    });
    final contacts = Get.put<ContactsLogic>(_MotionPickerContacts());
    final friends = _MotionPickerFriends();
    // Only data transports are faked. The production GroupContactPicker and
    // selection state are used without registering a route/SDK controller.
    final selection = SelectContactsLogic()
      ..action = SelAction.crateGroup
      ..openSelectedSheet = false;
    addTearDown(selection.onClose);
    await _mount(
        tester, GroupContactPicker(friends: friends, selection: selection));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('group-picker-audit-friend'));
    final name = find.descendant(of: row, matching: find.text('Audit friend'));
    final avatar = find.descendant(of: row, matching: find.byType(AvatarView));
    final initialRow = tester.getRect(row);
    final initialName = tester.getRect(name);
    final initialAvatar = tester.getRect(avatar);

    contacts.presence.users['audit-friend'] = UserPresence(true, null);
    await tester.pumpAndSettle();
    final knownName = tester.getRect(name);
    expect(tester.getRect(row), initialRow);
    expect(tester.getRect(avatar), initialAvatar);
    expect(knownName.top, lessThan(initialName.top));
    debugPrint('[contacts-motion] create-group presence: name delta='
        '${knownName.top - initialName.top}, row delta=0, avatar delta=0');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
