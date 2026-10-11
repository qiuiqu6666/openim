import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../routes/app_navigator.dart';
import '../group_profile_panel/group_profile_panel_logic.dart';

/// The entry page supplies its lifecycle/session guard after the scanner exits.
Future<void> openScannedContact(Map<String, String> result,
    {required bool Function() isActive}) async {
  if (!isActive()) return;
  final groupID = result['groupID'];
  if (groupID != null) {
    await openScannedGroup(groupID, isActive: isActive);
    return;
  }
  await AppNavigator.startUserProfilePane(
    userID: result['userID']!,
    addSource: result['source'] == 'link'
        ? FriendAddSource.link
        : FriendAddSource.qrcode,
    friendAddFields: {'inviteCode': result['inviteCode']!},
    forceCanAdd: true,
  );
}

/// Resolve the display prefix through OpenIM before opening the group profile.
Future<void> openScannedGroup(String id,
    {required bool Function() isActive}) async {
  final owner = (OpenIM.iMManager.userID, DataSp.userID, DataSp.chatToken);
  bool canOpen() =>
      isActive() &&
      owner == (OpenIM.iMManager.userID, DataSp.userID, DataSp.chatToken);
  if (!canOpen()) return;
  try {
    final groups = await OpenIM.iMManager.groupManager.getGroupsInfo(
      groupIDList: [id, if (id.startsWith('@')) id.substring(1)],
    );
    if (!canOpen()) return;
    if (groups.isEmpty) {
      IMViews.showToast('groupQrNotFound'.tr);
      return;
    }
    await AppNavigator.startGroupProfilePanel(
      groupID: groups.first.groupID,
      joinGroupMethod: JoinGroupMethod.qrcode,
    );
  } catch (_) {
    if (canOpen()) IMViews.showToast('groupQrScanFailed'.tr);
  }
}
