import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile _panel_logic.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile _panel_view.dart';

class ProfileFixture extends GetxController implements UserProfilePanelLogic {
  @override
  final userInfo = UserFullInfo(
          userID: '123456789012345678901234567890',
          nickname: 'A very long original nickname',
          remark: 'A very long friend remark that wraps')
      .obs;
  @override
  bool get isMyself => false;
  @override
  bool get isFriendship => true;
  @override
  bool get isGroupMemberPage => false;
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
        builder: (_, __) => GetMaterialApp(home: UserProfilePanelPage())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.call_outlined));
    expect(fixture.action, 'voice');
    await tester.tap(find.byIcon(Icons.videocam_outlined));
    expect(fixture.action, 'video');
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    expect(fixture.action, 'chat');
    await tester.tap(find.text('profileRemarkName'));
    expect(fixture.action, 'remark');
    await tester.tap(find.byIcon(Icons.copy_outlined));
    expect(fixture.action, 'copy');
  });
}
