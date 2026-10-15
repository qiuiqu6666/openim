import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import '../../../core/controller/im_controller.dart';
import '../../../core/im_callback.dart';
import 'group_feature_api.dart';
import 'group_feature_store.dart';
export 'group_feature_store.dart';

/// One cache per login session, shared by every route. Transport switches keep
/// its identity; GroupFeatureApi resolves and fences the current endpoint.
class GroupFeatureRuntime {
  GroupFeatureRuntime._();
  static GroupFeatureStore? _store;
  static String _user = '', _token = '';
  static GroupFeatureStore forAccount(IMController im) {
    final user = OpenIM.iMManager.userID, token = DataSp.chatToken ?? '';
    if (_store == null || _user != user || _token != token) {
      _store?.retireSession();
      _user = user;
      _token = token;
      _store = GroupFeatureStore(
          api: GroupFeatureApi(),
          sessionCurrent: () =>
              OpenIM.iMManager.userID == user && DataSp.chatToken == token,
          fetchGroups: (ids) =>
              OpenIM.iMManager.groupManager.getGroupsInfo(groupIDList: ids));
      _store!.bindSources(
          groupChanged: im.groupInfoUpdatedSubject,
          joined: im.joinedGroupAddedSubject,
          left: im.joinedGroupDeletedSubject,
          memberDeleted: im.memberDeletedSubject,
          memberChanged: im.memberInfoChangedSubject,
          business: im.customBusinessMessageSubject,
          messages: im.receivedMessages,
          synced: im.imSdkStatusPublishSubject
              .where((e) => e.status == IMSdkStatus.syncEnded)
              .map<void>((_) {}),
          kicked: im.onKickedOfflineSubject.map<void>((_) {}),
          currentUserID: () => OpenIM.iMManager.userID);
    }
    return _store!;
  }

  static void reset() {
    _store?.retireSession();
    _store = null;
    _user = '';
    _token = '';
  }
}
