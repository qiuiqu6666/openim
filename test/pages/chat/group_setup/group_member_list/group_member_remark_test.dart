import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group_setup/group_member_list/group_member_identity_state.dart';
import 'package:openim/pages/chat/group_setup/group_member_list/group_member_list_logic.dart';
import 'package:openim/pages/chat/group_setup/group_member_list/group_member_list_view.dart';
import 'package:openim/pages/chat/group_setup/group_member_list/group_member_remark_search.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../../support/contact_remark_fixture.dart';

GroupMembersInfo _member(String id,
        {String group = 'group', int role = GroupRoleLevel.member}) =>
    GroupMembersInfo(
        groupID: group, userID: id, nickname: '公开昵称$id', roleLevel: role);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ContactRemarkFixture contacts;
  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    OpenIM.iMManager.userID = 'viewer';
    contacts = ContactRemarkFixture();
    Get.put<ContactRemarkSource>(contacts);
  });
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    for (final mode in [GroupMemberOpType.view, GroupMemberOpType.del]) {
      testWidgets(
          '${mode.name} members use current remarks in ${brightness.name}',
          (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        contacts.remarks['peer'] = '群好友备注';
        final interval = VisibilityDetectorController.instance.updateInterval;
        VisibilityDetectorController.instance.updateInterval = Duration.zero;
        addTearDown(() =>
            VisibilityDetectorController.instance.updateInterval = interval);
        final logic = GroupMemberListLogic(
            identity: GroupMemberIdentityState(session: () => 'session'))
          ..groupInfo =
              GroupInfo(groupID: 'group', memberCount: 2, ownerUserID: 'viewer')
          ..opType = mode;
        addTearDown(logic.onDelete.call);
        logic.myGroupMemberLevel.value = GroupRoleLevel.owner;
        logic.memberList.assignAll([
          _member('viewer', role: GroupRoleLevel.owner),
          _member('peer', role: GroupRoleLevel.admin),
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
        expect(find.text('群好友备注'), findsOneWidget);
        expect(find.text('公开昵称peer'), findsNothing);
        if (mode == GroupMemberOpType.del) {
          await tester.tap(find.text('群好友备注'));
          await tester.pump();
          expect(logic.checkedList.single.userID, 'peer');
        }
        contacts.remarks['peer'] = '新备注';
        await tester.pump();
        expect(find.text('新备注'), findsWidgets);
        expect(logic.memberList.last.nickname, '公开昵称peer');
        logic.query.value = '新备注';
        await tester.pump();
        expect(logic.visibleMembers.single.userID, 'peer');
        contacts.remarks.remove('peer');
        await tester.pump();
        expect(logic.visibleMembers, isEmpty);
        logic.query.value = '';
        await tester.pump();
        expect(find.text('公开昵称peer'), findsWidgets);
        if (mode == GroupMemberOpType.del) {
          expect(logic.checkedList.single.userID, 'peer');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        logic.onDelete();
      });
    }
  }

  test(
      'remark search batches candidates and excludes outsiders and removed members',
      () async {
    contacts.remarks.addAll({for (var i = 0; i < 205; i++) 'peer-$i': '备注$i'});
    final batches = <List<String>>[];
    final results = await groupMembersMatchingRemarks(
      groupID: 'group',
      keyword: '备注',
      isCurrent: () => true,
      loadMembers: (ids) async {
        batches.add(ids);
        return [
          for (final id in ids) _member(id),
          _member('stranger'),
          _member(ids.first, group: 'another-group'),
          _member(ids.last, role: 0),
        ];
      },
    );
    expect(batches.map((ids) => ids.length), [100, 100, 5]);
    expect(results, hasLength(205));
    expect(results.any((m) => m.userID == 'stranger'), isFalse);
    expect(results.every((m) => m.groupID == 'group'), isTrue);
    expect(results.every((m) => m.roleLevel == GroupRoleLevel.member), isTrue);
  });

  test('remark search rejects a response after the search/session expires',
      () async {
    contacts.remarks['unloaded-peer'] = '搜索备注';
    final pending = Completer<List<GroupMembersInfo>>();
    var current = true;
    final search = groupMembersMatchingRemarks(
        groupID: 'group',
        keyword: '搜索备注',
        isCurrent: () => current,
        loadMembers: (_) => pending.future);
    current = false;
    pending.complete([_member('unloaded-peer')]);
    expect(await search, isEmpty);
  });
}
