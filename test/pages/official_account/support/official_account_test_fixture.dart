import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/official_account/models/official_account.dart';

import '../../ai_assistant/openim/support/ai_openim_test_fixture.dart';

String officialConversationID(String userID) =>
    'si_${([userID, 'self']..sort()).join('_')}';

Message officialText(String id, String text,
        {required String userID, int time = 1, bool outgoing = false}) =>
    aiOpenimText(id, text, time: time, outgoing: outgoing)
      ..sendID = outgoing ? 'self' : userID
      ..recvID = outgoing ? userID : 'self'
      ..senderNickname = outgoing ? '我' : userID;

/// Reuses the SDK boundary and its owner cleanup; only route identity differs.
class OfficialAccountTestFixture extends AiOpenimTestFixture {
  ChatLogic openOfficial({
    required OfficialAccountRole role,
    String? userID,
    String? draft,
  }) {
    final id = userID ??
        (role == OfficialAccountRole.pay
            ? OfficialAccount.payUserID
            : OfficialAccount.messageUserID);
    final account = OfficialAccount(userID: id, role: role);
    Get.routing.args = {
      'conversationInfo': ConversationInfo(
        conversationID: officialConversationID(id),
        userID: id,
        conversationType: ConversationType.single,
        showName: account.displayName,
        unreadCount: 1,
        groupAtType: GroupAtType.atNormal,
        isPrivateChat: false,
        draftText: draft,
        ex: jsonEncode({
          'accountType': 'official',
          'officialRole': role.name,
        }),
      ),
      'officialAccount': account,
    };
    final logic = ChatLogic();
    controllers.add(logic);
    logic.onInit();
    return logic;
  }
}
