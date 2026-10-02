import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_profile_panel/group_profile_panel_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';
import 'package:sprintf/sprintf.dart';

enum SearchType {
  user,
  group,
}

class AddContactsBySearchLogic extends GetxController {
  final refreshCtrl = RefreshController();
  final searchCtrl = TextEditingController();
  final focusNode = FocusNode();
  final userInfoList = <UserFullInfo>[].obs;
  final groupInfoList = <GroupInfo>[].obs;
  late SearchType searchType;
  int pageNo = 0;
  final _entryFields = <String, Map<String, String>>{};
  final _addSources = <String, FriendAddSource>{};

  @override
  void onClose() {
    searchCtrl.dispose();
    focusNode.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    searchType = Get.arguments['searchType'] ?? SearchType.user;
    searchCtrl.addListener(() {
      if (searchKey.isEmpty) {
        focusNode.requestFocus();
        userInfoList.clear();
        groupInfoList.clear();
      }
    });
    super.onInit();
  }

  bool get isSearchUser => searchType == SearchType.user;

  String get searchKey => searchCtrl.text.trim();

  bool get isNotFoundUser => userInfoList.isEmpty && searchKey.isNotEmpty;

  bool get isNotFoundGroup => groupInfoList.isEmpty && searchKey.isNotEmpty;

  void search() {
    if (searchKey.isEmpty) return;
    final invite = parseFriendInvite(searchKey);
    if (isSearchUser && invite != null) {
      AppNavigator.startUserProfilePane(
          userID: invite['userID']!,
          addSource: invite['source'] == 'link'
              ? FriendAddSource.link
              : FriendAddSource.qrcode,
          friendAddFields: {'inviteCode': invite['inviteCode']!});
      return;
    }
    if (isSearchUser) {
      searchUser();
    } else {
      searchGroup();
    }
  }

  void searchUser() async {
    final keyword = searchKey;
    var list = await LoadingView.singleton.wrap(
      asyncFunction: () => Apis.searchUserFullInfo(
        content: keyword,
        way: keyword.contains('@') && !keyword.startsWith('@')
            ? 3
            : RegExp(r'^\+?\d+$').hasMatch(keyword)
                ? 2
                : null,
        pageNumber: pageNo = 1,
        showNumber: 20,
      ),
    );
    _addSources.clear();
    for (final user in list ?? <UserFullInfo>[]) {
      if (user.userID != null) {
        final source = friendSearchSource(keyword, user);
        _addSources[user.userID!] = source;
        _entryFields[user.userID!] = {
          if (source == FriendAddSource.account) 'account': user.account ?? '',
          if (source == FriendAddSource.phone) ...{
            'phoneNumber': user.phoneNumber ?? keyword,
            'areaCode': user.areaCode ?? '',
          },
          if (source == FriendAddSource.email) 'email': user.email ?? keyword,
        };
      }
    }
    userInfoList.assignAll(list ?? []);
    refreshCtrl.refreshCompleted();
    if (null == list || list.isEmpty || list.length < 20) {
      refreshCtrl.loadNoData();
    } else {
      refreshCtrl.loadComplete();
    }
  }

  void loadMoreUser() async {
    final keyword = searchKey;
    var list = await LoadingView.singleton.wrap(
      asyncFunction: () => Apis.searchUserFullInfo(
        content: keyword,
        way: keyword.contains('@') && !keyword.startsWith('@')
            ? 3
            : RegExp(r'^\+?\d+$').hasMatch(keyword)
                ? 2
                : null,
        pageNumber: ++pageNo,
        showNumber: 20,
      ),
    );
    for (final user in list ?? <UserFullInfo>[]) {
      if (user.userID != null) {
        final source = friendSearchSource(keyword, user);
        _addSources[user.userID!] = source;
        _entryFields[user.userID!] = {
          if (source == FriendAddSource.account) 'account': user.account ?? '',
          if (source == FriendAddSource.phone) ...{
            'phoneNumber': user.phoneNumber ?? keyword,
            'areaCode': user.areaCode ?? '',
          },
          if (source == FriendAddSource.email) 'email': user.email ?? keyword,
        };
      }
    }
    userInfoList.addAll(list ?? []);
    refreshCtrl.refreshCompleted();
    if (null == list || list.isEmpty || list.length < 20) {
      refreshCtrl.loadNoData();
    } else {
      refreshCtrl.loadComplete();
    }
  }

  void searchGroup() async {
    var list = await OpenIM.iMManager.groupManager.getGroupsInfo(
      groupIDList: [searchKey],
    );
    groupInfoList.assignAll(list);
  }

  String getMatchContent(UserFullInfo userInfo) {
    return sprintf(StrRes.searchNicknameIs, [userInfo.nickname]);
  }

  String? getShowName(dynamic info) {
    if (info is UserFullInfo) {
      return info.nickname;
    } else if (info is GroupInfo) {
      return info.groupName;
    }
    return null;
  }

  void viewInfo(dynamic info) async {
    if (info is UserFullInfo) {
      final fields = Map<String, String>.from(_entryFields[info.userID] ?? {});
      if (_addSources[info.userID] == FriendAddSource.phone &&
          fields['areaCode']?.isNotEmpty != true) {
        final controller = TextEditingController(text: '+86');
        final code = await Get.dialog<String>(AlertDialog(
            title: const Text('确认手机号区号'),
            content: TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(hintText: '例如 +86，需与对方资料一致')),
            actions: [
              TextButton(onPressed: () => Get.back(), child: const Text('取消')),
              TextButton(
                  onPressed: () => Get.back(result: controller.text.trim()),
                  child: const Text('确定'))
            ]));
        controller.dispose();
        if (isClosed || code == null || !RegExp(r'^\+\d{1,4}$').hasMatch(code))
          return;
        fields['areaCode'] = code;
      }
      AppNavigator.startUserProfilePane(
        userID: info.userID!,
        addSource: _addSources[info.userID] ?? FriendAddSource.search,
        friendAddFields: fields,
        nickname: info.nickname,
        faceURL: info.faceURL,
      );
    } else if (info is GroupInfo) {
      AppNavigator.startGroupProfilePanel(
        groupID: info.groupID,
        joinGroupMethod: JoinGroupMethod.search,
      );
    }
  }

  String getShowTitle(info) {
    if (!isSearchUser) {
      return sprintf(StrRes.searchGroupNicknameIs, [getShowName(info)]);
    }

    final user = info as UserFullInfo;
    final source = _addSources[user.userID];
    final fields = _entryFields[user.userID] ?? const <String, String>{};
    return switch (source) {
      FriendAddSource.account => '公开账号:${user.account ?? user.nickname ?? ""}',
      FriendAddSource.phone => '手机号:${fields['phoneNumber'] ?? ""}',
      FriendAddSource.email => '邮箱:${fields['email'] ?? ""}',
      _ => user.nickname ?? '',
    };
  }
}
