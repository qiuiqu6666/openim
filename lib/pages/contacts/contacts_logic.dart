import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_profile_panel/group_profile_panel_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import '../../core/controller/im_controller.dart';
import '../../core/im_callback.dart';
import '../home/home_logic.dart';
import '../mine/settings/pages/qr_profile_page.dart';
import 'select_contacts/select_contacts_logic.dart';
import 'star_friend_store.dart';
import 'presence_store.dart';
import 'directory/contact_directory_indexer.dart';
import 'add_by_search/add_by_search_logic.dart';
import 'scanning/friend_qr_scanner.dart';

class ContactsLogic extends GetxController
    with WidgetsBindingObserver
    implements ViewUserProfileBridge, SelectContactsBridge, ScanBridge {
  ContactsLogic({
    Future<List<FriendInfo>> Function(int offset, int count)? fetchFriendsPage,
    ContactDirectoryIndexer? directoryIndexer,
  })  : _fetchFriendsPage = fetchFriendsPage ??
            ((offset, count) =>
                OpenIM.iMManager.friendshipManager.getFriendListPage(
                  offset: offset,
                  count: count,
                  filterBlack: true,
                )),
        _directoryIndexer = directoryIndexer ?? ContactDirectoryIndexer();

  final Future<List<FriendInfo>> Function(int offset, int count)
      _fetchFriendsPage;
  final ContactDirectoryIndexer _directoryIndexer;
  final _accountID = OpenIM.iMManager.userID;
  final _sessionToken = DataSp.chatToken;
  bool get _inactive =>
      _closed ||
      isClosed ||
      OpenIM.iMManager.userID != _accountID ||
      DataSp.chatToken != _sessionToken;
  bool get isCurrentSession => !_inactive;
  final imLogic = Get.find<IMController>();
  static const _inviteChannel = MethodChannel('openim_friend_invites');

  Future<void> _listenForInvites() async {
    _inviteChannel.setMethodCallHandler((call) async {
      if (_inactive ||
          call.method != 'openInvite' ||
          call.arguments is! String) {
        return false;
      }
      final link = call.arguments as String;
      if (parseFriendInvite(link) == null) return false;
      scanOutUserID(link);
      return true;
    });
    try {
      final pending = await _inviteChannel.invokeMethod<String>('takeInvite');
      if (!_inactive && pending != null && parseFriendInvite(pending) != null) {
        scanOutUserID(pending);
      }
    } on MissingPluginException {
      // Desktop platforms can paste invitations into the search entry.
    }
  }

  final homeLogic = Get.find<HomeLogic>();

  final friendApplicationList = <UserInfo>[];
  final friends = <ISUserInfo>[].obs;
  final friendsLoading = true.obs;
  final stars = StarFriendStore();
  final presence = PresenceStore();
  StreamSubscription<UserStatusInfo>? _presenceSubscription;
  final _presenceIDs = <String>{};
  final _visiblePresenceIDs = <String>{};
  final _profilePresenceIDs = <Object, String>{};
  final _directoryPresenceIDs = <Object, Set<String>>{};
  Timer? _presenceTimer;
  Timer? _presenceStatusTimer;
  final _pendingPresenceStatusIDs = <String>{};
  Future<void> _presenceWork = Future.value();
  bool _foreground = true;

  void setPresenceVisible(String id, bool visible) {
    if (isClosed) return;
    if (visible) {
      _visiblePresenceIDs.add(id);
    } else {
      _visiblePresenceIDs.remove(id);
    }
    _presenceTimer?.cancel();
    _presenceTimer = Timer(
        const Duration(milliseconds: 120), () => refreshPresence(force: false));
  }

  void setProfilePresence(Object owner, String? id) {
    if (id == null) {
      if (_profilePresenceIDs.remove(owner) == null) return;
    } else {
      if (_inactive || _profilePresenceIDs[owner] == id) return;
      _profilePresenceIDs[owner] = id;
    }
    // Changing route ownership does not require re-subscribing the same peer.
    unawaited(refreshPresence(force: false));
  }

  void _onPresenceStatusChanged(UserStatusInfo event) {
    final id = event.userID;
    if (_inactive ||
        !_foreground ||
        id == null ||
        !_presenceIDs.contains(id) ||
        (event.status != 0 && event.status != 1) ||
        presence.users[id]?.hidden == true) {
      return;
    }
    // SDK events signal a change. The presence API supplies the displayable
    // state, real last-seen time and privacy together, without a guessed time
    // being published and then immediately replaced by the server response.
    // Fence old responses immediately, including those arriving before the
    // batched refresh below has started.
    presence.invalidateRefresh(id);
    _pendingPresenceStatusIDs.add(id);
    _presenceStatusTimer ??= Timer(const Duration(milliseconds: 120), () {
      _presenceStatusTimer = null;
      final ids = _pendingPresenceStatusIDs
          .where((id) =>
              _presenceIDs.contains(id) && presence.users[id]?.hidden != true)
          .toList(growable: false);
      _pendingPresenceStatusIDs.clear();
      if (!_inactive && _foreground && ids.isNotEmpty) {
        unawaited(presence.refresh(ids));
      }
    });
  }

  /// A picker owns its visible batch without modifying the main directory.
  /// Empty batches pause a covered picker; null releases only that owner.
  void setDirectoryPresenceVisible(Object owner, Set<String>? userIDs) {
    // A stale picker may still release its ownership while its route closes.
    if (_inactive && userIDs?.isNotEmpty == true) return;
    if (userIDs == null) {
      _directoryPresenceIDs.remove(owner);
    } else {
      _directoryPresenceIDs[owner] = Set<String>.of(userIDs);
    }
    _presenceTimer?.cancel();
    if (_inactive) return;
    _presenceTimer = Timer(
        const Duration(milliseconds: 120), () => refreshPresence(force: false));
  }

  StreamSubscription<String>? _starSubscription;
  StreamSubscription<FriendInfo>? _friendAddedSub;
  StreamSubscription<FriendInfo>? _friendDeletedSub;
  StreamSubscription<FriendInfo>? _friendChangedSub;
  StreamSubscription<dynamic>? _syncSub;
  int _loadGeneration = 0;
  Future<void>? _friendsLoad;
  bool _reloadFriendsPending = false;
  bool _closed = false;
  Timer? _friendChangesTimer;
  final _directory = <String, ISUserInfo>{};
  final _friendChangesDuringLoad = <String, FriendInfo?>{};
  int _directoryRevision = 0;
  Future<void>? _directoryWork;
  bool _directoryDirty = false;

  int get friendApplicationCount =>
      homeLogic.unhandledFriendApplicationCount.value;

  int get groupApplicationCount =>
      homeLogic.unhandledGroupApplicationCount.value;

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    _presenceSubscription =
        imLogic.userStatusChangedSubject.listen(_onPresenceStatusChanged);
    _starSubscription =
        imLogic.customBusinessMessageSubject.listen(stars.handleNotification);
    unawaited(stars.refresh());
    PackageBridge.selectContactsBridge = this;
    PackageBridge.viewUserProfileBridge = this;
    PackageBridge.scanBridge = this;
    _friendAddedSub = imLogic.friendAddSubject.listen(_upsertFriend);
    _friendDeletedSub = imLogic.friendDelSubject.listen(_removeFriend);
    _friendChangedSub = imLogic.friendInfoChangedSubject.listen(_upsertFriend);
    _syncSub = imLogic.imSdkStatusPublishSubject.listen((event) {
      if (event.status == IMSdkStatus.syncEnded) loadFriends();
      if (event.status == IMSdkStatus.syncEnded ||
          event.status == IMSdkStatus.connectionSucceeded) {
        unawaited(stars.refresh());
        unawaited(refreshPresence());
      }
    });

    super.onInit();
  }

  @override
  void onReady() {
    if (_closed) return;
    super.onReady();
    unawaited(_listenForInvites());
    loadFriends();
  }

  /// A picker joins the initial load without requesting another full reload.
  Future<void> ensureFriendsLoaded() => _inactive
      ? Future.value()
      : _friendsLoad ?? (friendsLoading.value ? loadFriends() : Future.value());

  Future<void> loadFriends() {
    if (_inactive) return Future.value();
    final pending = _friendsLoad;
    if (pending != null) {
      _reloadFriendsPending = true;
      ++_loadGeneration;
      return pending;
    }
    friendsLoading.value = true;
    return _friendsLoad = _loadFriendsUntilCurrent().whenComplete(() {
      _friendsLoad = null;
      _friendChangesDuringLoad.clear();
      if (!_inactive) {
        friendsLoading.value = false;
      }
    });
  }

  Future<void> _loadFriendsUntilCurrent() async {
    do {
      _reloadFriendsPending = false;
      final generation = ++_loadGeneration;
      try {
        final loaded = <ISUserInfo>[];
        const pageSize = 1000;
        while (!_inactive && generation == _loadGeneration) {
          final page = await _fetchFriendsPage(loaded.length, pageSize);
          // A newer request only needs the latest directory. Stop reading the
          // obsolete pages before starting its one coalesced replacement.
          if (_inactive || generation != _loadGeneration) break;
          loaded.addAll(
              page.map((friend) => ISUserInfo.fromJson(friend.toJson())));
          if (page.length < pageSize) break;
        }
        if (!_inactive && generation == _loadGeneration) {
          _directory
            ..clear()
            ..addEntries(loaded
                .where((friend) => friend.userID != null)
                .map((friend) => MapEntry(friend.userID!, friend)));
          // Live SDK events can be newer than the paginated query snapshot.
          for (final entry in _friendChangesDuringLoad.entries) {
            _applyFriendChange(entry.key, entry.value);
          }
          _directoryRevision++;
          await _publishDirectory();
        }
      } catch (_) {
        // Keep the last visible directory when the SDK is temporarily offline.
      }
    } while (!_inactive && _reloadFriendsPending);
  }

  void _upsertFriend(FriendInfo friend) {
    final id = friend.userID;
    if (id != null) _queueFriendChange(id, friend);
  }

  void _removeFriend(FriendInfo friend) {
    if (friend.userID != null) presence.remove(friend.userID!);
    final id = friend.userID;
    if (id != null) _queueFriendChange(id, null);
  }

  void _queueFriendChange(String id, FriendInfo? friend) {
    if (_inactive) return;
    if (_friendsLoad != null) _friendChangesDuringLoad[id] = friend;
    _applyFriendChange(id, friend);
    _directoryRevision++;
    _friendChangesTimer ??= Timer(const Duration(milliseconds: 80), () {
      _friendChangesTimer = null;
      unawaited(_publishDirectory());
    });
  }

  void _applyFriendChange(String id, FriendInfo? friend) {
    if (friend == null) {
      _directory.remove(id);
    } else {
      _directory[id] = ISUserInfo.fromJson(friend.toJson());
    }
  }

  Future<void> _publishDirectory() {
    if (_inactive) return Future.value();
    if (_directoryWork != null) {
      _directoryDirty = true;
      return _directoryWork!;
    }
    return _directoryWork = _indexUntilCurrent().whenComplete(() {
      _directoryWork = null;
    });
  }

  Future<void> _indexUntilCurrent() async {
    do {
      _directoryDirty = false;
      final revision = _directoryRevision;
      try {
        final indexed = await _directoryIndexer.build([
          for (final friend in _directory.values)
            ContactNameIndex(
                userID: friend.userID!, displayName: friend.showName),
        ]);
        if (_inactive) return;
        if (revision != _directoryRevision) {
          _directoryDirty = true;
          continue;
        }
        if (indexed != null) {
          friends.value = [
            for (final name in indexed)
              _directory[name.userID]!
                ..tagIndex = name.tagIndex
                ..namePinyin = name.namePinyin
                ..isShowSuspension = name.showHeader,
          ];
          unawaited(refreshPresence(force: false));
        }
      } catch (_) {
        // Keep the visible directory if indexing fails. A later event or sync
        // can retry without starting an unbounded worker loop.
      }
    } while (!_inactive && _directoryDirty);
  }

  @override
  void onClose() {
    _closed = true;
    ++_loadGeneration;
    _friendChangesTimer?.cancel();
    _friendChangesDuringLoad.clear();
    _directory.clear();
    _directoryIndexer.close();
    _inviteChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    _starSubscription?.cancel();
    stars.dispose();
    _presenceSubscription?.cancel();
    _presenceTimer?.cancel();
    _presenceStatusTimer?.cancel();
    _pendingPresenceStatusIDs.clear();
    _directoryPresenceIDs.clear();
    presence.dispose();
    if (_presenceIDs.isNotEmpty) {
      OpenIM.iMManager.userManager
          .unsubscribeUsersStatus(_presenceIDs.toList())
          .catchError((_) {});
    }
    _friendAddedSub?.cancel();
    _friendDeletedSub?.cancel();
    _friendChangedSub?.cancel();
    _syncSub?.cancel();
    PackageBridge.selectContactsBridge = null;
    PackageBridge.viewUserProfileBridge = null;
    PackageBridge.scanBridge = null;
    super.onClose();
  }

  void newFriend() => AppNavigator.startFriendRequests();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(stars.refresh());
    unawaited(refreshPresence());
  }

  Future<void> refreshPresence({bool force = true}) {
    if (_inactive) return Future.value();
    _presenceWork = _presenceWork.then((_) => _refreshVisiblePresence(force));
    return _presenceWork;
  }

  Future<void> _refreshVisiblePresence(bool force) async {
    if (_inactive) return;
    final ids = !_foreground
        ? <String>{}
        : _profilePresenceIDs.isNotEmpty
            ? {_profilePresenceIDs.values.last}
            : _directoryPresenceIDs.isNotEmpty
                ? Set<String>.of(_directoryPresenceIDs.values.last)
                : Set<String>.of(_visiblePresenceIDs);
    final removed = _presenceIDs.difference(ids);
    final added = ids.difference(_presenceIDs);
    for (final id in removed) {
      presence.stopWatching(id);
    }
    _presenceIDs
      ..clear()
      ..addAll(ids);
    try {
      if (removed.isNotEmpty) {
        await OpenIM.iMManager.userManager
            .unsubscribeUsersStatus(removed.toList());
      }
      final subscribe = force ? ids : added;
      if (subscribe.isNotEmpty && !_inactive) {
        await OpenIM.iMManager.userManager
            .subscribeUsersStatus(subscribe.toList());
      }
    } catch (_) {/* Retry subscriptions on the next foreground/reconnect. */}
    if (!_inactive) {
      // Retry an unavailable first snapshot without re-subscribing peers whose
      // ownership is unchanged. Confirmed snapshots remain visible meanwhile.
      final refreshIDs = force
          ? ids
          : {...added, ...ids.where((id) => presence.users[id] == null)};
      await presence.refresh(refreshIDs);
    }
  }

  void newGroup() => AppNavigator.startGroupRequests();

  void myFriend() => AppNavigator.startFriendList();

  void myGroup() => AppNavigator.startGroupList();

  void viewFriend(ISUserInfo friend) => AppNavigator.startUserProfilePane(
        userID: friend.userID!,
        nickname: friend.nickname,
        faceURL: friend.faceURL,
        ex: friend.ex ?? '',
      );

  void searchContacts() => AppNavigator.startGlobalSearch();

  void addContacts() => AppNavigator.startAddContactsMethod();

  void searchAddContacts() {
    if (!_inactive) {
      AppNavigator.startAddContactsBySearch(searchType: SearchType.user);
    }
  }

  void createContactsGroup() {
    if (!_inactive) {
      AppNavigator.startCreateGroup(
          defaultCheckedList: [OpenIM.iMManager.userInfo]);
    }
  }

  Future<void> scanContacts() async {
    if (_inactive) return;
    final invite = await Get.to<Map<String, String>>(
        () => FriendQrScanner(onMyQrTap: _openScannerQrCode));
    if (_inactive || invite == null) return;
    AppNavigator.startUserProfilePane(
      userID: invite['userID']!,
      addSource: invite['source'] == 'link'
          ? FriendAddSource.link
          : FriendAddSource.qrcode,
      friendAddFields: {'inviteCode': invite['inviteCode']!},
      forceCanAdd: true,
    );
  }

  Future<void> _openScannerQrCode() async {
    if (_inactive) return;
    final user = imLogic.userInfo.value;
    await Get.to<void>(() => QrProfilePage(
          nickname: user.nickname ?? '',
          userId: user.userID ?? '',
          account: user.account?.trim() ?? '',
          avatarUrl: user.faceURL ?? '',
        ));
  }

  @override
  Future<T?>? selectContacts<T>(
    int type, {
    List<String>? defaultCheckedIDList,
    List? checkedList,
    List<String>? excludeIDList,
    bool openSelectedSheet = false,
    String? groupID,
    String? ex,
  }) =>
      AppNavigator.startSelectContacts(
        action: SelAction.values[type],
        defaultCheckedIDList: defaultCheckedIDList,
        checkedList: checkedList,
        excludeIDList: excludeIDList,
        openSelectedSheet: openSelectedSheet,
        groupID: groupID,
        ex: ex,
      );

  @override
  viewUserProfile(String userID, String? nickname, String? faceURL,
          [String? groupID]) =>
      AppNavigator.startUserProfilePane(
        userID: userID,
        nickname: nickname,
        faceURL: faceURL,
        groupID: groupID,
      );

  @override
  scanOutGroupID(String groupID) => AppNavigator.startGroupProfilePanel(
        groupID: groupID,
        joinGroupMethod: JoinGroupMethod.qrcode,
        offAndToNamed: true,
      );

  @override
  scanOutUserID(String userID) {
    final invite = parseFriendInvite(userID);
    if (invite == null) {
      IMViews.showToast('邀请已失效，请获取新的邀请');
      return;
    }
    return AppNavigator.startUserProfilePane(
        userID: invite['userID']!,
        offAndToNamed: false,
        addSource: invite['source'] == 'link'
            ? FriendAddSource.link
            : FriendAddSource.qrcode,
        friendAddFields: {'inviteCode': invite['inviteCode']!});
  }
}
