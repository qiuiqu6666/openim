import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../pages/contacts/select_contacts/select_contacts_logic.dart';
import '../../routes/app_navigator.dart';
import '../chat_message_sender.dart';
import '../favorite_send_coordinator.dart';
import 'message_send_session.dart';

/// Reuses the recipient picker and account-bound message sender.
Future<int> shareBrowserLink(Uri uri, String? title) async {
  final session = MessageSendSession.capture();
  final name = title?.trim() ?? '';
  final text = name.isEmpty ? uri.toString() : '$name\n$uri';
  final result = await AppNavigator.startSelectContacts(
      action: SelAction.forward, ex: text);
  if (result == null || !session.current) return 0;
  final targets = result['checkedList'];
  if (targets is! Iterable) return 0;
  var sent = 0;
  for (final target in targets) {
    session.check();
    final message =
        await OpenIM.iMManager.messageManager.createTextMessage(text: text);
    session.check();
    await ChatMessageSender().sendRaw(
        message,
        FavoriteTarget(
          conversationID: '',
          userID: IMUtils.convertCheckedToUserID(target),
          groupID: IMUtils.convertCheckedToGroupID(target),
          sessionType: APNsOfflinePushInfo.sessionTypeForSelection(target),
        ));
    sent++;
  }
  return session.current ? sent : 0;
}
