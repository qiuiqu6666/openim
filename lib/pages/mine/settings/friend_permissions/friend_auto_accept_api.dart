import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Uses the authenticated profile endpoint; old backends must not report success.
class FriendAutoAcceptApi {
  static Future<void> setEnabled(bool enabled) async {
    final owner = OpenIM.iMManager.userID;
    if (owner.isEmpty) throw StateError('Not signed in');
    await HttpUtil.post(Urls.updateUserInfo,
        data: {
          'userID': owner,
          'autoAcceptFriend': enabled,
          'platform': IMUtils.getPlatform(),
        },
        options: Apis.chatTokenOptions,
        showErrorToast: false);
    if (OpenIM.iMManager.userID != owner) throw StateError('Account changed');
    final info = await Apis.queryMyFullInfo();
    if (OpenIM.iMManager.userID != owner ||
        info?.userID != owner ||
        info?.autoAcceptFriend != enabled) {
      throw StateError('Friend approval setting was not confirmed');
    }
  }
}
