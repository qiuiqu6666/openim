import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../official_account/models/official_account.dart';

typedef OfficialAccountProfileLoader = Future<List<PublicUserInfo>> Function(
    String userID);

enum OfficialConversationTarget { chat, assistant, notification }

class OfficialConversationResolution {
  const OfficialConversationResolution(this.target, {this.account});

  final OfficialConversationTarget target;
  final OfficialAccount? account;
}

/// Selects the official conversation presentation from SDK account metadata.
/// No profile cache is retained across account changes.
class OfficialAccountResolver {
  OfficialAccountResolver({
    OfficialAccountProfileLoader? loadProfiles,
    this.lookupTimeout = const Duration(seconds: 3),
  }) : _loadProfiles = loadProfiles ?? _sdkProfiles;

  static const assistantUserID = OfficialAccount.assistantUserID;
  static final shared = OfficialAccountResolver();

  final OfficialAccountProfileLoader _loadProfiles;
  final Duration lookupTimeout;

  static Future<List<PublicUserInfo>> _sdkProfiles(String userID) =>
      OpenIM.iMManager.userManager.getUsersInfo(userIDList: [userID]);

  static bool isOfficialExtension(String? ex) =>
      OfficialAccount.isOfficialExtension(ex);

  static OfficialConversationResolution _metadata(String userID, String? ex) {
    if (userID == assistantUserID) {
      return const OfficialConversationResolution(
          OfficialConversationTarget.assistant);
    }
    final account = OfficialAccount.from(userID: userID, ex: ex);
    if (account != null) {
      return OfficialConversationResolution(
          OfficialConversationTarget.notification,
          account: account);
    }
    if (isOfficialExtension(ex)) {
      // Preserve the existing presentation for other interactive official users.
      return const OfficialConversationResolution(
          OfficialConversationTarget.assistant);
    }
    return const OfficialConversationResolution(
        OfficialConversationTarget.chat);
  }

  Future<OfficialConversationResolution> resolveUser({
    required String userID,
    String? ex,
    bool lookupProfile = true,
  }) async {
    final id = userID.trim();
    if (id.isEmpty) {
      return const OfficialConversationResolution(
          OfficialConversationTarget.chat);
    }
    final metadata = _metadata(id, ex);
    if (metadata.target != OfficialConversationTarget.chat || !lookupProfile) {
      return metadata;
    }
    try {
      final profiles = await _loadProfiles(id).timeout(lookupTimeout);
      for (final profile in profiles) {
        if (profile.userID == id) return _metadata(id, profile.ex);
      }
    } catch (_) {
      // A missing profile must never prevent opening an ordinary SDK chat.
    }
    return const OfficialConversationResolution(
        OfficialConversationTarget.chat);
  }

  Future<OfficialConversationResolution> resolveConversation(
      ConversationInfo conversation) async {
    if (conversation.conversationType != ConversationType.single) {
      return const OfficialConversationResolution(
          OfficialConversationTarget.chat);
    }
    return resolveUser(userID: conversation.userID ?? '', ex: conversation.ex);
  }

  Future<bool> usesOfficialPage(ConversationInfo conversation) async =>
      (await resolveConversation(conversation)).target !=
      OfficialConversationTarget.chat;
}
