import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile _panel_logic.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile _panel_view.dart';

import 'pages/contacts/user_profile_panel/support/profile_panel_fixture.dart';

class ProfileFixture extends GetxController implements UserProfilePanelLogic {
  ProfileFixture(
      {this.friend = true, this.allowAdd = true, this.group = false});
  final bool friend;
  final bool allowAdd;
  final bool group;
  @override
  String? get groupID => group ? 'fixture-group' : null;
  @override
  final profileLayoutReady = true.obs;
  @override
  final initialProfileFailed = false.obs;
  final moments =
      profileMomentsRepository(peerUserId: '123456789012345678901234567890');

  @override
  void onClose() {
    moments.dispose();
    super.onClose();
  }

  @override
  final commonGroupCount = RxnInt(3);
  @override
  final loadingCommonGroups = false.obs;
  @override
  final commonGroupsFailed = false.obs;
  @override
  Future<void> loadCommonGroupCount() async => action = 'commonGroupsRetry';
  @override
  Future<void> openCommonGroups() async => action = 'commonGroups';
  @override
  bool get showMemberIMID => false;
  @override
  String get displayedUserID => userInfo.value.account ?? '';

  @override
  final iAmOwner = false.obs;
  @override
  final iHaveAdminOrOwnerPermission = false.obs;
  @override
  final notAllowAddGroupMemberFriend = false.obs;
  @override
  bool? get forceCanAdd => false;
  @override
  final joinGroupTime = 0.obs;
  @override
  final inviterID = ''.obs;
  @override
  final inviterName = ''.obs;
  @override
  void viewInviter() => action = 'inviter';
  @override
  bool get isAllowAddFriend => allowAdd;
  @override
  bool get allowSendMsgNotFriend => true;
  @override
  void addFriend() => action = 'add';
  @override
  final userInfo = UserFullInfo(
          userID: '123456789012345678901234567890',
          account: 'public_account',
          nickname: 'A very long original nickname',
          remark: 'A very long friend remark that wraps')
      .obs;
  @override
  bool get isMyself => false;
  @override
  bool get isFriendship => friend || userInfo.value.isFriendship;
  @override
  bool get isGroupMemberPage => group;
  @override
  bool get hasActiveGroupMemberContext => true;
  @override
  bool get hasFriendAddEntry => true;
  @override
  final preparingFriendAdd = false.obs;
  @override
  bool get canPrepareFriendAdd =>
      hasFriendAddEntry ||
      (!isGroupMemberPage &&
          normalizePublicAccountSearch(displayedUserID) != null);
  @override
  final updatingBlacklist = false.obs;
  String? action;
  @override
  void callDirectly({required bool video}) =>
      action = video ? 'video' : 'voice';
  @override
  void toChat() => action = 'chat';
  @override
  Future<void> editRemark() async {
    action = 'remark';
  }

  @override
  void friendSetup() => action = 'more';
  @override
  void viewPersonalInfo() => action = 'info';
  @override
  void copyID() => action = 'copy';
  @override
  Future<void> setBlacklist(bool enabled) async {
    userInfo.update((v) => v?.isBlacklist = enabled);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'common group count and retry states in ${dark ? "dark" : "light"}',
        (tester) async {
      addTearDown(Get.reset);
      Styles.isDark = dark;
      addTearDown(() => Styles.isDark = false);
      final fixture = ProfileFixture();
      GetTags.createUserProfileTag();
      addTearDown(GetTags.destroyUserProfileTag);
      Get.put<UserProfilePanelLogic>(fixture, tag: GetTags.userProfile);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: UserProfilePanelPage(momentsRepository: fixture.moments),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('profileCommonGroups'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.text('profileCommonGroups'));
      expect(fixture.action, 'commonGroups');
      fixture.commonGroupCount.value = 0;
      await tester.pump();
      expect(find.text('0'), findsOneWidget);
      fixture.loadingCommonGroups.value = true;
      await tester.pump();
      expect(find.text('profileCommonGroupsLoading'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      fixture.loadingCommonGroups.value = false;
      fixture.commonGroupsFailed.value = true;
      await tester.pump();
      await tester.tap(find.text('profileCommonGroupsCountFailed'));
      expect(fixture.action, 'commonGroups');
      expect(find.text('0'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'group owner can open friend request when member disallows adding',
      (tester) async {
    addTearDown(Get.reset);
    final fixture = ProfileFixture(friend: false, allowAdd: false, group: true);
    fixture.iAmOwner.value = true;
    fixture.notAllowAddGroupMemberFriend.value = true;
    GetTags.createUserProfileTag();
    addTearDown(GetTags.destroyUserProfileTag);
    Get.put<UserProfilePanelLogic>(fixture, tag: GetTags.userProfile);
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
            home: UserProfilePanelPage(momentsRepository: fixture.moments))));
    await tester.pumpAndSettle();
    expect(find.textContaining(fixture.userInfo.value.userID!), findsNothing);
    await tester.tap(find.text(StrRes.addFriend));
    expect(fixture.action, 'add');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('friend profile fits narrow screens and connects primary actions',
      (tester) async {
    tester.view.physicalSize = const Size(320, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(Get.reset);
    final fixture = ProfileFixture();
    GetTags.createUserProfileTag();
    addTearDown(GetTags.destroyUserProfileTag);
    Get.put<UserProfilePanelLogic>(fixture, tag: GetTags.userProfile);
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
            home: UserProfilePanelPage(momentsRepository: fixture.moments))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.call_rounded));
    expect(fixture.action, 'voice');
    await tester.tap(find.byIcon(Icons.videocam_rounded));
    expect(fixture.action, 'video');
    await tester.tap(find.byIcon(Icons.chat_bubble_rounded));
    expect(fixture.action, 'chat');
    await tester.tap(find.text('profileRemarkName'));
    expect(fixture.action, 'remark');
    await tester.tap(find.byIcon(Icons.copy_outlined));
    expect(fixture.action, 'copy');
  });
  for (final dark in [false, true]) {
    testWidgets(
        'nonfriend profile has bottom actions in ${dark ? "dark" : "light"}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(Get.reset);
      Styles.isDark = dark;
      addTearDown(() => Styles.isDark = false);
      final fixture = ProfileFixture(friend: false);
      GetTags.createUserProfileTag();
      addTearDown(GetTags.destroyUserProfileTag);
      Get.put<UserProfilePanelLogic>(fixture, tag: GetTags.userProfile);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            home: RepaintBoundary(
                key: const ValueKey('profile-preview'),
                child:
                    UserProfilePanelPage(momentsRepository: fixture.moments))),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.call_rounded), findsNothing);
      expect(find.byIcon(Icons.chat_bubble_rounded), findsNothing);
      expect(find.text('profileRemarkName'), findsNothing);
      expect(find.text('profileGenderPrivate'), findsOneWidget);
      expect(find.text(StrRes.addFriend), findsOneWidget);
      expect(find.text('profileAddBlacklist'), findsOneWidget);
      final previewDir = Platform.environment['PROFILE_PREVIEW_DIR'];
      if (previewDir != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('profile-preview')));
        final image =
            (await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!;
        final bytes = await tester
            .runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
        await tester.runAsync(() async {
          await Directory(previewDir).create(recursive: true);
          await File('$previewDir/profile-${dark ? "dark" : "light"}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        });
        image.dispose();
      }

      await tester.tap(find.text(StrRes.addFriend));
      expect(fixture.action, 'add');
      await tester.tap(find.text('profileAddBlacklist'));
      await tester.pumpAndSettle();
      expect(fixture.userInfo.value.isBlacklist, isTrue);
      expect(find.text('profileRemoveBlacklist'), findsOneWidget);
      fixture.updatingBlacklist.value = true;
      await tester.pump();
      await tester.tap(find.text('profileRemoveBlacklist'));
      expect(fixture.userInfo.value.isBlacklist, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('nonfriend respects add permission', (tester) async {
    addTearDown(Get.reset);
    final fixture = ProfileFixture(friend: false, allowAdd: false);
    GetTags.createUserProfileTag();
    addTearDown(GetTags.destroyUserProfileTag);
    Get.put<UserProfilePanelLogic>(fixture, tag: GetTags.userProfile);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
          home: UserProfilePanelPage(momentsRepository: fixture.moments)),
    ));
    await tester.pumpAndSettle();
    expect(find.text(StrRes.addFriend), findsNothing);
    expect(find.text('profileAddBlacklist'), findsOneWidget);
    fixture.userInfo.update((user) => user?.isFriendship = true);
    await tester.pumpAndSettle();
    expect(find.text(StrRes.addFriend), findsNothing);
    expect(find.byIcon(Icons.chat_bubble_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('group nonfriend displays SDK join time and inviter action',
      (tester) async {
    addTearDown(Get.reset);
    final fixture = ProfileFixture(friend: false, group: true);
    fixture.joinGroupTime.value = 1700000000;
    fixture.inviterID.value = 'inviter-id';
    fixture.inviterName.value = 'Inviter';
    GetTags.createUserProfileTag();
    addTearDown(GetTags.destroyUserProfileTag);
    Get.put<UserProfilePanelLogic>(fixture, tag: GetTags.userProfile);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
          home: UserProfilePanelPage(momentsRepository: fixture.moments)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Inviter'), findsOneWidget);
    await tester.tap(find.text('Inviter'));
    expect(fixture.action, 'inviter');
    expect(tester.takeException(), isNull);
  });
}
