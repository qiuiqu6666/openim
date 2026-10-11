import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';

import '../select_contacts_logic.dart';

class SelectContactsFromGroupLogic extends GetxController {
  SelectContactsFromGroupLogic({
    SelectContactsLogic? selection,
    Future<List<GroupInfo>> Function()? loadGroups,
  })  : selectContactsLogic = selection ?? Get.find<SelectContactsLogic>(),
        _loadGroups =
            loadGroups ?? OpenIM.iMManager.groupManager.getJoinedGroupList;

  final SelectContactsLogic selectContactsLogic;
  final Future<List<GroupInfo>> Function() _loadGroups;
  final allList = <GroupInfo>[].obs;
  final searchController = TextEditingController();
  final searchQuery = ''.obs;
  final loading = true.obs;
  final loadFailed = false.obs;
  int _generation = 0;

  List<GroupInfo> get visibleGroups => allList
      .where((group) => '${group.groupName ?? ''} ${group.groupID}'
          .toLowerCase()
          .contains(searchQuery.value))
      .toList(growable: false);

  void searchGroups(String query) =>
      searchQuery.value = query.trim().toLowerCase();

  @override
  void onClose() {
    ++_generation;
    searchController.dispose();
    super.onClose();
  }

  @override
  void onReady() {
    loadGroups();
    super.onReady();
  }

  Future<void> loadGroups() async {
    if (!selectContactsLogic.selectionCurrent) return;
    final generation = ++_generation;
    loading.value = true;
    loadFailed.value = false;
    try {
      final list = await _loadGroups();
      if (isClosed ||
          generation != _generation ||
          !selectContactsLogic.selectionCurrent) {
        return;
      }
      allList.assignAll({
        for (final group in list)
          if (group.groupID.isNotEmpty) group.groupID: group
      }.values);
    } catch (_) {
      if (!isClosed && generation == _generation) loadFailed.value = true;
    } finally {
      if (!isClosed && generation == _generation) loading.value = false;
    }
  }

  Iterable<GroupInfo> get operableList => visibleGroups.where(_remove);

  bool _remove(GroupInfo info) => !selectContactsLogic.isDefaultChecked(info);

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
