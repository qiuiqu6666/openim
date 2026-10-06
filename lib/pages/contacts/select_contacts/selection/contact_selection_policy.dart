import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../../ai_assistant/navigation/official_account_resolver.dart';
import '../../../official_account/models/official_account.dart';

/// Notification accounts remain readable contacts, but are never recipients,
/// shared contact cards, or invitees in the contact selection flow.
class ContactSelectionPolicy {
  ContactSelectionPolicy._();

  /// A forward/share destination list can show notification accounts for
  /// recognition while [allows] continues to reject them as recipients.
  static bool allowsVisible(Object? info,
          {bool showNotificationAccounts = false}) =>
      showNotificationAccounts || allows(info);

  static String? userExtension(Object? info) {
    if (info is ConversationInfo) return info.isSingleChat ? info.ex : null;
    if (info is UserInfo) return info.ex;
    if (info is PublicUserInfo) return info.ex;
    if (info is FriendInfo) return info.ex;
    if (info is UserFullInfo) return info.ex;
    if (info is GroupMembersInfo) return info.ex;
    return null;
  }

  static String? _userID(Object? info) {
    if (info is ConversationInfo) return info.isSingleChat ? info.userID : null;
    if (info is UserInfo) return info.userID;
    if (info is PublicUserInfo) return info.userID;
    if (info is FriendInfo) return info.userID;
    if (info is UserFullInfo) return info.userID;
    if (info is GroupMembersInfo) return info.userID;
    return null;
  }

  static bool hasVerifiedIdentity(Object? info) =>
      OfficialAccount.hasVerifiedIdentity(
          userID: _userID(info), ex: userExtension(info));

  /// Official service accounts cannot be invited as group members. The stable
  /// assistant ID also applies when its SDK profile has no extension metadata.
  static bool allowsGroupMember(Object? info) =>
      allows(info) &&
      _userID(info)?.trim() != OfficialAccountResolver.assistantUserID &&
      !OfficialAccount.isOfficialExtension(userExtension(info));

  static bool allowsGroupMemberUserID(String userID) =>
      allowsUserID(userID) &&
      userID.trim() != OfficialAccountResolver.assistantUserID;

  static bool allows(Object? info) {
    if (info is ConversationInfo) {
      return !info.isSingleChat ||
          _allowsUser(userID: info.userID, ex: info.ex);
    }
    if (info is UserInfo) {
      return _allowsUser(userID: info.userID, ex: info.ex);
    }
    if (info is PublicUserInfo) {
      return _allowsUser(userID: info.userID, ex: info.ex);
    }
    if (info is FriendInfo) {
      return _allowsUser(userID: info.userID, ex: info.ex);
    }
    if (info is UserFullInfo) {
      return _allowsUser(userID: info.userID, ex: info.ex);
    }
    if (info is GroupMembersInfo) {
      return _allowsUser(userID: info.userID, ex: info.ex);
    }
    // Group metadata is unrelated to the group's members' account roles.
    return true;
  }

  static bool allowsUserID(String userID) => _allowsUser(userID: userID);

  static bool _allowsUser({String? userID, String? ex}) =>
      OfficialAccount.from(userID: userID, ex: ex) == null;
}
