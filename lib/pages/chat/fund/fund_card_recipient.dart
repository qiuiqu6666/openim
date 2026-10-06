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
    if (groupID.isNotEmpty) {
      try {
        final members = await OpenIM.iMManager.groupManager
            .getGroupMembersInfo(groupID: groupID, userIDList: [userID]);
        for (final member in members) {
          if (member.userID == userID) {
            return FundCardRecipient(
                userID: userID,
                name: member.nickname ?? '',
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
            name: user.nickname ?? '',
            faceURL: user.faceURL ?? '');
      }
    }
    return FundCardRecipient(userID: userID);
  }
}
