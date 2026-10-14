import 'dart:math';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Only actual members of this group may be added from contact-remark matches.
Future<List<GroupMembersInfo>> groupMembersMatchingRemarks({
  required String groupID,
  required String keyword,
  required bool Function() isCurrent,
  Future<List<GroupMembersInfo>> Function(List<String> userIDs)? loadMembers,
}) async {
  final ids = ContactRemarkSource.current
          ?.matchingRemarkUserIDs(keyword)
          .toSet()
          .toList(growable: false) ??
      const <String>[];
  final load = loadMembers ??
      (userIDs) => OpenIM.iMManager.groupManager
          .getGroupMembersInfo(groupID: groupID, userIDList: userIDs);
  final matches = <String, GroupMembersInfo>{};
  for (var offset = 0; offset < ids.length; offset += 100) {
    if (!isCurrent()) return [];
    final batch = ids.sublist(offset, min(offset + 100, ids.length));
    final members = await load(batch);
    if (!isCurrent()) return [];
    for (final member in members) {
      final id = member.userID;
      if (id != null &&
          batch.contains(id) &&
          member.groupID == groupID &&
          (member.roleLevel ?? 0) >= GroupRoleLevel.member) {
        matches[id] = member;
      }
    }
  }
  return matches.values.toList(growable: false);
}

bool groupMemberMatchesQuery(GroupMembersInfo member, String keyword) {
  final query = keyword.trim().toLowerCase();
  return query.isEmpty ||
      [
        member.userID,
        member.nickname,
        ContactRemarkSource.current?.remarkFor(member.userID),
      ].any((name) => name?.toLowerCase().contains(query) == true);
}
