import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import '../pages/register/profile/registration_profile_draft.dart';
import 'package:openim_common/openim_common.dart';

import '../pages/ai_assistant/navigation/official_account_resolver.dart';
import '../pages/chat/group_setup/edit_name/edit_name_logic.dart';
import '../pages/chat/group_setup/group_member_list/group_member_list_logic.dart';
import '../pages/chat/history/chat_history_prefetcher.dart';
import '../pages/contacts/add_by_search/add_by_search_logic.dart';
import '../pages/contacts/group_profile_panel/group_profile_panel_logic.dart';
import '../pages/contacts/select_contacts/select_contacts_logic.dart';
import '../pages/mine/edit_my_info/edit_my_info_logic.dart';
import '../pages/official_account/models/official_account.dart';
import 'app_pages.dart';

class AppNavigator {
  AppNavigator._();

  static void startLogin() {
    Get.offAllNamed(AppRoutes.login);
  }

  static void startBackLogin() {
    Get.until((route) => Get.currentRoute == AppRoutes.login);
  }

  static void startMain(
      {bool isAutoLogin = false, List<ConversationInfo>? conversations}) {
    Get.offAllNamed(
      AppRoutes.home,
      arguments: {'isAutoLogin': isAutoLogin, 'conversations': conversations},
    );
  }

  static void startSplashToMain(
      {bool isAutoLogin = false, List<ConversationInfo>? conversations}) {
    Get.offAndToNamed(
      AppRoutes.home,
      arguments: {'isAutoLogin': isAutoLogin, 'conversations': conversations},
    );
  }

  static void startBackMain() {
    Get.until((route) => Get.currentRoute == AppRoutes.home);
  }

  static Future<T?>? startChat<T>({
    required ConversationInfo conversationInfo,
    bool offUntilHome = true,
    String? draftText,
    Message? searchMessage,
    bool Function()? isCurrent,
  }) async {
    if (isCurrent?.call() == false) return null;
    final owner = (OpenIM.iMManager.userID, DataSp.imToken);
    final resolution = await OfficialAccountResolver.shared
        .resolveConversation(conversationInfo);
    if (owner != (OpenIM.iMManager.userID, DataSp.imToken) ||
        isCurrent?.call() == false) {
      return null;
    }
    return _startResolvedChat<T>(
      conversationInfo: conversationInfo,
      resolution: resolution,
      offUntilHome: offUntilHome,
      draftText: draftText,
      searchMessage: searchMessage,
    );
  }

  static Future<T?>? _startResolvedChat<T>({
    required ConversationInfo conversationInfo,
    required OfficialConversationResolution resolution,
    bool offUntilHome = true,
    bool replaceCurrent = false,
    String? draftText,
    Message? searchMessage,
  }) {
    ChatHistoryPrefetcher.shared.prepare(conversationInfo);
    GetTags.createChatTag();
    final route = switch (resolution.target) {
      OfficialConversationTarget.notification => AppRoutes.officialAccountChat,
      OfficialConversationTarget.assistant => AppRoutes.aiAssistantChat,
      OfficialConversationTarget.chat => AppRoutes.chat,
    };

    final arguments = {
      'draftText': draftText,
      'conversationInfo': conversationInfo,
      'searchMessage': searchMessage,
      if (resolution.account != null) 'officialAccount': resolution.account,
    };

    if (replaceCurrent) {
      return Get.offAndToNamed(route, arguments: arguments);
    }

    return offUntilHome
        ? Get.offNamedUntil(
            route,
            (route) => route.settings.name == AppRoutes.home,
            arguments: arguments,
          )
        : Get.toNamed(
            route,
            arguments: arguments,
            preventDuplicates: false,
          );
  }

  static Future<T?>? startAiAssistant<T>({bool offUntilHome = false}) async {
    final owner = (OpenIM.iMManager.userID, DataSp.imToken);
    if (owner.$1.isEmpty || owner.$2?.isNotEmpty != true) {
      IMViews.showToast('请先登录后使用 AI 助理');
      return null;
    }
    ConversationInfo conversation;
    try {
      conversation = await OpenIM.iMManager.conversationManager
          .getOneConversation(
              sourceID: OfficialAccountResolver.assistantUserID,
              sessionType: ConversationType.single);
    } catch (_) {
      if (owner == (OpenIM.iMManager.userID, DataSp.imToken)) {
        IMViews.showToast('无法打开 AI 助理，请稍后再试');
      }
      return null;
    }
    if (owner != (OpenIM.iMManager.userID, DataSp.imToken)) return null;
    if (conversation.userID != OfficialAccountResolver.assistantUserID ||
        conversation.conversationType != ConversationType.single) {
      IMViews.showToast('无法打开 AI 助理，请稍后再试');
      return null;
    }
    if (conversation.showName?.trim().isNotEmpty != true) {
      conversation.showName = 'AI助理';
    }
    return startChat<T>(
        conversationInfo: conversation,
        draftText: conversation.draftText,
        offUntilHome: offUntilHome);
  }

  static startAddContactsMethod() => Get.toNamed(AppRoutes.addContactsMethod);

  static startAddContactsBySearch({required SearchType searchType}) =>
      Get.toNamed(
        AppRoutes.addContactsBySearch,
        arguments: {"searchType": searchType},
      );

  static Future<dynamic> startUserProfilePane({
    required String userID,
    FriendAddSource? addSource,
    Map<String, String> friendAddFields = const {},
    String? groupID,
    String? nickname,
    String? faceURL,
    String? ex,
    bool offAllWhenDelFriend = false,
    bool offAndToNamed = false,
    bool forceCanAdd = false,
  }) async {
    final owner = (OpenIM.iMManager.userID, DataSp.imToken);
    final resolution = await _resolveProfileTarget(userID, ex: ex);
    if (owner != (OpenIM.iMManager.userID, DataSp.imToken)) return null;
    if (resolution.target != OfficialConversationTarget.chat) {
      return _startOfficialConversation(userID, resolution, owner,
          replaceCurrent: offAndToNamed);
    }
    GetTags.createUserProfileTag();

    final arguments = {
      'groupID': groupID,
      'userID': userID,
      'nickname': nickname,
      'faceURL': faceURL,
      'offAllWhenDelFriend': offAllWhenDelFriend,
      'forceCanAdd': forceCanAdd,
      'addSource': resolveFriendAddSource(addSource, groupID: groupID),
      'friendAddFields': friendAddFields,
    };

    return offAndToNamed
        ? Get.offAndToNamed(AppRoutes.userProfilePanel, arguments: arguments)
        : Get.toNamed(
            AppRoutes.userProfilePanel,
            arguments: arguments,
            preventDuplicates: false,
          );
  }

  static Future<dynamic> startPersonalInfo({
    required String userID,
  }) =>
      _startUserDetailsRoute(AppRoutes.personalInfo, userID);

  static Future<dynamic> startFriendSetup({
    required String userID,
  }) =>
      _startUserDetailsRoute(AppRoutes.friendSetup, userID);

  static Future<OfficialConversationResolution> _resolveProfileTarget(
    String userID, {
    String? ex,
  }) {
    // Looking at one's own profile must retain the existing immediate entry.
    if (userID == OpenIM.iMManager.userID) {
      return Future.value(const OfficialConversationResolution(
          OfficialConversationTarget.chat));
    }
    return OfficialAccountResolver.shared
        .resolveUser(userID: userID, ex: ex, lookupProfile: ex == null);
  }

  static Future<dynamic> _startUserDetailsRoute(
      String route, String userID) async {
    final owner = (OpenIM.iMManager.userID, DataSp.imToken);
    final resolution = await _resolveProfileTarget(userID);
    if (owner != (OpenIM.iMManager.userID, DataSp.imToken)) return null;
    if (resolution.target != OfficialConversationTarget.chat) {
      return _startOfficialConversation(userID, resolution, owner);
    }
    return Get.toNamed(route, arguments: {'userID': userID});
  }

  static Future<dynamic> _startOfficialConversation(
    String userID,
    OfficialConversationResolution resolution,
    (String, String?) owner, {
    bool replaceCurrent = false,
  }) async {
    ConversationInfo conversation;
    try {
      conversation = await OpenIM.iMManager.conversationManager
          .getOneConversation(
              sourceID: userID, sessionType: ConversationType.single);
    } catch (_) {
      if (owner == (OpenIM.iMManager.userID, DataSp.imToken)) {
        IMViews.showToast('无法打开官方账号，请稍后再试');
      }
      return null;
    }
    if (owner != (OpenIM.iMManager.userID, DataSp.imToken)) return null;
    if (conversation.userID != userID ||
        conversation.conversationType != ConversationType.single) {
      IMViews.showToast('无法打开官方账号，请稍后再试');
      return null;
    }
    if (conversation.showName?.trim().isNotEmpty != true &&
        resolution.account != null) {
      conversation.showName = resolution.account!.displayName;
    }
    return _startResolvedChat(
      conversationInfo: conversation,
      resolution: resolution,
      draftText: conversation.draftText,
      offUntilHome: false,
      replaceCurrent: replaceCurrent,
    );
  }

  static startSetFriendRemark() =>
      Get.toNamed(AppRoutes.setFriendRemark, arguments: {});

  static startSendVerificationApplication({
    String? userID,
    String? targetName,
    String? targetAvatarURL,
    String? targetAccount,
    String? selfNickname,
    FriendAddSource? addSource,
    Map<String, String> friendAddFields = const {},
    String? friendGroupID,
    String? groupID,
    JoinGroupMethod? joinGroupMethod,
  }) =>
      Get.toNamed(AppRoutes.sendVerificationApplication, arguments: {
        'joinGroupMethod': joinGroupMethod,
        'addSource': resolveFriendAddSource(addSource, groupID: friendGroupID),
        'friendGroupID': friendGroupID,
        'friendAddFields': friendAddFields,
        'userID': userID,
        'targetName': targetName,
        'targetAvatarURL': targetAvatarURL,
        'targetAccount': targetAccount,
        'selfNickname': selfNickname,
        'groupID': groupID,
      });

  static startGroupProfilePanel({
    required String groupID,
    required JoinGroupMethod joinGroupMethod,
    bool offAndToNamed = false,
  }) =>
      offAndToNamed
          ? Get.offAndToNamed(AppRoutes.groupProfilePanel, arguments: {
              'joinGroupMethod': joinGroupMethod,
              'groupID': groupID,
            })
          : Get.toNamed(AppRoutes.groupProfilePanel, arguments: {
              'joinGroupMethod': joinGroupMethod,
              'groupID': groupID,
            });

  static startMyInfo() => Get.toNamed(AppRoutes.myInfo);

  static startEditMyInfo({EditAttr attr = EditAttr.nickname, int? maxLength}) =>
      Get.toNamed(AppRoutes.editMyInfo,
          arguments: {'editAttr': attr, 'maxLength': maxLength});

  static startAccountSetup() => Get.toNamed(AppRoutes.accountSetup);

  static startBlacklist() => Get.toNamed(AppRoutes.blacklist);

  static startLanguageSetup() => Get.toNamed(AppRoutes.languageSetup);

  static startAboutUs() => Get.toNamed(AppRoutes.aboutUs);

  static Future<dynamic>? startChatSetup({
    required ConversationInfo conversationInfo,
  }) {
    if (conversationInfo.conversationType == ConversationType.single &&
        OfficialAccount.from(
                userID: conversationInfo.userID, ex: conversationInfo.ex) !=
            null) {
      return null;
    }
    return Get.toNamed(AppRoutes.chatSetup, arguments: {
      'conversationInfo': conversationInfo,
    });
  }

  static startGroupChatSetup({
    required ConversationInfo conversationInfo,
  }) =>
      Get.toNamed(AppRoutes.groupChatSetup, arguments: {
        'conversationInfo': conversationInfo,
      });

  static startGroupManage({
    required GroupInfo groupInfo,
  }) =>
      Get.toNamed(AppRoutes.groupManage, arguments: {
        'groupInfo': groupInfo,
      });

  static startEditGroupName({required EditNameType type, String? faceUrl}) =>
      Get.toNamed(AppRoutes.editGroupName, arguments: {
        'type': type,
        'faceUrl': faceUrl,
      });

  static Future<T?> startGroupMemberList<T>({
    required GroupInfo groupInfo,
    GroupMemberOpType opType = GroupMemberOpType.view,
  }) async {
    // Named GetX routes are registered as dynamic. Convert the result after
    // navigation completes instead of requiring a typed Route at push time.
    final result = await Get.toNamed<dynamic>(AppRoutes.groupMemberList,
        preventDuplicates: false,
        arguments: {
          'groupInfo': groupInfo,
          'opType': opType,
        });
    return result as T?;
  }

  static startSearchGroupMember({
    required GroupInfo groupInfo,
    GroupMemberOpType opType = GroupMemberOpType.view,
  }) =>
      Get.toNamed(AppRoutes.searchGroupMember, arguments: {
        'groupInfo': groupInfo,
        'opType': opType,
      });

  static startGroupQrcode() => Get.toNamed(AppRoutes.groupQrcode);

  static startFriendRequests() => Get.toNamed(AppRoutes.friendRequests);

  static startProcessFriendRequests({
    required FriendApplicationInfo applicationInfo,
  }) =>
      Get.toNamed(AppRoutes.processFriendRequests, arguments: {
        'applicationInfo': applicationInfo,
      });

  static startGroupRequests() => Get.toNamed(AppRoutes.groupRequests);

  static startProcessGroupRequests({
    required GroupApplicationInfo applicationInfo,
  }) =>
      Get.toNamed(AppRoutes.processGroupRequests, arguments: {
        'applicationInfo': applicationInfo,
      });

  static startFriendList() => Get.toNamed(AppRoutes.friendList);

  static startGroupList() => Get.toNamed(AppRoutes.groupList);

  static startSelectContacts({
    required SelAction action,
    UserInfo? sharedContact,
    String? cardRecipientName,
    String? cardRecipientFaceURL,
    bool cardRecipientIsGroup = false,
    List<String>? defaultCheckedIDList,
    List<dynamic>? checkedList,
    List<String>? excludeIDList,
    bool openSelectedSheet = false,
    String? groupID,
    String? ex,
  }) =>
      Get.toNamed(AppRoutes.selectContacts, arguments: {
        'action': action,
        'sharedContact': sharedContact,
        'cardRecipientName': cardRecipientName,
        'cardRecipientFaceURL': cardRecipientFaceURL,
        'cardRecipientIsGroup': cardRecipientIsGroup,
        'defaultCheckedIDList': defaultCheckedIDList,
        'checkedList': IMUtils.convertCheckedListToMap(checkedList),
        'excludeIDList': excludeIDList,
        'openSelectedSheet': openSelectedSheet,
        'groupID': groupID,
        'ex': ex,
      });

  static startSelectContactsFromFriends() =>
      Get.toNamed(AppRoutes.selectContactsFromFriends);

  static startSelectContactsFromGroup() =>
      Get.toNamed(AppRoutes.selectContactsFromGroup);

  static startSelectContactsFromSearch() =>
      Get.toNamed(AppRoutes.selectContactsFromSearch);

  static startCreateGroup({
    List<UserInfo> defaultCheckedList = const [],
  }) async {
    final result = await startSelectContacts(
      action: SelAction.crateGroup,
      defaultCheckedIDList: defaultCheckedList.map((e) => e.userID!).toList(),
    );
    final list = IMUtils.convertSelectContactsResultToUserInfo(result);
    if (list is List<UserInfo>) {
      return Get.toNamed(
        AppRoutes.createGroup,
        arguments: {
          'checkedList': list,
          'defaultCheckedList': defaultCheckedList
        },
      );
    }
    return null;
  }

  static startGlobalSearch() => Get.toNamed(AppRoutes.globalSearch);

  static startExpandChatHistory({
    required SearchResultItems searchResultItems,
    required String defaultSearchKey,
  }) =>
      Get.toNamed(AppRoutes.expandChatHistory, arguments: {
        'searchResultItems': searchResultItems,
        'defaultSearchKey': defaultSearchKey,
      });

  static startRegister() => Get.toNamed(AppRoutes.register);

  static void startVerifyPhone({
    String? phoneNumber,
    String? email,
    required String areaCode,
    required int usedFor,
    String? invitationCode,
  }) =>
      Get.toNamed(AppRoutes.verifyPhone, arguments: {
        'phoneNumber': phoneNumber,
        'email': email,
        'areaCode': areaCode,
        'usedFor': usedFor,
        'invitationCode': invitationCode,
      });

  static void startSetPassword({
    RegistrationProfileDraft? profileDraft,
    String? phoneNumber,
    String? email,
    required String areaCode,
    required int usedFor,
    required String verificationCode,
    String? invitationCode,
    String? password,
  }) =>
      Get.toNamed(AppRoutes.setPassword, arguments: {
        'profileDraft': profileDraft,
        'phoneNumber': phoneNumber,
        'email': email,
        'areaCode': areaCode,
        'usedFor': usedFor,
        'verificationCode': verificationCode,
        'invitationCode': invitationCode,
        'password': password,
      });

  static void startSetSelfInfo({
    String? phoneNumber,
    String? email,
    String? account,
    required String areaCode,
    required password,
    required int usedFor,
    required String verificationCode,
    String? invitationCode,
  }) =>
      Get.toNamed(AppRoutes.setSelfInfo, arguments: {
        'phoneNumber': phoneNumber,
        'email': email,
        'account': account,
        'areaCode': areaCode,
        'password': password,
        'usedFor': usedFor,
        'verificationCode': verificationCode,
        'invitationCode': invitationCode
      });

  static startForgetPassword() => Get.toNamed(AppRoutes.forgetPassword);

  static void startResetPassword({
    String? phoneNumber,
    String? email,
    String? account,
    required String areaCode,
    required String verificationCode,
  }) =>
      Get.toNamed(AppRoutes.resetPassword, arguments: {
        'phoneNumber': phoneNumber,
        'email': email,
        'account': account,
        'areaCode': areaCode,
        'usedFor': 2,
        'verificationCode': verificationCode,
      });

  static startSelectContactsFromTag() =>
      Get.toNamed(AppRoutes.selectContactsFromTag);
}
