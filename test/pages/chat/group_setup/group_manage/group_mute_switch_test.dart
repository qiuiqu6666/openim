import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group_setup/group_manage/group_manage_logic.dart';
import 'package:openim/pages/chat/group_setup/group_manage/group_manage_view.dart';
import 'package:openim_common/openim_common.dart';

import '../members/group_preview_fixture.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'admin mute switch follows state, busy and demotion, dark=$dark',
        (tester) async {
      final fixture = GroupPreviewFixture();
      await fixture.initialize(
        cachedGroup: GroupInfo(
            groupID: previewGroupID, ownerUserID: 'im_owner', status: 0),
        cachedMember: GroupMembersInfo(
            groupID: previewGroupID,
            userID: previewViewer,
            roleLevel: GroupRoleLevel.admin),
      );
      final logic = GroupManageLogic();
      Styles.isDark = dark;
      addTearDown(() async {
        logic.onDelete();
        Styles.isDark = false;
        await fixture.close();
      });
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: GroupManagePage(logic: logic),
        ),
      ));
      for (final reply in fixture.joined) {
        reply.complete('true');
      }
      await tester.pumpAndSettle();
      expect(find.text('sdkMuteAll'.tr), findsOneWidget);
      expect(find.text('sdkJoinRule'.tr), findsOneWidget);
      expect(find.text('群个性化'), findsOneWidget);
      expect(find.text('新成员历史消息'), findsNothing);
      expect(find.text(StrRes.transferGroupOwnerRight), findsNothing);
      expect(tester.widget<AppSwitch>(find.byType(AppSwitch)).value, isFalse);
      expect(tester.widget<AppSwitch>(find.byType(AppSwitch)).onChanged,
          isNotNull);

      expect(find.text('sdkMutedList'.tr), findsOneWidget);
      fixture.setup.groupInfo.update((info) => info!.ex = '{"conversationKind":"channel"}');
      await tester.pump();
      expect(find.text('sdkMutedList'.tr), findsNothing);
      fixture.setup.groupInfo.update((info) => info!.ex = '{}');
      await tester.pump();
      expect(find.text('sdkMutedList'.tr), findsOneWidget);
      fixture.setup.groupInfo.update((info) => info!.status = 3);
      await tester.pump();
      expect(tester.widget<AppSwitch>(find.byType(AppSwitch)).value, isTrue);
      logic.busy.value = true;
      await tester.pump();
      expect(
          tester.widget<AppSwitch>(find.byType(AppSwitch)).onChanged, isNull);
      logic.busy.value = false;
      fixture.setup.myGroupMembersInfo
          .update((member) => member!.roleLevel = GroupRoleLevel.member);
      await tester.pumpAndSettle();
      expect(find.text('sdkMuteAll'.tr), findsNothing);
      expect(find.text('sdkJoinRule'.tr), findsNothing);
      expect(find.text('群个性化'), findsNothing);
      expect(find.byType(AppSwitch), findsNothing);
      fixture.setup.myGroupMembersInfo
          .update((member) => member!.roleLevel = GroupRoleLevel.owner);
      await tester.pumpAndSettle();
      expect(find.text('新成员历史消息'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
