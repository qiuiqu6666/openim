import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity.dart';
import 'package:openim/pages/chat/group_setup/group_member_list/group_member_identity_state.dart';
import 'package:openim/pages/chat/group_setup/group_member_list/group_member_list_logic.dart';
import 'package:openim/pages/chat/group_setup/group_member_list/group_member_list_view.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    OpenIM.iMManager.userID = 'viewer';
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} rows hide accounts and retain member selection',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousInterval =
          VisibilityDetectorController.instance.updateInterval;
      VisibilityDetectorController.instance.updateInterval = Duration.zero;
      addTearDown(() => VisibilityDetectorController.instance.updateInterval =
          previousInterval);
      final identity = GroupMemberIdentityState(session: () => 'session');
      final logic = GroupMemberListLogic(identity: identity)
        ..groupInfo = GroupInfo(groupID: 'group', memberCount: 3)
        ..opType = GroupMemberOpType.at;
      logic.memberList.assignAll([
        GroupMemberIdentityInfo(
            groupID: 'group',
            userID: 'im_visible_peer',
            nickname: 'Public peer',
            account: '@abcdefgh12'),
        GroupMemberIdentityInfo(
            groupID: 'group',
            userID: 'im_hidden_peer',
            nickname: 'Hidden peer'),
        GroupMembersInfo(
            groupID: 'group', userID: 'im_sdk_peer', nickname: 'SDK peer'),
      ]);
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          theme:
              ThemeData(brightness: brightness, platform: TargetPlatform.iOS),
          home: GroupMemberListPage(logic: logic),
        ),
      ));
      await tester.pump();
      expect(find.text('@abcdefgh12'), findsNothing);
      expect(find.text('Public peer'), findsOneWidget);
      for (final id in ['im_visible_peer', 'im_hidden_peer', 'im_sdk_peer']) {
        expect(find.text(id), findsNothing);
      }
      await tester.tap(find.text('Public peer'));
      await tester.pump();
      expect(logic.checkedList.single.userID, 'im_visible_peer');
      final shortList = find.byType(SmartRefresher);
      final shortScroll = tester.state<ScrollableState>(find
          .descendant(of: shortList, matching: find.byType(Scrollable))
          .first);
      final shortDrag = await tester.startGesture(tester.getCenter(shortList));
      await shortDrag.moveBy(const Offset(0, 160));
      await tester.pump();
      expect(shortScroll.position.pixels, shortScroll.position.minScrollExtent);
      await shortDrag.up();
      await tester.pump(const Duration(milliseconds: 500));
      logic.memberList.assignAll(List.generate(
          100,
          (i) => GroupMembersInfo(
              groupID: 'group',
              userID: 'old-${i.toString().padLeft(3, '0')}',
              nickname: 'Old $i',
              joinTime: 100 - i)));
      await tester.pump();
      final refresher = find.byType(SmartRefresher);
      final scrollable = tester.state<ScrollableState>(find
          .descendant(of: refresher, matching: find.byType(Scrollable))
          .first);
      // Hold the drag at the boundary: settling alone would hide iOS bounce.
      final gesture = await tester.startGesture(tester.getCenter(refresher));
      await gesture.moveBy(const Offset(0, 160));
      await tester.pump();
      expect(scrollable.position.pixels, scrollable.position.minScrollExtent);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.drag(refresher, const Offset(0, -220));
      await tester.pump(const Duration(milliseconds: 500));
      expect(scrollable.position.pixels, greaterThan(0));
      scrollable.position.jumpTo(800);
      await tester.pump();
      final before = scrollable.position.pixels;
      expect(before, greaterThan(0));
      final firstIDs = logic.visibleMembers.map((m) => m.userID).toList();
      logic.memberList.addAll(List.generate(
          100,
          (i) => GroupMembersInfo(
              groupID: 'group',
              userID: 'new-$i',
              nickname: 'New $i',
              joinTime: 200 + i)));
      await tester.pump();
      expect(scrollable.position.pixels, closeTo(before, 0.1));
      expect(logic.visibleMembers.take(100).map((m) => m.userID), firstIDs);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      logic.onClose();
      await tester.pump();
    });
  }
}
