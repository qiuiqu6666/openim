import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/cloud/search_sender_profiles.dart';

void main() {
  test('batches distinct senders and reuses in-flight and cached profiles',
      () async {
    final response = Completer<List<PublicUserInfo>>();
    var calls = 0;
    final profiles = SearchSenderProfiles(lookup: (ids) {
      calls++;
      expect(ids, ['alice', 'bob']);
      return response.future;
    });
    final messages = [
      Message(sendID: 'alice'),
      Message(sendID: 'alice'),
      Message(sendID: 'bob')
    ];
    final first = profiles.enrich(messages, isCurrent: () => true);
    final next = Message(sendID: 'alice');
    final second = profiles.enrich([next], isCurrent: () => true);
    response.complete([
      PublicUserInfo(
          userID: 'alice',
          nickname: '小木',
          faceURL: 'https://example.com/a.png'),
      PublicUserInfo(userID: 'bob', nickname: '小李'),
    ]);
    await Future.wait([first, second]);
    expect(messages.first.senderNickname, '小木');
    expect(messages[1].senderFaceUrl, 'https://example.com/a.png');
    expect(messages.last.senderNickname, '小李');
    expect(next.senderNickname, '小木');
    await profiles.enrich([Message(sendID: 'alice')], isCurrent: () => true);
    expect(calls, 1);
  });

  test('late profile responses cannot update invalidated results', () async {
    final response = Completer<List<PublicUserInfo>>();
    final profiles = SearchSenderProfiles(lookup: (_) => response.future);
    final message = Message(sendID: 'alice');
    var current = true;
    final pending = profiles.enrich([message], isCurrent: () => current);
    current = false;
    response.complete([PublicUserInfo(userID: 'alice', nickname: '小木')]);
    await pending;
    expect(message.senderNickname, isNull);
  });

  test('profile failure preserves messages and can retry', () async {
    var calls = 0;
    final profiles = SearchSenderProfiles(lookup: (_) async {
      if (++calls == 1) throw StateError('unavailable');
      return [PublicUserInfo(userID: 'alice', nickname: '小木')];
    });
    final message = Message(sendID: 'alice', clientMsgID: 'hit');
    await profiles.enrich([message], isCurrent: () => true);
    expect(message.clientMsgID, 'hit');
    await profiles.enrich([message], isCurrent: () => true);
    expect(message.senderNickname, '小木');
  });
}
