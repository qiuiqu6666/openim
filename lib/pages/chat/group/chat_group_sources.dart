import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../../core/controller/im_controller.dart';

/// The six SDK event streams owned by the chat's group feature.
class ChatGroupEvents {
  const ChatGroupEvents({
    required this.joined,
    required this.left,
    required this.memberAdded,
    required this.memberDeleted,
    required this.memberChanged,
    required this.groupChanged,
  });

  factory ChatGroupEvents.fromController(IMController im) => ChatGroupEvents(
        joined: im.joinedGroupAddedSubject,
        left: im.joinedGroupDeletedSubject,
        memberAdded: im.memberAddedSubject,
        memberDeleted: im.memberDeletedSubject,
        memberChanged: im.memberInfoChangedSubject,
        groupChanged: im.groupInfoUpdatedSubject,
      );

  final Stream<GroupInfo> joined, left, groupChanged;
  final Stream<GroupMembersInfo> memberAdded, memberDeleted, memberChanged;
}

/// SDK queries are separate from event subscriptions so lifecycle races can be
/// tested without creating the app's global SDK controller.
class ChatGroupQueries {
  const ChatGroupQueries({
    required this.isJoined,
    required this.groupInfo,
    required this.selfMember,
    required this.ownerAndAdmin,
  });

  factory ChatGroupQueries.sdk() => ChatGroupQueries(
        isJoined: (id) =>
            OpenIM.iMManager.groupManager.isJoinedGroup(groupID: id),
        groupInfo: (id) =>
            OpenIM.iMManager.groupManager.getGroupsInfo(groupIDList: [id]),
        selfMember: (id, userID) => OpenIM.iMManager.groupManager
            .getGroupMembersInfo(groupID: id, userIDList: [userID]),
        ownerAndAdmin: (id) => OpenIM.iMManager.groupManager
            .getGroupMemberList(groupID: id, filter: 5, count: 20),
      );

  final Future<bool> Function(String groupID) isJoined;
  final Future<List<GroupInfo>> Function(String groupID) groupInfo;
  final Future<List<GroupMembersInfo>> Function(String groupID, String userID)
      selfMember;
  final Future<List<GroupMembersInfo>> Function(String groupID) ownerAndAdmin;
}
