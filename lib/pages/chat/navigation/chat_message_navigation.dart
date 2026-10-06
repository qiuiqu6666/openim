import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:url_launcher/url_launcher.dart';
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

  void onTapLeftAvatar(Message message) {
    viewUserInfo(UserInfo()
      ..userID = message.sendID
      ..nickname = message.senderNickname
      ..faceURL = message.senderFaceUrl);
  }

  void onTapRightAvatar() {
    viewUserInfo(OpenIM.iMManager.userInfo);
  }

  void viewUserInfo(UserInfo userInfo,
      {bool isCard = false, String? inviteCode}) {
    if (isClosed) return;
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
        groupID: groupID,
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
    if (uri != null && await canLaunchUrl(uri) && !isClosed) {
      await launchUrl(uri);
    }
  }

  Future<void> searchMentionID(String id) async {
    final candidates = mentionIDCandidates(id.trim());
    if (candidates.first.isEmpty) return;
    final results = await LoadingView.singleton.wrap(asyncFunction: () async {
      final usersFuture = _findMentionUsers(candidates);
      final groupsFuture = _findMentionGroups(candidates);
      return (await usersFuture, await groupsFuture);
    });
    if (isClosed) return;

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
