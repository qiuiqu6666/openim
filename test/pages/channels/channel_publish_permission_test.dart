import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../chat/group/support/chat_group_harness.dart';

void main() {
  test('channel members cannot send even when group mute is disabled', () {
    final h = ChatGroupHarness();
    final controller = h.controller;
    controller.membershipPending.value = false;
    controller.groupInfo = GroupInfo(groupID: 'group', status: 0,
      ex: '{"conversationKind":"channel"}');
    for (final role in [GroupRoleLevel.member, GroupRoleLevel.admin, GroupRoleLevel.owner]) {
      controller.groupMembersInfo = GroupMembersInfo(userID: 'me', roleLevel: role);
      controller.groupMemberRoleLevel.value = role;
      expect(controller.sendingMuted, role == GroupRoleLevel.member);
    }
    controller.groupMemberRoleLevel.value = GroupRoleLevel.member;
    expect(controller.sendingMuted, isTrue, reason: 'Revoked admin loses posting permission');
    controller.groupInfo!.ex = '{}';
    expect(controller.sendingMuted, isFalse, reason: 'Ordinary group behavior remains unchanged');
  });
}
