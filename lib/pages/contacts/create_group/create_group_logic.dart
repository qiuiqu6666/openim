import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/core/user_activity/activity_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../../routes/app_navigator.dart';
import '../../conversation/conversation_logic.dart';
import '../select_contacts/select_contacts_logic.dart';
import '../select_contacts/selection/contact_selection_policy.dart';
import 'create_group_default_name.dart';

class CreateGroupLogic extends GetxController {
  final conversationLogic = Get.find<ConversationLogic>();
  final nameCtrl = TextEditingController();
  final checkedList = <UserInfo>[];
  final defaultCheckedList = <UserInfo>[];
  final allList = <UserInfo>[].obs;
  final faceURL = ''.obs;

  @override
  void onInit() {
    defaultCheckedList.addAll(Get.arguments['defaultCheckedList']);
    checkedList.addAll(Get.arguments['checkedList']);
    allList.addAll(defaultCheckedList);
    allList.addAll(checkedList);
    _removeUnavailableMembers();
    super.onInit();
  }

  void _removeUnavailableMembers() {
    bool unavailable(UserInfo member) =>
        !ContactSelectionPolicy.allowsGroupMember(member);
    defaultCheckedList.removeWhere(unavailable);
    checkedList.removeWhere(unavailable);
    allList.removeWhere(unavailable);
  }

  String get groupName {
    final name = nameCtrl.text.trim();
    return name.isNotEmpty ? name : defaultGroupName;
  }

  String get defaultGroupName => defaultCreateGroupName(allList.toList());

  Future<void> completeCreation() async {
    _removeUnavailableMembers();
    if (allList.length > 1) {
      var info = await LoadingView.singleton.wrap(
        asyncFunction: () => observeUserActivity(
            'group_create',
            () => OpenIM.iMManager.groupManager.createGroup(
                  groupInfo: GroupInfo(
                    groupID: '',
                    groupName: groupName,
                    faceURL: faceURL.value,
                    groupType: GroupType.work,
                  ),
                  memberUserIDs: allList
                      .where((e) => e.userID != OpenIM.iMManager.userID)
                      .map((e) => e.userID!)
                      .toList(),
                )),
      );
      conversationLogic.toChat(
        offUntilHome: true,
        groupID: info.groupID,
        nickname: groupName,
        faceURL: faceURL.value,
        sessionType: info.sessionType,
      );
    } else {
      conversationLogic.toChat(
        offUntilHome: true,
        userID: checkedList.firstOrNull?.userID,
        nickname: checkedList.firstOrNull?.nickname,
        faceURL: checkedList.firstOrNull?.faceURL,
        sessionType: ConversationType.single,
      );
    }
  }

  void selectAvatar() {
    IMViews.openPhotoSheet(onData: (path, url) {
      if (url != null) faceURL.value = url;
    });
  }

  int length() {
    return (allList.length + 2) > 10 ? 10 : (allList.length + 2);
  }

  Widget itemBuilder({
    required int index,
    required Widget Function(UserInfo info) builder,
    required Widget Function() addButton,
    required Widget Function() delButton,
  }) {
    if (allList.length > 8) {
      if (index < 8) {
        var info = allList.elementAt(index);
        return builder(info);
      } else if (index == 8) {
        return addButton();
      } else {
        return delButton();
      }
    } else {
      if (index < allList.length) {
        var info = allList.elementAt(index);
        return builder(info);
      } else if (index == allList.length) {
        return addButton();
      } else {
        return delButton();
      }
    }
  }

  @override
  void onClose() {
    nameCtrl.dispose();
    super.onClose();
  }

  void opMember({bool isDel = false}) async {
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.addMember,
      checkedList: checkedList,
      defaultCheckedIDList: defaultCheckedList.map((e) => e.userID!).toList(),
      openSelectedSheet: isDel,
    );
    final list = IMUtils.convertSelectContactsResultToUserInfo(result);
    if (list is List<UserInfo>) {
      checkedList
        ..clear()
        ..addAll(list.where(ContactSelectionPolicy.allowsGroupMember));
      allList
        ..assignAll(defaultCheckedList)
        ..addAll(checkedList);
    }
  }
}
