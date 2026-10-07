import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/services/realtime/sangong_state_event.dart';
import '../../sangong_test_support.dart';

void main() {
  test(
      'requires authenticated bot, persisted identity and matching scope/version',
      () {
    final event = sangongMessageEvent(3);
    for (final invalid in [
      {...event, 'senderID': 'player'},
      {...event, 'groupID': 'other'},
      {...event, 'serverMsgID': ''},
      {...event, 'seq': 0},
      sangongMessageEvent(3, state: {...sangongState(3), 'groupId': 'other'}),
      sangongMessageEvent(3, state: sangongState(4)),
      sangongMessageEvent(3, state: {...sangongState(3), 'settings': null}),
      sangongMessageEvent(1),
    ]) {
      expect(
          readSangongStateEvent(invalid,
              groupID: 'group-sangong',
              botUserID: 'bot-sangong',
              currentVersion: 1),
          isNull);
    }
    expect(
        readSangongStateEvent(event,
            groupID: 'group-sangong', botUserID: '', currentVersion: 1),
        isNull);
    final accepted = readSangongStateEvent(event,
        groupID: 'group-sangong', botUserID: 'bot-sangong', currentVersion: 1)!;
    expect(accepted.version, 3);
    // Go reserves accepted stakes immediately, including while betting is open.
    expect(accepted.toGroupGameRoundStatus().totalBetCount, 300);
  });
}
