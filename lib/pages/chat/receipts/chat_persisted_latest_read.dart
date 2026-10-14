import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Loading older history does not invalidate an already painted SDK latest.
/// This only relaxes the loading gate; the receipt owner still checks actual
/// visibility, route, lifecycle, animations and the latest conversation target.
bool canReadPersistedLatestDuringLoad(
    ConversationInfo conversation, Message? latest) {
  final preview = conversation.latestMsg;
  return conversation.isPrivateChat != true &&
      latest != null &&
      preview != null &&
      latest.clientMsgID?.isNotEmpty == true &&
      latest.clientMsgID == preview.clientMsgID &&
      (latest.seq ?? 0) > 0 &&
      latest.seq == preview.seq &&
      latest.status == MessageStatus.succeeded &&
      preview.status == MessageStatus.succeeded &&
      latest.attachedInfoElem?.isPrivateChat != true &&
      preview.attachedInfoElem?.isPrivateChat != true;
}
