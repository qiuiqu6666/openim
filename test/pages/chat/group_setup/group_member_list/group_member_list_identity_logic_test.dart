import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/chat/group/identity/group_member_identity.dart';
import 'package:openim/pages/chat/group_setup/group_member_list/group_member_identity_state.dart';
import 'package:openim/pages/chat/group_setup/group_member_list/group_member_list_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'group_member_identity_state_test.dart' show sourceWith, response;
import '../members/group_preview_fixture.dart' show PreviewIM;

class _IdentityApp extends GetxController implements AppController {
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

  test(
      'rule change removes all held accounts before reload and rejects old page',
      () async {
    final pending = <Completer<dynamic>>[];
    final state = GroupMemberIdentityState(
      session: () => 'session',
      source: sourceWith((url, data, options) {
        final next = Completer<dynamic>();
        pending.add(next);
        return next.future;
      }),
    );
    final logic = GroupMemberListLogic(identity: state)
      ..groupInfo = GroupInfo(groupID: 'group', lookMemberInfo: 0)
      ..opType = GroupMemberOpType.at;
    addTearDown(logic.onClose);
    final held = GroupMemberIdentityInfo(
        groupID: 'group', userID: 'im_peer', account: '1234567890');
    logic.memberList.add(held);
    logic.searchResults.add(held);
    logic.checkedList.add(held);
    logic.searchController.text = 'Peer';
    logic.query.value = 'Peer';
    final oldLoad = logic.onLoad();

    logic.onGroupIdentityRulesChanged(
        GroupInfo(groupID: 'group', lookMemberInfo: 1));
    expect(held.account, isNull);
    expect(logic.memberList, isEmpty);
    expect(logic.searchResults, isEmpty);
    expect(logic.checkedList, isEmpty);
    expect(logic.query.value, isEmpty);
    expect(logic.searchController.text, isEmpty);
    expect(pending, hasLength(2));

    pending.first.complete(response(account: '1234567890'));
    await oldLoad;
    expect(logic.memberList, isEmpty);
    pending.last.complete(response());
    await Future<void>.delayed(Duration.zero);
    expect(logic.memberList.single.userID, 'im_peer');
    expect(logic.displayedAccount(logic.memberList.single), isEmpty);
  });

  test(
      'self demotion updates list permissions immediately; SDK metadata retains authority account',
      () async {
    final state = GroupMemberIdentityState(
      session: () => 'session',
      source: sourceWith((url, data, options) async => response()),
    );
    final logic = GroupMemberListLogic(identity: state)
      ..groupInfo = GroupInfo(groupID: 'group', lookMemberInfo: 1)
      ..opType = GroupMemberOpType.del;
    addTearDown(logic.onClose);
    logic.myGroupMemberLevel.value = GroupRoleLevel.admin;
    final held = GroupMemberIdentityInfo(
        groupID: 'group', userID: 'im_peer', account: '1234567890');
    logic.memberList.add(held);
    logic.onGroupMemberChanged(GroupMembersInfo(
        groupID: 'group',
        userID: 'im_peer',
        nickname: 'Updated',
        roleLevel: GroupRoleLevel.member));
    expect(logic.memberList.single.nickname, 'Updated');
    expect(logic.displayedAccount(logic.memberList.single), '1234567890');

    logic.checkedList.add(held);
    logic.onGroupMemberChanged(GroupMembersInfo(
        groupID: 'group', userID: 'viewer', roleLevel: GroupRoleLevel.member));
    expect(logic.isAdmin, isFalse);
    expect(logic.myGroupMemberLevel.value, GroupRoleLevel.member);
    expect(held.account, isNull);
    expect(logic.checkedList, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(logic.displayedAccount(logic.memberList.single), isEmpty);
  });

  test('an in-place group rule update still invalidates retained accounts',
      () async {
    final pending = Completer<dynamic>();
    var requests = 0;
    final state = GroupMemberIdentityState(
      session: () => 'session',
      source: sourceWith((url, data, options) {
        requests++;
        return pending.future;
      }),
    );
    final group = GroupInfo(groupID: 'group', lookMemberInfo: 0);
    final logic = GroupMemberListLogic(identity: state)
      ..groupInfo = group
      ..opType = GroupMemberOpType.view;
    addTearDown(logic.onClose);
    logic.onGroupIdentityRulesChanged(group);
    final held = GroupMemberIdentityInfo(
        groupID: 'group', userID: 'im_peer', account: '1234567890');
    logic.memberList.add(held);
    group.lookMemberInfo = 1;
    logic.onGroupIdentityRulesChanged(group);
    expect(held.account, isNull);
    expect(requests, 1);
    pending.complete(response());
    await Future<void>.delayed(Duration.zero);
    expect(logic.displayedAccount(logic.memberList.single), isEmpty);
  });

  test(
      'another member deletion clears only their held accounts without requery',
      () async {
    var session = 'session';
    var requests = 0;
    final state = GroupMemberIdentityState(
      session: () => session,
      source: sourceWith((url, data, options) async {
        requests++;
        return response();
      }),
    );
    final logic = GroupMemberListLogic(identity: state)
      ..groupInfo = GroupInfo(groupID: 'group')
      ..opType = GroupMemberOpType.at;
    addTearDown(logic.onClose);
    final removed = List.generate(
        3,
        (_) => GroupMemberIdentityInfo(
            groupID: 'group', userID: 'im_peer', account: '1234567890'));
    final kept = GroupMemberIdentityInfo(
        groupID: 'group', userID: 'im_other', account: '0987654321');
    for (final (index, list)
        in [logic.memberList, logic.searchResults, logic.checkedList].indexed) {
      list.addAll([removed[index], kept]);
    }
    logic.setPresenceVisible('im_peer', true);
    final generation = state.generation;

    logic.onGroupMemberDeleted(
        GroupMembersInfo(groupID: 'other_group', userID: 'im_peer'));
    session = 'another_session';
    logic.onGroupMemberDeleted(
        GroupMembersInfo(groupID: 'group', userID: 'im_peer'));
    expect(removed.every((member) => member.account != null), isTrue);
    expect(logic.memberList, hasLength(2));
    session = 'session';

    logic.onGroupMemberDeleted(
        GroupMembersInfo(groupID: 'group', userID: 'im_peer'));
    expect(removed.every((member) => member.account == null), isTrue);
    for (final list in [
      logic.memberList,
      logic.searchResults,
      logic.checkedList
    ]) {
      expect(list, [kept]);
    }
    expect(kept.account, '0987654321');
    expect(state.generation, generation);
    expect(state.isCurrentSession, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 0);
  });

  for (final leave in ['removed', 'left']) {
    test('$leave membership clears held identities without requery', () async {
      final pending = Completer<dynamic>();
      var requests = 0;
      final state = GroupMemberIdentityState(
        session: () => 'session',
        source: sourceWith((url, data, options) {
          requests++;
          return pending.future;
        }),
      );
      final logic = GroupMemberListLogic(identity: state)
        ..groupInfo = GroupInfo(groupID: 'group')
        ..opType = GroupMemberOpType.view;
      addTearDown(logic.onClose);
      final held = GroupMemberIdentityInfo(
          groupID: 'group', userID: 'im_peer', account: '1234567890');
      logic.memberList.add(held);
      logic.checkedList.add(held);
      final loading = logic.onLoad();
      if (leave == 'removed') {
        logic.onGroupMemberDeleted(
            GroupMembersInfo(groupID: 'group', userID: 'viewer'));
      } else {
        logic.onJoinedGroupDeleted(GroupInfo(groupID: 'group'));
      }
      expect(held.account, isNull);
      expect(logic.memberList, isEmpty);
      expect(logic.checkedList, isEmpty);
      pending.complete(response(account: '1234567890'));
      await loading;
      await logic.onLoad();
      expect(logic.memberList, isEmpty);
      expect(requests, 1);
    });
  }

  test(
      'resume refreshes unchanged group rules and self role once before requery',
      () async {
    final pendingRules = Completer<GroupMemberIdentityRules>();
    var requests = 0;
    var ruleRequests = 0;
    final state = GroupMemberIdentityState(
      session: () => 'session',
      rulesLoader: (_) {
        ruleRequests++;
        return pendingRules.future;
      },
      source: sourceWith((url, data, options) async {
        requests++;
        return response();
      }),
    );
    final logic = GroupMemberListLogic(identity: state)
      ..groupInfo = GroupInfo(groupID: 'group', lookMemberInfo: 1)
      ..opType = GroupMemberOpType.view;
    logic.myGroupMemberLevel.value = GroupRoleLevel.admin;
    addTearDown(logic.onClose);
    final held = GroupMemberIdentityInfo(
        groupID: 'group', userID: 'im_peer', account: '1234567890');
    logic.memberList.add(held);
    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(held.account, isNull);
    expect(ruleRequests, 1);
    expect(requests, 0);
    pendingRules.complete((
      group: GroupInfo(groupID: 'group', lookMemberInfo: 1),
      self: GroupMembersInfo(
          groupID: 'group', userID: 'viewer', roleLevel: GroupRoleLevel.member),
    ));
    await Future<void>.delayed(Duration.zero);
    expect(logic.isAdmin, isFalse);
    expect(requests, 1);
    expect(logic.displayedAccount(logic.memberList.single), isEmpty);
  });

  testWidgets(
      'self profile events revoke old accounts and skip the cached replay',
      (tester) async {
    Get.testMode = true;
    Get.put<AppController>(_IdentityApp());
    final im = Get.put<IMController>(PreviewIM()) as PreviewIM;
    im.selfInfoUpdated(UserInfo(userID: 'viewer', appMangerLevel: 2));
    final pending = <Completer<dynamic>>[];
    final state = GroupMemberIdentityState(
      session: () => 'session',
      source: sourceWith((url, data, options) {
        if (url.endsWith('/group/get_group_members_info')) {
          return Future.value(response(id: 'viewer'));
        }
        final next = Completer<dynamic>();
        pending.add(next);
        return next.future;
      }),
    );
    Get.routing.args = {
      'groupInfo': GroupInfo(groupID: 'group', lookMemberInfo: 1),
      'opType': GroupMemberOpType.view,
    };
    final logic = Get.put(GroupMemberListLogic(identity: state));
    addTearDown(() {
      for (final reply in pending) {
        if (!reply.isCompleted) reply.complete(response());
      }
      Get.reset();
      Get.routing.args = null;
    });
    await tester.idle();
    expect(pending, isEmpty);
    logic.onReady();
    await tester.pump();
    await tester.pump();
    expect(pending, hasLength(1));
    pending.single.complete(response(account: '@1234567890'));
    await tester.pump();
    final held = logic.memberList.single as GroupMemberIdentityInfo;
    logic.checkedList.add(held);
    final old = logic.onLoad();
    im.selfInfoUpdated(UserInfo(userID: 'another-viewer'));
    await tester.pump();
    expect(pending, hasLength(2));
    expect(held.account, '@1234567890');

    im.selfInfoUpdated(UserInfo(userID: 'viewer', appMangerLevel: 1));
    await tester.pump();
    expect(logic.myGroupMemberLevel.value, GroupRoleLevel.member);
    expect(held.account, isNull);
    expect(logic.memberList, isEmpty);
    expect(logic.checkedList, isEmpty);
    expect(pending, hasLength(3));
    pending[1].complete(response(account: '@1234567890'));
    await old;
    expect(logic.memberList, isEmpty);
    pending.last.complete(response());
    await tester.pump();
    expect(logic.displayedAccount(logic.memberList.single), isEmpty);

    await Get.delete<GroupMemberListLogic>();
    expect(im.selfInfoUpdatedSubject.hasListener, isFalse);
    im.selfInfoUpdated(UserInfo(userID: 'viewer'));
    await tester.pump();
    expect(pending, hasLength(3));
  });

  test('self profile event replaces an unfinished initial group role read',
      () async {
    final roles = <Completer<dynamic>>[];
    final pages = <Completer<dynamic>>[];
    final state = GroupMemberIdentityState(
      session: () => 'session',
      source: sourceWith((url, data, options) {
        final next = Completer<dynamic>();
        if (url.endsWith('/group/get_group_members_info')) {
          roles.add(next);
        } else {
          pages.add(next);
        }
        return next.future;
      }),
    );
    final logic = GroupMemberListLogic(identity: state)
      ..groupInfo = GroupInfo(groupID: 'group', lookMemberInfo: 1)
      ..opType = GroupMemberOpType.view;
    addTearDown(logic.onClose);
    logic.onReady();
    expect(roles, hasLength(1));
    expect(pages, isEmpty);
    logic.onSelfInfoUpdated(UserInfo(userID: 'viewer', appMangerLevel: 1));
    expect(roles, hasLength(2));
    expect(pages, hasLength(1));

    final oldRole = response(id: 'viewer');
    (oldRole['members'] as List).single['roleLevel'] = GroupRoleLevel.admin;
    roles.first.complete(oldRole);
    await Future<void>.delayed(Duration.zero);
    expect(logic.myGroupMemberLevel.value, 1);
    roles.last.complete(response(id: 'viewer'));
    await Future<void>.delayed(Duration.zero);
    expect(logic.myGroupMemberLevel.value, GroupRoleLevel.member);
    expect(pages, hasLength(1));
    pages.single.complete(response());
    await Future<void>.delayed(Duration.zero);
    expect(logic.displayedAccount(logic.memberList.single), isEmpty);
  });
}
