import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_profile_panel/group_profile_panel_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';
import 'package:sprintf/sprintf.dart';
import '../../../core/session/session_request_errors.dart';
import '../search/contact_search_source.dart';

enum SearchType {
  user,
  group,
}

class AddContactsBySearchLogic extends GetxController {
  AddContactsBySearchLogic({ContactSearchSource? source})
      : source = source ?? ContactSearchSource();
  final ContactSearchSource source;
  final refreshCtrl = RefreshController();
  final searchCtrl = TextEditingController();
  final focusNode = FocusNode();
  final userInfoList = <UserFullInfo>[].obs;
  final groupInfoList = <GroupInfo>[].obs;
  late SearchType searchType;
  int pageNo = 0;
  final _entryFields = <String, Map<String, String>>{};
  final _addSources = <String, FriendAddSource>{};
  int _generation = 0;
  bool _closed = false;
  bool _loadingMore = false;

  @override
  void onClose() {
    _closed = true;
    ++_generation;
    searchCtrl.removeListener(_queryChanged);
    refreshCtrl.dispose();
    searchCtrl.dispose();
    focusNode.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    searchType = Get.arguments['searchType'] ?? SearchType.user;
    searchCtrl.addListener(_queryChanged);
    super.onInit();
  }

  String _inputKey = '';
  void _queryChanged() {
    final key = searchKey;
    if (key == _inputKey) return;
    _inputKey = key;
    ++_generation;
    pageNo = 0;
    _loadingMore = false;
    userInfoList.clear();
    groupInfoList.clear();
    _entryFields.clear();
    _addSources.clear();
    if (key.isEmpty) focusNode.requestFocus();
  }

  bool _active(int generation, String keyword, String account, String? token) =>
      !_closed &&
      generation == _generation &&
      keyword == searchKey &&
      account == OpenIM.iMManager.userID &&
      token == DataSp.chatToken;

  bool get isSearchUser => searchType == SearchType.user;

  String get searchKey => searchCtrl.text.trim();

  bool get isNotFoundUser => userInfoList.isEmpty && searchKey.isNotEmpty;

  bool get isNotFoundGroup => groupInfoList.isEmpty && searchKey.isNotEmpty;

  void search() {
    if (_closed || searchKey.isEmpty) return;
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

  Future<void> searchUser() => _queryUsers(false);
  Future<void> loadMoreUser() => _queryUsers(true);

  Future<void> _queryUsers(bool append) async {
    if (_closed ||
        searchKey.isEmpty ||
        append && (_loadingMore || pageNo == 0)) {
      return;
    }
    final keyword = searchKey;
    final generation = append ? _generation : ++_generation;
    final account = OpenIM.iMManager.userID;
    final token = DataSp.chatToken;
    final page = append ? pageNo + 1 : 1;
    if (append) {
      _loadingMore = true;
    } else {
      pageNo = 0;
    }
    try {
      final list = await LoadingView.singleton.wrap(
          asyncFunction: () => _active(generation, keyword, account, token)
              ? source.users(keyword, page)
              : Future.value(<UserFullInfo>[]));
      if (!_active(generation, keyword, account, token)) return;
      if (!append) {
        _entryFields.clear();
        _addSources.clear();
      }
      _rememberSources(keyword, list ?? []);
      if (append) {
        final known = userInfoList.map((user) => user.userID).toSet();
        userInfoList
            .addAll((list ?? []).where((user) => known.add(user.userID)));
      } else {
        userInfoList.value = list ?? [];
      }
      pageNo = page;
      refreshCtrl.refreshCompleted();
      if (list == null || list.length < 20) {
        refreshCtrl.loadNoData();
      } else {
        refreshCtrl.loadComplete();
      }
    } catch (error) {
      if (_active(generation, keyword, account, token)) {
        refreshCtrl.loadFailed();
        if (!handleSessionAuthFailure(error, account: account, token: token)) {
          IMViews.showToast(error.toString());
        }
      }
    } finally {
      if (generation == _generation) _loadingMore = false;
    }
  }

  void _rememberSources(String keyword, List<UserFullInfo> list) {
    for (final user in list) {
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
  }

  Future<void> searchGroup() async {
    if (_closed || searchKey.isEmpty) return;
    final keyword = searchKey;
    final generation = ++_generation;
    final account = OpenIM.iMManager.userID;
    final token = DataSp.chatToken;
    try {
      final list = await source.groups(keyword);
      if (_active(generation, keyword, account, token))
        groupInfoList.value = list;
    } catch (error) {
      if (_active(generation, keyword, account, token)) {
        IMViews.showToast(error.toString());
      }
    }
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
