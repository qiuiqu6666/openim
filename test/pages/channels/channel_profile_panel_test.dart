import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/contacts/group_profile_panel/group_profile_panel_logic.dart';
import 'package:openim/pages/contacts/group_profile_panel/group_profile_panel_view.dart';

class _Panel implements GroupProfilePanelLogic {
  _Panel(bool channel, bool joined) : isJoined = joined.obs,
    groupInfo = GroupInfo(groupID: 'AbCd1234EfGh', groupName: '测试', memberCount: 2,
      ex: channel ? '{"conversationKind":"channel"}' : null).obs;
  @override
  final Rx<GroupInfo> groupInfo;
  @override
  final RxBool isJoined;
  @override
  final members = <GroupMembersInfo>[].obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final channel in [true, false]) {
    for (final joined in [true, false]) {
      testWidgets('profile panel labels channel=$channel joined=$joined', (tester) async {
        await tester.pumpWidget(ScreenUtilInit(designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
            translations: TranslationService(), locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: GroupProfilePanelPage(logic: _Panel(channel, joined)))));
        await tester.pumpAndSettle();
        expect(find.text(channel ? '频道ID' : '群UID'), findsOneWidget);
        expect(find.text(channel ? '频道公告' : '群公告'), findsOneWidget);
        expect(find.text(channel ? '暂无频道公告' : '暂无群公告'), findsOneWidget);
        expect(find.text(channel ? '2位订阅者' : '共2人'), findsOneWidget);
        expect(find.text(channel ? (joined ? '进入频道' : '订阅频道') : (joined ? StrRes.enterGroup : StrRes.applyJoin)), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
