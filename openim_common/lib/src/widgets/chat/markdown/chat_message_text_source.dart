import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Bubble text keeps line breaks; conversation summaries still use parseMsg.
/// Mention names are a display adaptation and never mutate the SDK message.
String chatMessageTextSource(Message message) {
  if (message.hasExpired) return IMUtils.parseMsg(message);
  switch (message.contentType) {
    case MessageType.text:
      return message.textElem?.content ?? '';
    case MessageType.quote:
      return message.quoteElem?.text ?? '';
    case MessageType.advancedText:
      return message.advancedTextElem?.text ?? '';
    case MessageType.atText:
      var text = message.atTextElem?.text ?? '';
      final members = [...?message.atTextElem?.atUsersInfo]..sort((a, b) =>
          (b.atUserID?.length ?? 0).compareTo(a.atUserID?.length ?? 0));
      for (final member in members) {
        final id = member.atUserID;
        final name = member.groupNickname;
        if (id != null && id.isNotEmpty && name != null) {
          text = text.replaceAll('@$id', '@${IMUtils.getAtNickname(id, name)}');
        }
      }
      return text.replaceAll('@atAllTag', '@${StrRes.everyone}');
    default:
      return IMUtils.parseMsg(message);
  }
}
