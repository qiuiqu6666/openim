import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../data_sp.dart';

/// Local feedback only. The server checks both directions authoritatively.
class FriendRelationshipGuard {
  static Future<void> requireNotBlocked(String peer) async {
    final owner = (OpenIM.iMManager.userID, DataSp.chatToken);
    final entries = await OpenIM.iMManager.friendshipManager.getBlacklist();
    if (owner != (OpenIM.iMManager.userID, DataSp.chatToken)) {
      throw PlatformException(code: '20013');
    }
    if (entries.any((entry) => (entry.blockUserID ?? entry.userID) == peer)) {
      throw PlatformException(code: 'FriendBlacklisted');
    }
  }
}
