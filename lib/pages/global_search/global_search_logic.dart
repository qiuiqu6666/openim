import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../conversation/conversation_logic.dart';

class GlobalSearchSource {
  Future<List<FriendInfo>> friends(String query) async =>
      OpenIM.iMManager.friendshipManager.searchFriends(
          keywordList: [query],
          isSearchUserID: true,
          isSearchNickname: true,
          isSearchRemark: true);
  Future<List<GroupInfo>> groups(String query) =>
      OpenIM.iMManager.groupManager.searchGroups(
          keywordList: [query], isSearchGroupName: true, isSearchGroupID: true);
  Future<List<ConversationInfo>> conversations(String query) async {
    final key = query.toLowerCase();
    return Get.find<ConversationLogic>()
        .list
        .where((item) => [item.showName, item.userID, item.groupID]
            .any((value) => value?.toLowerCase().contains(key) == true))
        .toList();
  }

  Future<List<SearchResultItems>> messages(String query, bool files) async {
    final result = await OpenIM.iMManager.messageManager.searchLocalMessages(
      keywordList: [query],
      messageTypeList:
          files ? [MessageType.file] : [MessageType.text, MessageType.atText],
    );
    return result.searchResultItems ?? [];
  }
}

class GlobalSearchLogic extends GetxController {
  GlobalSearchLogic({GlobalSearchSource? source})
      : source = source ?? GlobalSearchSource();
  final GlobalSearchSource source;
  final searchCtrl = TextEditingController();
  final focusNode = FocusNode();
  final contactsList = <FriendInfo>[].obs;
  final groupList = <GroupInfo>[].obs;
  final conversations = <ConversationInfo>[].obs;
  final textSearchResultItems = <SearchResultItems>[].obs;
  final fileSearchResultItems = <SearchResultItems>[].obs;
  final failures = <int>{}.obs;
  final loading = false.obs;
  final query = ''.obs;
  final index = 0.obs;
  Timer? _debounce;
  int _generation = 0;
  bool _closed = false;

  @override
  void onInit() {
    super.onInit();
    searchCtrl.addListener(_inputChanged);
  }

  void _inputChanged() {
    final value = searchCtrl.text.trim();
    if (value == query.value) return;
    _debounce?.cancel();
    ++_generation;
    query.value = value;
    clearList();
    loading.value = value.isNotEmpty;
    if (value.isNotEmpty)
      _debounce = Timer(const Duration(milliseconds: 300), search);
  }

  void clearList() {
    contactsList.clear();
    groupList.clear();
    conversations.clear();
    textSearchResultItems.clear();
    fileSearchResultItems.clear();
    failures.clear();
  }

  Future<void> search() async {
    _debounce?.cancel();
    final key = searchCtrl.text.trim();
    final version = ++_generation;
    query.value = key;
    clearList();
    loading.value = key.isNotEmpty;
    if (key.isEmpty) return;
    bool active() => !_closed && version == _generation;
    Future<void> section<T>(
        int id, Future<List<T>> Function() fetch, RxList<T> output) async {
      try {
        final results = await fetch();
        if (active()) output.assignAll(results);
      } catch (_) {
        if (active()) failures.add(id);
      }
    }

    await Future.wait([
      section(1, () => source.friends(key), contactsList),
      section(2, () => source.groups(key), groupList),
      section(3, () => source.conversations(key), conversations),
      section(4, () => source.messages(key, false), textSearchResultItems),
      section(5, () => source.messages(key, true), fileSearchResultItems),
    ]);
    if (active()) loading.value = false;
  }

  @override
  void onClose() {
    _closed = true;
    ++_generation;
    _debounce?.cancel();
    searchCtrl.removeListener(_inputChanged);
    searchCtrl.dispose();
    focusNode.dispose();
    super.onClose();
  }
}

abstract class CommonSearchLogic extends GetxController {
  final searchCtrl = TextEditingController();
  final focusNode = FocusNode();

  void clearList();

  @override
  void onInit() {
    searchCtrl.addListener(_clearInput);
    super.onInit();
  }

  @override
  void onClose() {
    focusNode.dispose();
    searchCtrl.dispose();
    super.onClose();
  }

  _clearInput() {
    if (searchKey.isEmpty) {
      clearList();
    }
  }

  String get searchKey => searchCtrl.text.trim();

  Future<List<FriendInfo>> searchFriend() =>
      Apis.searchFriendInfo(searchCtrl.text.trim()).then(
          (list) => list.map((e) => FriendInfo.fromJson(e.toJson())).toList());

  Future<List<GroupInfo>> searchGroup() =>
      OpenIM.iMManager.groupManager.searchGroups(
          keywordList: [searchCtrl.text.trim()],
          isSearchGroupName: true,
          isSearchGroupID: true);

  Future<SearchResult> searchTextMessage({
    int pageIndex = 1,
    int count = 20,
  }) =>
      OpenIM.iMManager.messageManager.searchLocalMessages(
        keywordList: [searchKey],
        messageTypeList: [MessageType.text, MessageType.atText],
        pageIndex: pageIndex,
        count: count,
      );

  Future<SearchResult> searchFileMessage({
    int pageIndex = 1,
    int count = 20,
  }) =>
      OpenIM.iMManager.messageManager.searchLocalMessages(
        keywordList: [searchKey],
        messageTypeList: [MessageType.file],
        pageIndex: pageIndex,
        count: count,
      );

  String? parseID(e) {
    if (e is ConversationInfo) {
      return e.isSingleChat ? e.userID : e.groupID;
    } else if (e is GroupInfo) {
      return e.groupID;
    } else if (e is UserInfo) {
      return e.userID;
    } else if (e is FriendInfo) {
      return e.userID;
    } else {
      return null;
    }
  }

  String? parseNickname(e) {
    if (e is ConversationInfo) {
      return e.showName;
    } else if (e is GroupInfo) {
      return e.groupName;
    } else if (e is UserInfo) {
      return e.nickname;
    } else if (e is FriendInfo) {
      return e.nickname;
    } else {
      return null;
    }
  }

  String? parseFaceURL(e) {
    if (e is ConversationInfo) {
      return e.faceURL;
    } else if (e is GroupInfo) {
      return e.faceURL;
    } else if (e is UserInfo) {
      return e.faceURL;
    } else if (e is FriendInfo) {
      return e.faceURL;
    } else {
      return null;
    }
  }
}
