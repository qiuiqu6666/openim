// Regression coverage for the group-state audit and promotion scenarios.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/pages/chat/group_setup/group_manage/group_member_permissions_page.dart';
import 'package:openim/pages/chat/group_setup/group_member_list/group_member_identity_state.dart';
import 'package:openim/pages/chat/group_setup/group_member_list/group_member_list_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/chat_group_harness.dart';
import '../group_setup/group_member_list/group_member_identity_state_test.dart'
    show sourceWith, response;
import '../group_setup/members/group_preview_fixture.dart' show PreviewIM;

class _AuditApp extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    OpenIM.iMManager.userID = 'viewer';
  });

  testWidgets('sync completion re-reads self mute and role', (tester) async {
    var muted = false;
    var role = GroupRoleLevel.admin;
    final h = ChatGroupHarness(
        selfMember: (id, user) async => [
              GroupMembersInfo(
                  groupID: id,
                  userID: user,
                  roleLevel: role,
                  muteEndTime: muted ? 2000 : 0),
            ]);
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    muted = true;
    role = GroupRoleLevel.member;
    h.controller.recover(resetAttempts: true);
    await h.controller.refreshProfileAfterSync();
    expect(h.selfReads, 2);
    expect(h.controller.personallyMuted, isTrue);
    expect(h.controller.isAdminOrOwner, isFalse);
    h.changed.add(GroupMembersInfo(
        groupID: 'group', userID: 'me', roleLevel: role, muteEndTime: 2000));
    await tester.pump();
    expect(h.controller.personallyMuted, isTrue);
    expect(h.controller.isAdminOrOwner, isFalse);
    h.controller.close();
  });

  testWidgets('member event during sync verification wins over stale query',
      (tester) async {
    final verification = Completer<bool>();
    var initial = true;
    final h = ChatGroupHarness(
      verifyMembership: (_, __) =>
          initial ? Future.value(true) : verification.future,
      selfMember: (id, user) async => [
        GroupMembersInfo(
            groupID: id,
            userID: user,
            roleLevel: GroupRoleLevel.member,
            muteEndTime: 2000)
      ],
      admins: (_) async => [],
    );
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    initial = false;
    final refresh = h.controller.refreshProfileAfterSync();
    h.changed.add(GroupMembersInfo(
        groupID: 'group',
        userID: 'me',
        roleLevel: GroupRoleLevel.owner,
        muteEndTime: 0));
    verification.complete(true);
    await refresh;
    expect(h.controller.groupMemberRoleLevel.value, GroupRoleLevel.owner);
    expect(h.controller.sendingMuted, isFalse);
    expect(h.controller.ownerAndAdmin.any((m) => m.userID == 'me'), isTrue);
    h.controller.close();
  });

  testWidgets('sync self lookup failure recovers without another event',
      (tester) async {
    var reads = 0;
    final h = ChatGroupHarness(selfMember: (id, user) async {
      reads++;
      if (reads == 2) throw StateError('temporary self lookup failure');
      return [
        GroupMembersInfo(
            groupID: id,
            userID: user,
            roleLevel:
                reads >= 3 ? GroupRoleLevel.admin : GroupRoleLevel.member)
      ];
    });
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    await h.controller.refreshProfileAfterSync();
    await tester.pump(const Duration(seconds: 1));
    expect(reads, greaterThanOrEqualTo(3));
    expect(h.controller.groupMemberRoleLevel.value, GroupRoleLevel.admin);
    h.controller.close();
  });

  testWidgets('stale positive membership is verified and revoked',
      (tester) async {
    var verifyReads = 0;
    final h = ChatGroupHarness(verifyMembership: (_, __) async {
      verifyReads++;
      return false;
    });
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    h.controller.recover(resetAttempts: true);
    await h.controller.refreshProfileAfterSync();
    expect(verifyReads, greaterThan(0));
    expect(h.controller.isInGroup.value, isFalse);
    expect(h.controller.isInvalidGroup, isTrue);
  });

  testWidgets('expired server millisecond deadline allows sending',
      (tester) async {
    const nowSeconds = 1792627200;
    final raw = {
      'groupID': 'group',
      'userID': 'me',
      'roleLevel': GroupRoleLevel.member,
      'muteEndTime': (nowSeconds - 60) * 1000
    };
    final h = ChatGroupHarness(
        selfMember: (_, __) async => [GroupMembersInfo.fromJson(raw)]);
    h.now = nowSeconds;
    h.controller.initialize();
    await h.controller.loadAfterHistory();
    expect(h.controller.groupMembersInfo!.muteEndTime, raw['muteEndTime']);
    expect(h.controller.personallyMuted, isFalse);
    expect(h.controller.sendingMuted, isFalse);
    h.controller.close();
  });

  for (final role in [GroupRoleLevel.admin, GroupRoleLevel.owner]) {
    testWidgets('promotion to $role applies the server personal-mute rule',
        (tester) async {
      final h = ChatGroupHarness(
        groupInfo: (id) async => [GroupInfo(groupID: id, status: 3)],
        selfMember: (id, user) async => [
          GroupMembersInfo(
              groupID: id,
              userID: user,
              roleLevel: GroupRoleLevel.member,
              muteEndTime: 2000)
        ],
      );
      h.controller.initialize();
      await h.controller.loadAfterHistory();
      h.changed.add(GroupMembersInfo(
          groupID: 'group', userID: 'me', roleLevel: role, muteEndTime: 2000));
      await tester.pump();
      expect(h.controller.groupMemberRoleLevel.value, role);
      expect(h.controller.isAdminOrOwner, isTrue);
      expect(h.controller.sendingMuted, role == GroupRoleLevel.admin,
          reason: 'Only owners are exempt from a personal mute');
      h.changed.add(GroupMembersInfo(
          groupID: 'group', userID: 'me', roleLevel: role, muteEndTime: 0));
      await tester.pump();
      expect(h.controller.sendingMuted, isFalse,
          reason:
              'Both elevated roles are exempt from mute-all once personal mute clears');
      h.controller.close();
    });
  }

  test('a pre-deletion page cannot resurrect removed member', () async {
    final reply = Completer<dynamic>();
    final state = GroupMemberIdentityState(
        session: () => 'session',
        source: sourceWith((_, __, ___) => reply.future));
    final logic = GroupMemberListLogic(identity: state)
      ..groupInfo = GroupInfo(groupID: 'group')
      ..opType = GroupMemberOpType.view;
    addTearDown(logic.onClose);
    logic.memberList.add(GroupMembersInfo(groupID: 'group', userID: 'im_peer'));
    final request = logic.onLoad();
    logic.onGroupMemberDeleted(
        GroupMembersInfo(groupID: 'group', userID: 'im_peer'));
    expect(logic.memberList, isEmpty);
    reply.complete(response());
    await request;
    expect(logic.memberList, isEmpty);
  });

  test('a pre-role-change page preserves newer role event', () async {
    final reply = Completer<dynamic>();
    final state = GroupMemberIdentityState(
        session: () => 'session',
        source: sourceWith((_, __, ___) => reply.future));
    final logic = GroupMemberListLogic(identity: state)
      ..groupInfo = GroupInfo(groupID: 'group')
      ..opType = GroupMemberOpType.view;
    addTearDown(logic.onClose);
    final request = logic.onLoad();
    logic.onGroupMemberChanged(GroupMembersInfo(
        groupID: 'group', userID: 'im_peer', roleLevel: GroupRoleLevel.admin));
    reply.complete(response());
    await request;
    expect(logic.memberList.single.roleLevel, GroupRoleLevel.admin);
  });

  for (final mode in [
    MemberPermissionMode.admins,
    MemberPermissionMode.muted
  ]) {
    testWidgets('$mode removes departed members and revoked controls',
        (tester) async {
      Get.testMode = true;
      Get.put<AppController>(_AuditApp());
      final im = PreviewIM();
      Get.put<IMController>(im);
      const channel = MethodChannel('flutter_openim_sdk');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'getGroupMemberList') {
          return jsonEncode([
            GroupMembersInfo(
                    groupID: 'group',
                    userID: 'peer',
                    nickname: 'AuditPeer',
                    roleLevel: GroupRoleLevel.admin,
                    muteEndTime:
                        DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600)
                .toJson(),
          ]);
        }
        return null;
      });
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        Get.reset();
      });
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
                translations: TranslationService(),
                locale: const Locale('zh', 'CN'),
                home: GroupMemberPermissionsPage(
                    groupID: 'group', owner: true, mode: mode),
              )));
      await tester.pumpAndSettle();
      expect(find.text('AuditPeer'), findsOneWidget);
      im.memberInfoChangedSubject.add(GroupMembersInfo(
          groupID: 'group',
          userID: 'viewer',
          roleLevel: GroupRoleLevel.member));
      await tester.pumpAndSettle();
      expect(find.text('AuditPeer'), findsOneWidget);
      expect(
          find.byTooltip(
              mode == MemberPermissionMode.admins ? '移除管理员' : '解除禁言'),
          findsNothing,
          reason: 'Revoking the viewer role disables actions without leaving');
      im.memberDeletedSubject
          .add(GroupMembersInfo(groupID: 'group', userID: 'peer'));
      await tester.pumpAndSettle();
      expect(find.text('AuditPeer'), findsNothing);
      im.joinedGroupDeletedSubject.add(GroupInfo(groupID: 'group'));
      await tester.pumpAndSettle();
      expect(find.text('AuditPeer'), findsNothing);
      expect(
          find.byTooltip(
              mode == MemberPermissionMode.admins ? '移除管理员' : '解除禁言'),
          findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
