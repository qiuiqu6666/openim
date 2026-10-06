import 'package:azlistview/azlistview.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:openim/pages/contacts/friend_list/friend_list_logic.dart';
import 'package:openim_common/openim_common.dart';

import '../select_contacts_logic.dart';
import '../../contacts_logic.dart';

class SelectContactsFromFriendsLogic extends FriendListLogic {
  final selectContactsLogic = Get.find<SelectContactsLogic>();
  final searchController = TextEditingController();
  final searchQuery = ''.obs;

  void searchFriends(String value) =>
      searchQuery.value = value.trim().toLowerCase();

  List<ISUserInfo> get visibleFriends {
    final query = searchQuery.value;
    final available = friendList.where(selectContactsLogic.isVisible).toList();
    if (query.isEmpty && available.length == friendList.length) {
      return available;
    }
    final filtered = available
        .where((friend) =>
            query.isEmpty ||
            [
              friend.showName,
              friend.nickname,
              friend.remark,
              friend.userID,
              friend.namePinyin
            ].any((value) => value?.toLowerCase().contains(query) == true))
        .map((friend) => ISUserInfo.fromJson(friend.toJson()))
        .toList();
    // A search can begin with a formerly non-leading row in its letter group.
    // Reserve the header on the projection without changing SDK source flags.
    SuspensionUtil.setShowSuspensionStatus(filtered);
    return filtered;
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    if (selectContactsLogic.action == SelAction.carte &&
        Get.isRegistered<ContactsLogic>()) {
      final contacts = Get.find<ContactsLogic>();
      if (contacts.isCurrentSession) {
        friendList.assignAll(contacts.friends
            .map((friend) => ISUserInfo.fromJson(friend.toJson())));
      }
    }
    super.onInit();
  }

  @override
  void onUserIDList(List<String> userIDList) {
    selectContactsLogic.updateDefaultCheckedList(
        userIDList.where(selectContactsLogic.allowsUserID).toList());
    super.onUserIDList(userIDList);
  }

  bool get isSelectAll {
    if (selectContactsLogic.checkedList.isEmpty || operableList.isEmpty) {
      return false;
    } else if (operableList
        .every((item) => selectContactsLogic.isChecked(item))) {
      return true;
    } else {
      return false;
    }
  }

  Iterable<ISUserInfo> get operableList => visibleFriends.where(_remove);

  bool _remove(ISUserInfo info) =>
      selectContactsLogic.allowsSelection(info) &&
      !selectContactsLogic.isDefaultChecked(info);

  void selectAll() {
    if (isSelectAll) {
      for (var info in operableList) {
        selectContactsLogic.removeItem(info);
      }
    } else {
      for (var info in operableList) {
        final isChecked = selectContactsLogic.isChecked(info);
        if (!isChecked) {
          selectContactsLogic.toggleChecked(info);
        }
      }
    }
  }
}
