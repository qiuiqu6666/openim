import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/member_actions/chat_member_action_policy.dart';

const _now = 1000;

GroupInfo _group({int? status = 0, int? groupType = GroupType.work}) =>
    GroupInfo(
      groupID: 'group',
      ownerUserID: 'owner',
      status: status,
      groupType: groupType,
    );

GroupMembersInfo _member(String id, int? role, {int? muteEndTime}) =>
    GroupMembersInfo(
      groupID: 'group',
      userID: id,
      roleLevel: role,
      muteEndTime: muteEndTime,
    );

List<ChatMemberAction> _actions({
  GroupInfo? group,
  GroupMembersInfo? self,
  GroupMembersInfo? target,
  bool isJoined = true,
  bool isReadOnly = false,
  bool sendingMuted = false,
  String? currentUserID,
}) {
  final actor = self ?? _member('owner', GroupRoleLevel.owner);
  return ChatMemberActionPolicy.actions(
    currentUserID: currentUserID ?? actor.userID!,
    group: group ?? _group(),
    self: actor,
    target: target ?? _member('member', GroupRoleLevel.member),
    isJoined: isJoined,
    isReadOnly: isReadOnly,
    sendingMuted: sendingMuted,
    nowSeconds: _now,
  );
}

void main() {
  group('group role hierarchy', () {
    const cases = <(int, int, bool)>[
      (GroupRoleLevel.owner, GroupRoleLevel.owner, false),
      (GroupRoleLevel.owner, GroupRoleLevel.admin, true),
      (GroupRoleLevel.owner, GroupRoleLevel.member, true),
      (GroupRoleLevel.admin, GroupRoleLevel.owner, false),
      (GroupRoleLevel.admin, GroupRoleLevel.admin, false),
      (GroupRoleLevel.admin, GroupRoleLevel.member, true),
      (GroupRoleLevel.member, GroupRoleLevel.owner, false),
      (GroupRoleLevel.member, GroupRoleLevel.admin, false),
      (GroupRoleLevel.member, GroupRoleLevel.member, false),
    ];
    for (final (actorRole, targetRole, canManage) in cases) {
      test('role $actorRole against role $targetRole', () {
        final actions = _actions(
          self: _member(
              actorRole == GroupRoleLevel.owner ? 'owner' : 'actor', actorRole),
          target: _member('target', targetRole),
        );
        expect(
          actions,
          canManage
              ? [
                  ChatMemberAction.mention,
                  ChatMemberAction.exclusiveRedPacket,
                  ChatMemberAction.mute,
                  ChatMemberAction.remove,
                ]
              : [ChatMemberAction.mention, ChatMemberAction.exclusiveRedPacket],
        );
      });
    }

    test('self avatar never exposes actions, including owner', () {
      for (final role in [
        GroupRoleLevel.owner,
        GroupRoleLevel.admin,
        GroupRoleLevel.member,
      ]) {
        final self = _member('actor', role);
        expect(_actions(self: self, target: self), isEmpty);
      }
    });

    test('owner ID protects a target with a stale regular member role', () {
      expect(
        _actions(
          self: _member('admin', GroupRoleLevel.admin),
          target: _member('owner', GroupRoleLevel.member),
        ),
        [ChatMemberAction.mention, ChatMemberAction.exclusiveRedPacket],
      );
    });

    test('previous owner loses management after ownership transfer', () {
      expect(
        _actions(group: _group()..ownerUserID = 'new-owner'),
        [ChatMemberAction.mention, ChatMemberAction.exclusiveRedPacket],
      );
    });

    test('unknown role never grants or receives management actions', () {
      for (final role in [null, 0, 50, 999]) {
        expect(_actions(self: _member('actor', role)),
            [ChatMemberAction.mention, ChatMemberAction.exclusiveRedPacket]);
        expect(_actions(target: _member('target', role)),
            [ChatMemberAction.mention, ChatMemberAction.exclusiveRedPacket]);
      }
    });
  });

  group('mute state', () {
    test('active target mute shows unmute with removal', () {
      expect(
        _actions(
            target: _member('target', GroupRoleLevel.member,
                muteEndTime: _now + 1)),
        [
          ChatMemberAction.mention,
          ChatMemberAction.exclusiveRedPacket,
          ChatMemberAction.unmute,
          ChatMemberAction.remove,
        ],
      );
    });

    test('expiry is exclusive and uses seconds', () {
      for (final end in [null, 0, _now - 1, _now]) {
        expect(
          _actions(
              target:
                  _member('target', GroupRoleLevel.member, muteEndTime: end)),
          [
            ChatMemberAction.mention,
            ChatMemberAction.exclusiveRedPacket,
            ChatMemberAction.mute,
            ChatMemberAction.remove,
          ],
        );
      }
    });

    test('muted regular member cannot mention anyone', () {
      expect(
        _actions(
          self: _member('actor', GroupRoleLevel.member),
          sendingMuted: true,
        ),
        isEmpty,
      );
    });

    test('muted manager retains moderation but cannot compose a mention', () {
      expect(_actions(sendingMuted: true),
          [ChatMemberAction.mute, ChatMemberAction.remove]);
    });

    test('all-member mute retains manager actions', () {
      expect(_actions(group: _group(status: 3)), [
        ChatMemberAction.mention,
        ChatMemberAction.exclusiveRedPacket,
        ChatMemberAction.mute,
        ChatMemberAction.remove,
      ]);
      expect(
        _actions(
          group: _group(status: 3),
          self: _member('actor', GroupRoleLevel.member),
          sendingMuted: true,
        ),
        isEmpty,
      );
    });
  });

  group('membership and group availability', () {
    test('left, banned, dismissed and read-only groups expose no actions', () {
      expect(_actions(isJoined: false), isEmpty);
      expect(_actions(isReadOnly: true), isEmpty);
      expect(_actions(group: _group(status: 1)), isEmpty);
      expect(_actions(group: _group(status: 2)), isEmpty);
    });

    test('OpenIM work and legacy group types use the same role hierarchy', () {
      // General groups (0) are deprecated in SDK v3; existing chats still work.
      for (final type in [0, GroupType.work]) {
        expect(
          _actions(
            group: _group(groupType: type),
            self: _member('admin', GroupRoleLevel.admin),
          ),
          [
            ChatMemberAction.mention,
            ChatMemberAction.exclusiveRedPacket,
            ChatMemberAction.mute,
            ChatMemberAction.remove,
          ],
        );
      }
    });

    test('mismatched account or group member data exposes no actions', () {
      expect(_actions(currentUserID: 'different-account'), isEmpty);
      expect(_actions(currentUserID: ' '), isEmpty);
      expect(_actions(group: _group()..groupID = ''), isEmpty);
      expect(
          _actions(
              self: _member('owner', GroupRoleLevel.owner)
                ..groupID = 'different-group'),
          isEmpty);
      expect(
          _actions(
              target: _member('target', GroupRoleLevel.member)
                ..groupID = 'different-group'),
          isEmpty);
      expect(_actions(target: _member(' ', GroupRoleLevel.member)), isEmpty);
    });

    test('missing fresh member or group records expose no actions', () {
      for (final missing in ['group', 'self', 'target']) {
        expect(
          ChatMemberActionPolicy.actions(
            currentUserID: 'owner',
            group: missing == 'group' ? null : _group(),
            self: missing == 'self'
                ? null
                : _member('owner', GroupRoleLevel.owner),
            target: missing == 'target'
                ? null
                : _member('member', GroupRoleLevel.member),
            isJoined: true,
            isReadOnly: false,
            sendingMuted: false,
            nowSeconds: _now,
          ),
          isEmpty,
        );
      }
    });
  });
}
