import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Friend remarks are local display metadata, never transfer identities.
Future<String?> loadFundRecipientRemark(String userID) async {
  try {
    final friends = await OpenIM.iMManager.friendshipManager.getFriendsInfo(
        userIDList: [userID]);
    for (final friend in friends) {
      final remark = friend.remark?.trim() ?? '';
      if (friend.userID == userID && remark.isNotEmpty) return remark;
    }
  } catch (_) {
    // Display the existing nickname when friend metadata is unavailable.
  }
  return null;
}
