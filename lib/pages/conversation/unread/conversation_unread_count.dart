import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// The navigation badge represents unread messages that can notify the user.
/// A missing receive option has the SDK's default (normal reception) meaning.
int notifiableConversationUnreadCount(ConversationInfo info,
    {int? unreadCount}) {
  if ((info.recvMsgOpt ?? 0) != 0) return 0;
  final count = unreadCount ?? info.unreadCount;
  return count > 0 ? count : 0;
}

/// Optional scope and archive filters apply the notification rule to each tab
/// while retaining the controller's current read projection.
int sumNotifiableConversationUnread(Iterable<ConversationInfo> rows,
    {bool? groupChats,
    bool Function(ConversationInfo)? isArchived,
    int Function(ConversationInfo)? unreadCountFor}) {
  var sum = 0;
  for (final info in rows) {
    if (groupChats != null &&
        !(groupChats ? info.isGroupChat : info.isSingleChat)) {
      continue;
    }
    if (isArchived?.call(info) ?? false) continue;
    sum += notifiableConversationUnreadCount(info,
        unreadCount: unreadCountFor?.call(info));
  }
  return sum;
}

/// OpenIM's SDK total uses its database rule, which differs from UI badges:
/// receive options below 2 and a positive latest-message timestamp are counted,
/// including rejected-message rows, archives, and every conversation type.
int sumSdkConversationUnread(Iterable<ConversationInfo> rows) {
  var sum = 0;
  for (final info in rows) {
    if ((info.recvMsgOpt ?? 0) >= 2 || (info.latestMsgSendTime ?? 0) <= 0) {
      continue;
    }
    if (info.unreadCount > 0) sum += info.unreadCount;
  }
  return sum;
}
