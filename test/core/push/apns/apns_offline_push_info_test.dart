import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  test('single-chat metadata preserves the exact current SDK ID', () {
    final push = APNsOfflinePushInfo.chatMessage(
        sendID: '@sdk_user', sessionType: ConversationType.single);
    expect(jsonDecode(push.ex!), {
      'version': 1,
      'type': 'chat_message',
      'sessionType': 1,
      'sendID': '@sdk_user',
      'groupID': '',
    });
    expect(push.title, '99CHAT');
    expect(push.desc, '你收到了一条新消息');
    expect(push.iOSBadgeCount, isTrue);
    expect(push.iOSPushSound, 'default');
  });

  for (final type in [2, ConversationType.superGroup]) {
    test('SDK group conversation $type preserves the exact group identifier',
        () {
      final push = APNsOfflinePushInfo.chatMessage(
          sendID: '@sender', sessionType: type, groupID: '@下注群');
      final data = jsonDecode(push.ex!) as Map;
      expect(data['sessionType'], type);
      expect(data['sendID'], '@sender');
      expect(data['groupID'], '@下注群');
    });
  }

  test('invalid IDs and inconsistent destination types never produce a target',
      () {
    for (final bad in [
      '',
      ' @owner',
      '@owner ',
      '@own er',
      '@owner\n',
      '@owner\u0000'
    ]) {
      expect(
          () => APNsOfflinePushInfo.chatMessage(
              sendID: bad, sessionType: ConversationType.single),
          throwsFormatException);
      expect(
          () => APNsOfflinePushInfo.chatMessage(
              sendID: '@owner',
              sessionType: ConversationType.superGroup,
              groupID: bad),
          throwsFormatException);
    }
    expect(
        () => APNsOfflinePushInfo.chatMessage(
            sendID: '@owner',
            sessionType: ConversationType.single,
            groupID: '@group'),
        throwsFormatException);
    expect(
        () => APNsOfflinePushInfo.chatMessage(sendID: '@owner', sessionType: 4),
        throwsFormatException);
  });

  test('only known SDK group types resolve to a group conversation', () {
    expect(
        APNsOfflinePushInfo.sessionTypeForGroup(
            GroupInfo(groupID: '@old', groupType: 0)),
        2);
    expect(
        APNsOfflinePushInfo.sessionTypeForGroup(
            GroupInfo(groupID: '@work', groupType: GroupType.work)),
        3);
    expect(
        APNsOfflinePushInfo.sessionTypeForGroup(GroupInfo(groupID: '@unknown')),
        isNull);
    expect(
        APNsOfflinePushInfo.sessionTypeForGroup(
            GroupInfo(groupID: '@unknown', groupType: 99)),
        isNull);
  });

  test('generic fallback has no guessed conversation or message body', () {
    final first = APNsOfflinePushInfo.generic()..ex = 'private';
    final push = APNsOfflinePushInfo.generic();
    expect(push.ex, isNull);
    expect(push.title, '99CHAT');
    expect(push.desc, '你收到了一条新消息');
    expect(identical(first, push), isFalse);
  });
}
