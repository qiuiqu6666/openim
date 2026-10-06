import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../global_search/global_search_logic.dart';
import '../select_contacts_logic.dart';
import '../../search/contact_search_source.dart';
import '../../../../core/session/session_request_errors.dart';

class SelectContactsFromSearchLogic extends CommonSearchLogic {
  SelectContactsFromSearchLogic({ContactSearchSource? source})
      : source = source ?? ContactSearchSource();
  final ContactSearchSource source;
  final selectContactsLogic = Get.find<SelectContactsLogic>();
  final resultList = <dynamic>{}.obs;
  int _generation = 0;
  bool _closed = false;
  String _inputKey = '';

  @override
  void onInit() {
    super.onInit();
    searchCtrl.addListener(_queryChanged);
  }

  void _queryChanged() {
    final key = searchKey;
    if (key == _inputKey) return;
    _inputKey = key;
    clearList();
  }

  @override
  void onClose() {
    _closed = true;
    ++_generation;
    searchCtrl.removeListener(_queryChanged);
    super.onClose();
  }

  bool get isSearchNotResult =>
      searchCtrl.text.trim().isNotEmpty && resultList.isEmpty;

  @override
  void clearList() {
    ++_generation;
    resultList.clear();
  }

  Future<void> search() async {
    if (_closed || searchKey.isEmpty) return;
    final generation = ++_generation;
    final keyword = searchKey;
    final account = OpenIM.iMManager.userID;
    final token = DataSp.chatToken;
    bool active() =>
        !_closed &&
        generation == _generation &&
        keyword == searchKey &&
        account == OpenIM.iMManager.userID &&
        token == DataSp.chatToken &&
        !selectContactsLogic.isClosed;
    try {
      final result = await LoadingView.singleton.wrap(
          asyncFunction: () => active()
              ? Future.wait([
                  searchFriend(),
                  if (!selectContactsLogic.hiddenGroup) searchGroup(),
                ])
              : Future.value(<List<dynamic>>[]));
      if (!active()) return;
      final friendList = (result[0] as List<FriendInfo>)
          .where(selectContactsLogic.isVisible)
          .toList();
      resultList.assignAll({...friendList});
      if (selectContactsLogic.action == SelAction.addMember) {
        var memberInfoList =
            await getMemberInfo(friendList.map((e) => e.userID!).toList());
        if (!active()) return;
        for (var element in memberInfoList) {
          selectContactsLogic.defaultCheckedIDList.add(element.userID!);
        }
      }
      if (result.length == 2) {
        final groupList = result[1] as List<GroupInfo>;
        resultList.addAll(groupList);
      }
    } catch (error) {
      if (active() &&
          !handleSessionAuthFailure(error, account: account, token: token)) {
        IMViews.showToast(error.toString());
      }
    }
  }

  @override
  Future<List<FriendInfo>> searchFriend() => source.friends(searchKey);

  Future<List<GroupMembersInfo>> getMemberInfo(List<String> uidList) async {
    return await OpenIM.iMManager.groupManager.getGroupMembersInfo(
        groupID: selectContactsLogic.groupID!, userIDList: uidList);
  }
}
