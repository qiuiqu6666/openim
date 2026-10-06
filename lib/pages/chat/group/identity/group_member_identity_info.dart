import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// A group response keeps the SDK routing ID and optional public account separate.
class GroupMemberIdentityInfo extends GroupMembersInfo {
  GroupMemberIdentityInfo({
    super.groupID,
    super.userID,
    super.roleLevel,
    super.joinTime,
    super.nickname,
    super.faceURL,
    super.ex,
    super.joinSource,
    super.operatorUserID,
    super.muteEndTime,
    super.appManagerLevel,
    super.inviterUserID,
    this.account,
  });

  GroupMemberIdentityInfo.fromJson(Map<String, dynamic> json)
      : super.fromJson(json) {
    final value = json['account'];
    account = value is String && value.trim().isNotEmpty ? value : null;
  }

  /// Only the group endpoint may supply this field under its current permissions.
  String? account;

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (account?.trim().isNotEmpty == true) 'account': account,
      };
}
