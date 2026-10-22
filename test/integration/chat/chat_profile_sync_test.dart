import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../../support/chat/chat_recovery_fixture.dart';

void main() {
  recoveryScenario('conversation profile updates the open single chat',
      (tester, fixture) async {
    final logic = await fixture.open(tester);
    fixture.im.conversationChanged([
      fixture.conversation()
        ..showName = 'New name'
        ..faceURL = 'new-avatar',
    ]);
    await tester.pump();
    expect(logic.nickname.value, 'New name');
    expect(logic.faceUrl.value, 'new-avatar');
    final oldMessage = recoveryMessage('older-page', 0)
      ..senderFaceUrl = 'stale-avatar';
    expect(logic.getNewestFaceURL(oldMessage), 'new-avatar');

    fixture.im.conversationChanged([
      fixture.conversation()
        ..showName = 'Latest name'
        ..faceURL = '',
    ]);
    await tester.pump();
    expect(logic.nickname.value, 'Latest name');
    expect(logic.faceUrl.value, '');
    expect(logic.getNewestFaceURL(oldMessage), '');
    expect(
        logic.getNewestFaceURL(
            Message(sendID: 'self', senderFaceUrl: 'self-avatar')),
        'self-avatar');
  });

  recoveryScenario('friend remark stays ahead of personal nickname',
      (tester, fixture) async {
    final logic = await fixture.open(tester);
    fixture.im.friendInfoChanged(FriendInfo(
        userID: 'peer',
        nickname: 'New personal name',
        remark: 'My remark',
        faceURL: 'new-avatar'));
    await tester.pump();
    expect(logic.nickname.value, 'My remark');
    expect(logic.faceUrl.value, 'new-avatar');
    expect(logic.messageList.first.senderNickname, 'New personal name');
  });

  recoveryScenario(
      'unrelated and disposed chat updates cannot replace identity',
      (tester, fixture) async {
    final logic = await fixture.open(tester);
    fixture.im.conversationChanged([
      ConversationInfo(
          conversationID: 'other', showName: 'Other user', faceURL: 'other'),
    ]);
    await tester.pump();
    expect(logic.nickname.value, 'Peer');
    logic.onDelete();
    fixture.im.conversationChanged([
      fixture.conversation()
        ..showName = 'Late update'
        ..faceURL = 'late',
    ]);
    await tester.pump();
    expect(logic.nickname.value, 'Peer');
  });
}
