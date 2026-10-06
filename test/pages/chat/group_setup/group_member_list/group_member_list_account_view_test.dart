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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    OpenIM.iMManager.userID = 'viewer';
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} rows show permitted accounts without IM fallback',
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
          theme: ThemeData(brightness: brightness),
          home: GroupMemberListPage(logic: logic),
        ),
      ));
      await tester.pump();
      expect(find.text('@abcdefgh12'), findsOneWidget);
      for (final id in ['im_visible_peer', 'im_hidden_peer', 'im_sdk_peer']) {
        expect(find.text(id), findsNothing);
      }
      await tester.tap(find.text('Public peer'));
      await tester.pump();
      expect(logic.checkedList.single.userID, 'im_visible_peer');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      logic.onClose();
      await tester.pump();
    });
  }
}
