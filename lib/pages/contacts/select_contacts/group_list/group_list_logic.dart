import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';

import '../select_contacts_logic.dart';

class SelectContactsFromGroupLogic extends GetxController {
  final selectContactsLogic = Get.find<SelectContactsLogic>();
  final allList = <GroupInfo>[].obs;
  final loading = true.obs;
  final loadFailed = false.obs;

  @override
  void onReady() {
    loadGroups();
    super.onReady();
  }

  Future<void> loadGroups() async {
    loading.value = true;
    loadFailed.value = false;
    try {
      final list = await OpenIM.iMManager.groupManager.getJoinedGroupList();
      if (isClosed) return;
      allList.assignAll(list);
    } catch (_) {
      if (!isClosed) loadFailed.value = true;
    } finally {
      if (!isClosed) loading.value = false;
    }
  }

  Iterable<GroupInfo> get operableList => allList.where(_remove);

  bool _remove(GroupInfo info) => !selectContactsLogic.isDefaultChecked(info);

  bool get isSelectAll {
    if (selectContactsLogic.checkedList.isEmpty) {
      return false;
    } else if (operableList
        .every((item) => selectContactsLogic.isChecked(item))) {
      return true;
    } else {
      return false;
    }
  }

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
