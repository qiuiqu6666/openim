import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Read the same committed identity as contacts, without fetching on build or
/// mutating SDK conversation snapshots. Group/system names remain SDK-owned.
String conversationDisplayName(ConversationInfo info) {
  if (info.isSingleChat) {
    final source = ContactRemarkSource.current;
    if (source is ContactDisplayNameSource) {
      final name = (source as ContactDisplayNameSource)
          .friendDisplayNameFor(info.userID);
      if (name != null) return name;
    }
    final remark = source?.remarkFor(info.userID);
    if (remark != null && remark.trim().isNotEmpty) return remark.trim();
  }
  return ContactRemarkSource.nameFromValues(info.userID,
      nickname: info.showName);
}
