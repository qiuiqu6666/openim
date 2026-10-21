import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Resolve missing group names from public profiles, not the friend directory.
Future<Map<String, String>> resolveMentionNames(
  List<GroupMembersInfo> members, {
  Future<List<PublicUserInfo>> Function(List<String>)? loadUsers,
}) async {
  final names = <String, String>{};
  final missing = <String>{};
  for (final member in members) {
    final id = member.userID;
    if (id == null || id.isEmpty) continue;
    final name = member.nickname?.trim() ?? '';
    names[id] = IMUtils.getAtNickname(id, name);
    if (name.isEmpty && id != 'atAllTag') missing.add(id);
  }
  if (missing.isNotEmpty) {
    try {
      final users = await (loadUsers ??
          (ids) => OpenIM.iMManager.userManager
              .getUsersInfo(userIDList: ids))(missing.toList());
      for (final user in users) {
        final name = user.nickname?.trim() ?? '';
        if (missing.contains(user.userID) && name.isNotEmpty) {
          names[user.userID!] = name;
        }
      }
    } catch (_) {
      // Offline/profile failures must not insert an empty mention.
    }
  }
  return names;
}
