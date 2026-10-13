import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Optional SDK display metadata, independent from payment authorization.
class FundCardRecipient {
  const FundCardRecipient(
      {this.userID = '', this.name = '', this.faceURL = ''});
  final String userID;
  final String name;
  final String faceURL;

  static Future<FundCardRecipient> resolve(
      String userID, String groupID) async {
    // Resolve from the viewer's SDK friendship data. Never put this private
    // display name into the shared order or message payload.
    String? remark;
    try {
      final friends = await OpenIM.iMManager.friendshipManager
          .getFriendsInfo(userIDList: [userID]);
      for (final friend in friends) {
        if (friend.userID == userID &&
            friend.remark?.trim().isNotEmpty == true) {
          remark = friend.remark!.trim();
          break;
        }
      }
    } catch (_) {
      // Non-friends and unavailable local metadata fall back to SDK nicknames.
    }
    if (groupID.isNotEmpty) {
      try {
        final members = await OpenIM.iMManager.groupManager
            .getGroupMembersInfo(groupID: groupID, userIDList: [userID]);
        for (final member in members) {
          if (member.userID == userID) {
            return FundCardRecipient(
                userID: userID,
                name: remark ?? member.nickname ?? '',
                faceURL: member.faceURL ?? '');
          }
        }
      } catch (_) {
        // A former member can still have a readable user profile.
      }
    }
    final users =
        await OpenIM.iMManager.userManager.getUsersInfo(userIDList: [userID]);
    for (final user in users) {
      if (user.userID == userID) {
        return FundCardRecipient(
            userID: userID,
            name: remark ?? user.nickname ?? '',
            faceURL: user.faceURL ?? '');
      }
    }
    return FundCardRecipient(userID: userID, name: remark ?? '');
  }
}
