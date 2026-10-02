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
import 'select_contacts/select_contacts_logic.dart';
import 'star_friend_store.dart';
import 'presence_store.dart';

class ContactsLogic extends GetxController
    with WidgetsBindingObserver
    implements ViewUserProfileBridge, SelectContactsBridge, ScanBridge {
  final imLogic = Get.find<IMController>();
  static const _inviteChannel = MethodChannel('openim_friend_invites');

  Future<void> _listenForInvites() async {
    _inviteChannel.setMethodCallHandler((call) async {
      if (isClosed || call.method != 'openInvite' || call.arguments is! String)
        return false;
      final link = call.arguments as String;
      if (parseFriendInvite(link) == null) return false;
      scanOutUserID(link);
      return true;
    });
    try {
      final pending = await _inviteChannel.invokeMethod<String>('takeInvite');
      if (!isClosed && pending != null && parseFriendInvite(pending) != null)
        scanOutUserID(pending);
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
  late final StreamSubscription<UserStatusInfo> _presenceSubscription;
  final _presenceIDs = <String>{};
  final _visiblePresenceIDs = <String>{};
  final _profilePresenceIDs = <Object, String>{};
  Timer? _presenceTimer;
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
      _profilePresenceIDs.remove(owner);
    } else {
      _profilePresenceIDs[owner] = id;
    }
    unawaited(refreshPresence());
  }

  late final StreamSubscription<String> _starSubscription;
  late final StreamSubscription<FriendInfo> _friendAddedSub;
  late final StreamSubscription<FriendInfo> _friendDeletedSub;
  late final StreamSubscription<FriendInfo> _friendChangedSub;
  late final StreamSubscription<dynamic> _syncSub;
  int _loadGeneration = 0;

  int get friendApplicationCount =>
      homeLogic.unhandledFriendApplicationCount.value;

  int get groupApplicationCount =>
      homeLogic.unhandledGroupApplicationCount.value;

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    _presenceSubscription = imLogic.userStatusChangedSubject.listen((event) {
      if (_presenceIDs.contains(event.userID)) {
        final cached = presence.users[event.userID];
        if (cached == null || cached.hidden) return;
        if (event.status == 1) {
          presence.markOnline(event.userID!);
        } else {
          presence.markOffline(event.userID!);
          unawaited(presence.refresh([event.userID!]));
        }
      }
    });
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
    super.onReady();
    unawaited(_listenForInvites());
    loadFriends();
  }

  Future<void> loadFriends() async {
    final generation = ++_loadGeneration;
    friendsLoading.value = true;
    try {
      final loaded = <ISUserInfo>[];
      const pageSize = 1000;
      while (true) {
        final page = await OpenIM.iMManager.friendshipManager.getFriendListPage(
          offset: loaded.length,
          count: pageSize,
          filterBlack: true,
        );
        loaded
            .addAll(page.map((friend) => ISUserInfo.fromJson(friend.toJson())));
        if (page.length < pageSize) break;
      }
      if (generation == _loadGeneration && !isClosed) {
        friends.assignAll(IMUtils.convertToAZList(loaded).cast<ISUserInfo>());
        unawaited(refreshPresence(force: false));
      }
    } catch (_) {
      // Keep the last visible directory when the SDK is temporarily offline.
    } finally {
      if (generation == _loadGeneration && !isClosed) {
        friendsLoading.value = false;
      }
    }
  }

  void _upsertFriend(FriendInfo friend) {
    final updated = ISUserInfo.fromJson(friend.toJson());
    final all = friends.where((item) => item.userID != updated.userID).toList()
      ..add(updated);
    friends.assignAll(IMUtils.convertToAZList(all).cast<ISUserInfo>());
    unawaited(loadFriends());
  }

  void _removeFriend(FriendInfo friend) {
    if (friend.userID != null) presence.remove(friend.userID!);
    friends.removeWhere((item) => item.userID == friend.userID);
    unawaited(loadFriends());
  }

  @override
  void onClose() {
    _inviteChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    _starSubscription.cancel();
    stars.dispose();
    _presenceSubscription.cancel();
    _presenceTimer?.cancel();
    presence.dispose();
    if (_presenceIDs.isNotEmpty) {
      OpenIM.iMManager.userManager
          .unsubscribeUsersStatus(_presenceIDs.toList())
          .catchError((_) {});
    }
    _friendAddedSub.cancel();
    _friendDeletedSub.cancel();
    _friendChangedSub.cancel();
    _syncSub.cancel();
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
    _presenceWork = _presenceWork.then((_) => _refreshVisiblePresence(force));
    return _presenceWork;
  }

  Future<void> _refreshVisiblePresence(bool force) async {
    if (isClosed) return;
    final ids = !_foreground
        ? <String>{}
        : _profilePresenceIDs.isNotEmpty
            ? {_profilePresenceIDs.values.last}
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
      if (subscribe.isNotEmpty && !isClosed) {
        await OpenIM.iMManager.userManager
            .subscribeUsersStatus(subscribe.toList());
      }
    } catch (_) {/* Retry subscriptions on the next foreground/reconnect. */}
    if (!isClosed) await presence.refresh(force ? ids : added);
  }

  void newGroup() => AppNavigator.startGroupRequests();

  void myFriend() => AppNavigator.startFriendList();

  void myGroup() => AppNavigator.startGroupList();

  void viewFriend(ISUserInfo friend) => AppNavigator.startUserProfilePane(
        userID: friend.userID!,
        nickname: friend.nickname,
        faceURL: friend.faceURL,
      );

  void searchContacts() => AppNavigator.startGlobalSearch();

  void addContacts() => AppNavigator.startAddContactsMethod();

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
