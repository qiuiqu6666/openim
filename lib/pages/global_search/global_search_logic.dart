import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../conversation/conversation_logic.dart';
import '../group_features/data/group_feature_store.dart';
import 'cloud/global_history_cloud_search.dart';
import 'cloud/global_keyword_search_api.dart';
import '../chat/history_search/cloud/chat_keyword_search_api.dart';

class GlobalSearchSource {
  Iterable<ConversationInfo> get currentConversations =>
      Get.isRegistered<ConversationLogic>()
          ? Get.find<ConversationLogic>().list
          : const <ConversationInfo>[];

  GroupFeatureStore? get groupFeatures => Get.isRegistered<ConversationLogic>()
      ? Get.find<ConversationLogic>().groupFeatures
      : null;

  /// Reuses the home owner's projection without another SDK listener.
  Stream<List<ConversationInfo>>? get conversationUpdates =>
      Get.isRegistered<ConversationLogic>()
          ? Get.find<ConversationLogic>().list.stream
          : null;

  static List<ConversationInfo> matchConversations(
      Iterable<ConversationInfo> items, String query) {
    final key = query.toLowerCase();
    return items
        .where((item) => [item.showName, item.userID, item.groupID]
            .any((value) => value?.toLowerCase().contains(key) == true))
        .toList();
  }

  Future<List<FriendInfo>> friends(String query) async =>
      OpenIM.iMManager.friendshipManager.searchFriends(
          keywordList: [query],
          isSearchUserID: true,
          isSearchNickname: true,
          isSearchRemark: true);
  Future<List<GroupInfo>> groups(String query) async {
    final store = groupFeatures;
    final groups = await OpenIM.iMManager.groupManager.searchGroups(
        keywordList: [query], isSearchGroupName: true, isSearchGroupID: true);
    for (final group in groups) {
      store?.seed(group);
    }
    return groups;
  }

  Future<List<ConversationInfo>> conversations(String query) async {
    return matchConversations(Get.find<ConversationLogic>().list, query);
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
  GlobalSearchLogic(
      {GlobalSearchSource? source,
      GlobalKeywordSearchApi? keywordApi,
      GlobalHistoryCloudSearch Function()? cloudFactory})
      : source = source ?? GlobalSearchSource(),
        _globalApi = keywordApi ??
            (source == null && cloudFactory == null
                ? GlobalKeywordSearchApi()
                : null),
        _cloudFactory = cloudFactory;
  final GlobalKeywordSearchApi? _globalApi;
  bool get invalidKeyword =>
      _globalApi != null &&
      (query.value.runes.length < 2 || query.value.runes.length > 64);
  final cloudHits = <CloudKeywordMessage>[].obs;
  String _globalCursor = '';
  final searchError = Rxn<int>();
  final GlobalHistoryCloudSearch Function()? _cloudFactory;
  GlobalHistoryCloudSearch? _cloud;
  final cloudLoading = false.obs;
  final cloudHasMore = false.obs;
  String? _searchAccount, _searchToken;
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
  final index = 1.obs;
  Timer? _debounce;
  Timer? _conversationTimer;
  List<ConversationInfo>? _latestConversations;
  StreamSubscription<List<ConversationInfo>>? _conversationSubscription;
  int _conversationRevision = 0;
  int _generation = 0;
  bool _closed = false;

  @override
  void onInit() {
    super.onInit();
    searchCtrl.addListener(_inputChanged);
    _conversationSubscription =
        source.conversationUpdates?.listen(_conversationsChanged);
  }

  void _conversationsChanged(List<ConversationInfo> items) {
    if (_closed) return;
    ++_conversationRevision;
    if (query.value.isEmpty) return;
    _latestConversations = items;
    _conversationTimer ??= Timer(const Duration(milliseconds: 80), () {
      _conversationTimer = null;
      final latest = _latestConversations;
      _latestConversations = null;
      if (_closed || query.value.isEmpty || latest == null) return;
      conversations.assignAll(
          GlobalSearchSource.matchConversations(latest, query.value));
      failures.remove(3);
    });
  }

  void _inputChanged() {
    final value = searchCtrl.text.trim();
    if (value == query.value) return;
    _debounce?.cancel();
    ++_generation;
    query.value = value;
    clearList();
    loading.value = value.isNotEmpty;
    if (value.isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 300), search);
    }
  }

  void clearList() {
    cloudHits.clear();
    _globalCursor = '';
    searchError.value = null;
    _cloud = null;
    cloudLoading.value = false;
    cloudHasMore.value = false;
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
    final conversationRevision = _conversationRevision;
    query.value = key;
    clearList();
    loading.value = key.isNotEmpty;
    if (key.isEmpty) return;
    if (_cloudFactory != null) {
      _searchAccount = OpenIM.iMManager.userID;
      _searchToken = OpenIM.iMManager.token;
    }
    _cloud = _cloudFactory?.call();
    cloudHasMore.value = _globalApi != null || (_cloud?.hasMore ?? false);
    bool active() => !_closed && version == _generation;
    Future<void> section<T>(
        int id, Future<List<T>> Function() fetch, RxList<T> output) async {
      bool applicable() =>
          active() &&
          (id != 3 || conversationRevision == _conversationRevision);
      try {
        final results = await fetch();
        if (applicable()) output.assignAll(results);
      } catch (_) {
        if (applicable()) failures.add(id);
      }
    }

    await Future.wait([
      section(1, () => source.friends(key), contactsList),
      section(2, () => source.groups(key), groupList),
      section(3, () => source.conversations(key), conversations),
      if (_globalApi == null)
        section(4, () => source.messages(key, false), textSearchResultItems)
      else
        _loadGlobal(),
    ]);
    if (active()) loading.value = false;
    if (active() && _globalApi == null) await loadMoreCloud();
  }

  Future<void> loadMoreCloud() async {
    if (_globalApi != null) return _loadGlobal();
    final cloud = _cloud;
    if (_closed || cloud == null || !cloud.hasMore || cloudLoading.value) {
      return;
    }
    final generation = _generation;
    final keyword = query.value;
    bool current() =>
        !_closed &&
        generation == _generation &&
        identical(_cloud, cloud) &&
        _searchAccount == OpenIM.iMManager.userID &&
        _searchToken == OpenIM.iMManager.token;
    if (!current()) return;
    cloudLoading.value = true;
    failures.remove(4);
    // Publish fast conversations without waiting for the slowest history page.
    // Serialize local searches so an older snapshot cannot replace a newer one.
    Future<void> refresh = Future<void>.value();
    Future<void> publish() {
      refresh = refresh.then((_) async {
        if (!current()) return;
        final results = await source.messages(keyword, false);
        if (current()) textSearchResultItems.assignAll(results);
      });
      return refresh;
    }

    try {
      // One interaction is one bounded batch, even if no new matches appear.
      // Older history remains explicitly available through the next load-more.
      await cloud.supplement(current, onProgress: publish);
    } catch (_) {
      if (current()) failures.add(4);
    } finally {
      if (current()) {
        cloudHasMore.value = cloud.hasMore;
        cloudLoading.value = false;
      }
    }
  }

  Future<void> _loadGlobal() async {
    if (_closed || cloudLoading.value || !cloudHasMore.value) return;
    final generation = _generation;
    final keyword = query.value;
    bool current() => !_closed && generation == _generation;
    cloudLoading.value = true;
    failures.remove(4);
    searchError.value = null;
    var cursor = _globalCursor;
    final seenCursors = <String>{cursor};
    try {
      while (current()) {
        final page =
            await _globalApi!.search(keyword, cursor, isCurrent: current);
        if (!current()) return;
        if (page.hasMore && !seenCursors.add(page.cursor)) {
          throw const FormatException('Repeated cursor');
        }
        cursor = page.cursor;
        if (page.items.isEmpty && page.hasMore) continue;
        final ids =
            cloudHits.map((m) => '${m.conversationID}:${m.seq}').toSet();
        cloudHits.addAll(
            page.items.where((m) => ids.add('${m.conversationID}:${m.seq}')));
        _globalCursor = cursor;
        cloudHasMore.value = page.hasMore;
        break;
      }
    } on SearchApiException catch (error) {
      if (current()) {
        searchError.value = error.code;
        if (error.code == 1001) {
          _globalCursor = '';
          cloudHits.clear();
        }
        if (error.invalidatesContext) cloudHits.clear();
        failures.add(4);
      }
    } catch (_) {
      if (current()) failures.add(4);
    } finally {
      if (current()) cloudLoading.value = false;
    }
  }

  @override
  void onClose() {
    _closed = true;
    _conversationTimer?.cancel();
    _latestConversations = null;
    ++_generation;
    _debounce?.cancel();
    final subscription = _conversationSubscription;
    _conversationSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
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

  void _clearInput() {
    if (searchKey.isEmpty) {
      clearList();
    }
  }

  String get searchKey => graphemeTrim(searchCtrl.text);

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

  String? parseID(Object? e) {
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

  String? parseNickname(Object? e) {
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

  String? parseFaceURL(Object? e) {
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
