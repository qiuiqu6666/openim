import 'package:openim_common/localization.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../../routes/app_navigator.dart';
import '../../contacts/group_profile_panel/group_profile_panel_logic.dart';
import '../composer/mention_id.dart';

/// Message profile, link, and mention-ID navigation.
class ChatMessageNavigation {
  ChatMessageNavigation({
    required bool Function() isClosed,
    required bool Function() isGroupChat,
    required bool Function() isSingleChat,
    required bool Function() isAdminOrOwner,
    required String? Function() groupID,
    required GroupInfo? Function() groupInfo,
  })  : _isClosed = isClosed,
        _isGroupChat = isGroupChat,
        _isSingleChat = isSingleChat,
        _isAdminOrOwner = isAdminOrOwner,
        _groupID = groupID,
        _groupInfo = groupInfo;
  final bool Function() _isClosed, _isGroupChat, _isSingleChat, _isAdminOrOwner;
  final String? Function() _groupID;
  final GroupInfo? Function() _groupInfo;
  bool get isClosed => _isClosed();
  bool get isGroupChat => _isGroupChat();
  bool get isSingleChat => _isSingleChat();
  bool get isAdminOrOwner => _isAdminOrOwner();
  String? get groupID => _groupID();
  GroupInfo? get groupInfo => _groupInfo();

  bool _openingFriendVerification = false;

  Future<void> sendFriendVerification({
    required String? userID,
    required String nickname,
    required String faceURL,
  }) async {
    if (isClosed ||
        !isSingleChat ||
        userID == null ||
        userID.trim().isEmpty ||
        _openingFriendVerification) {
      return;
    }
    _openingFriendVerification = true;
    final owner = (OpenIM.iMManager.userID, DataSp.chatToken);
    final route = Get.currentRoute;
    final arguments = Get.arguments;
    try {
      await FriendRelationshipGuard.requireNotBlocked(userID);
      if (isClosed ||
          owner != (OpenIM.iMManager.userID, DataSp.chatToken) ||
          route != Get.currentRoute ||
          !identical(arguments, Get.arguments)) {
        return;
      }
      final users = await LoadingView.singleton.wrap(
        asyncFunction: () => Apis.getUserFullInfo(
          userIDList: [userID],
          showErrorToast: false,
        ),
      );
      if (isClosed ||
          owner != (OpenIM.iMManager.userID, DataSp.chatToken) ||
          route != Get.currentRoute ||
          !identical(arguments, Get.arguments)) {
        return;
      }
      final user = users?.firstWhereOrNull((item) => item.userID == userID);
      final account = normalizePublicAccountSearch(user?.account ?? '');
      await AppNavigator.startSendVerificationApplication(
        userID: userID,
        targetName: user?.nickname ?? nickname,
        targetAvatarURL: user?.faceURL ?? faceURL,
        targetAccount: account,
        selfNickname: OpenIM.iMManager.userInfo.nickname,
        addSource:
            account == null ? FriendAddSource.chat : FriendAddSource.account,
        friendAddFields: account == null ? const {} : {'account': account},
      );
    } catch (error) {
      if (!isClosed &&
          owner == (OpenIM.iMManager.userID, DataSp.chatToken) &&
          route == Get.currentRoute &&
          identical(arguments, Get.arguments)) {
        IMViews.showToast(friendAddErrorMessage(error,
                chinese: Get.locale?.languageCode != 'en') ??
            StrRes.addFailed);
      }
    } finally {
      _openingFriendVerification = false;
    }
  }

  void onTapLeftAvatar(Message message) {
    _viewAvatar(UserInfo()
      ..userID = message.sendID
      ..nickname = message.senderNickname
      ..faceURL = message.senderFaceUrl);
  }

  void onTapRightAvatar() {
    _viewAvatar(UserInfo(
      userID: OpenIM.iMManager.userID,
      nickname: OpenIM.iMManager.userInfo.nickname,
      faceURL: OpenIM.iMManager.userInfo.faceURL,
    ));
  }

  void _viewAvatar(UserInfo userInfo) {
    if (!isGroupChat) {
      viewUserInfo(userInfo);
      return;
    }
    if (isClosed) return;
    final userID = userInfo.userID;
    if (userID == null || userID.isEmpty) return;
    // Match the member-list entry. The profile owns group privacy and actions.
    AppNavigator.startUserProfilePane(
      userID: userID,
      groupID: groupID,
      nickname: userInfo.nickname,
      faceURL: userInfo.faceURL,
    );
  }

  void viewUserInfo(UserInfo userInfo,
      {bool isCard = false, String? inviteCode}) {
    if (isClosed) return;
    final userID = userInfo.userID;
    if (userID == null || userID.isEmpty) return;
    // Group member privacy never prevents the owner from viewing themselves.
    if (AppNavigator.isCurrentUser(userID)) {
      AppNavigator.startUserProfilePane(userID: userID);
      return;
    }
    if (isGroupChat && !isAdminOrOwner && !isCard) {
      // Until group metadata arrives, member-profile permission is unknown.
      // A later click re-evaluates the loaded policy rather than bypassing it.
      final info = groupInfo;
      if (info != null && info.lookMemberInfo != 1) {
        AppNavigator.startUserProfilePane(
          userID: userInfo.userID!,
          nickname: userInfo.nickname,
          faceURL: userInfo.faceURL,
          groupID: groupID,
          offAllWhenDelFriend: isSingleChat,
        );
      }
    } else {
      AppNavigator.startUserProfilePane(
        userID: userInfo.userID!,
        nickname: userInfo.nickname,
        faceURL: userInfo.faceURL,
        // A shared card identifies a person, not membership in the source chat.
        groupID: isCard ? null : groupID,
        offAllWhenDelFriend: isSingleChat,
        forceCanAdd: isCard,
        addSource: isCard ? FriendAddSource.card : null,
        friendAddFields: isCard ? {'inviteCode': inviteCode ?? ''} : const {},
      );
    }
  }

  Future<void> clickLinkText(String url, Object? type) async {
    if (isClosed) return;
    final uri = Uri.tryParse(url);
    if (uri != null && !isClosed) {
      if (!await openInAppBrowser(uri)) {
        IMViews.showToast(AppCopy.text('此链接不支持在应用内打开'));
      }
    }
  }

  Future<void> searchMentionID(String id) async {
    if (isClosed) return;
    final owner = (OpenIM.iMManager.userID, DataSp.imToken);
    final candidates = mentionIDCandidates(id.trim());
    if (candidates.first.isEmpty) return;
    final results = await LoadingView.singleton.wrap(asyncFunction: () async {
      final usersFuture = _findMentionUsers(candidates);
      final groupsFuture = _findMentionGroups(candidates);
      return (await usersFuture, await groupsFuture);
    });
    if (isClosed || owner != (OpenIM.iMManager.userID, DataSp.imToken)) return;

    final user = results.$1
        .firstWhereOrNull((item) => _matchesMentionUser(item, candidates));
    final group = results.$2
        .firstWhereOrNull((item) => candidates.contains(item.groupID));
    if (group != null) {
      AppNavigator.startGroupProfilePanel(
        groupID: group.groupID,
        joinGroupMethod: JoinGroupMethod.search,
      );
    } else if (user != null) {
      AppNavigator.startUserProfilePane(
        userID: user.userID!,
        nickname: user.nickname,
        faceURL: user.faceURL,
      );
    } else {
      IMViews.showToast('mentionIdNotFound'.tr);
    }
  }

  Future<List<UserFullInfo>> _findMentionUsers(List<String> candidates) async {
    for (final candidate in candidates) {
      try {
        final users = await Apis.searchUserFullInfo(content: candidate);
        final exact = users
            ?.where((item) => _matchesMentionUser(item, candidates))
            .toList();
        if (exact != null && exact.isNotEmpty) return exact;
      } catch (_) {}
    }
    return [];
  }

  bool _matchesMentionUser(UserFullInfo user, List<String> candidates) {
    if (user.userID?.trim().isNotEmpty != true) return false;
    if (candidates.contains(user.userID)) return true;

    // Public accounts identify a user, while navigation requires the SDK ID.
    final account = normalizePublicAccountSearch(user.account ?? '');
    return account != null &&
        candidates.any(
            (candidate) => normalizePublicAccountSearch(candidate) == account);
  }

  Future<List<GroupInfo>> _findMentionGroups(List<String> candidates) async {
    for (final candidate in candidates) {
      try {
        final groups = await OpenIM.iMManager.groupManager
            .getGroupsInfo(groupIDList: [candidate]);
        if (groups.any((item) => candidates.contains(item.groupID))) {
          return groups;
        }
      } catch (_) {}
    }
    for (final candidate in candidates) {
      try {
        final groups = await OpenIM.iMManager.groupManager
            .searchGroups(keywordList: [candidate], isSearchGroupID: true);
        if (groups.any((item) => candidates.contains(item.groupID))) {
          return groups;
        }
      } catch (_) {}
    }
    return [];
  }
}
