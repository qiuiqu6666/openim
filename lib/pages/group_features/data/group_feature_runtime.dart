import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import '../../../core/controller/im_controller.dart';
import '../../../core/im_callback.dart';
import 'group_feature_api.dart';
import 'group_feature_store.dart';
export 'group_feature_store.dart';

/// App owns one cache across routes; account/token/server changes replace it.
class GroupFeatureRuntime {
  GroupFeatureRuntime._();
  static GroupFeatureStore? _store;
  static String _user = '', _token = '', _base = '';
  static GroupFeatureStore forAccount(IMController im) {
    final user = OpenIM.iMManager.userID,
        token = DataSp.chatToken ?? '',
        base = Config.appAuthUrl;
    if (_store == null || _user != user || _token != token || _base != base) {
      _store?.dispose();
      _user = user;
      _token = token;
      _base = base;
      _store = GroupFeatureStore(
          api: GroupFeatureApi(),
          sessionCurrent: () =>
              OpenIM.iMManager.userID == user &&
              DataSp.chatToken == token &&
              Config.appAuthUrl == base,
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
    _store?.invalidateSession();
    _store?.dispose();
    _store = null;
    _user = '';
    _token = '';
    _base = '';
  }
}
