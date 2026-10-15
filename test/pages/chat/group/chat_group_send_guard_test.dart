import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/chat_delivery_controller.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

import 'support/chat_group_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final departure in ['left', 'removed', 'server', 'pending']) {
    testWidgets('$departure blocks new sends, retry and explicit group sends',
        (tester) async {
      var joined = true;
      final pending = Completer<bool>();
      final h = ChatGroupHarness(
        isJoined: (_) async => joined,
        verifyMembership: (_, __) =>
            departure == 'pending' ? pending.future : Future.value(false),
      );
      h.controller.initialize();
      await h.controller.loadAfterHistory();
      var calls = 0;
      var resets = 0;
      final delivery = ChatDeliveryController(
        accountID: 'me',
        currentAccountID: () => 'me',
        messageList: h.messages,
        conversation: () => ConversationInfo(
            conversationID: 'sg_group', groupID: 'group', conversationType: 3),
        isClosed: () => false,
        groupStatus: () => null,
        scrollBottom: () {},
        resetInput: (_) => resets++,
        canSendToGroup: (id) =>
            id != h.groupID ||
            (!h.controller.sendingMuted && !h.controller.isInvalidGroup),
        sendRaw: (message, _) async {
          calls++;
          return message;
        },
      );
      addTearDown(delivery.close);
      switch (departure) {
        case 'left':
          h.left.add(GroupInfo(groupID: 'group'));
        case 'removed':
          h.deleted.add(GroupMembersInfo(groupID: 'group', userID: 'me'));
        case 'server':
          joined = false;
          await h.controller.loadAfterHistory();
        case 'pending':
          joined = false;
          unawaited(h.controller.loadAfterHistory());
          await tester.pump();
      }
      for (final explicit in [false, true]) {
        FavoriteSendResult? result;
        await delivery.send(Message(clientMsgID: 'blocked-$explicit'),
            groupId: explicit ? 'group' : null,
            favoriteResult: (value) => result = value);
        expect(result?.status, FavoriteSendStatus.failed);
      }
      expect(calls, 0);
      expect(resets, 0);
      expect(h.messages, isEmpty);
      h.controller.recover(resetAttempts: true);
      await tester.pump();
      expect(h.controller.isInvalidGroup, departure != 'pending');
      expect(calls, 0);
      h.controller.close();
      if (!pending.isCompleted) pending.complete(false);
    });
  }
}
