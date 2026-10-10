import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/push/apns/apns_notification_target.dart';

void main() {
  const account = 'im_current';
  final payload = <String, dynamic>{
    'accountID': account,
    'conversationID': 'sg_@group',
    'sourceID': '@group',
    'sessionType': 3,
    'clientMsgID': 'msg-1',
  };
  Map<String, dynamic> actual({int type = 1, String message = 'real-msg'}) => {
        'openimAPNS': true,
        'accountID': account,
        'clientMsgID': message,
        'ex': jsonEncode({
          'version': 1,
          'type': 'chat_message',
          'sessionType': type,
          'sendID': '@sender_exact',
          'groupID': type == 1 ? '' : '@group_exact',
        }),
      };

  test('OpenIM private payload uses exact sender and captured client session',
      () {
    final body = actual()..['sessionKey'] = 'server-cannot-supply-session';
    final before = jsonEncode(body);
    final target = apnsNotificationTarget(body,
        accountID: account, sessionKey: 'captured-session')!;
    expect(target.sourceID, '@sender_exact');
    expect(target.sessionType, 1);
    expect(target.messageID, 'real-msg');
    expect(target.sessionKey, 'captured-session');
    expect(target.conversationID, isNull);
    expect(jsonEncode(body), before);
    final resolved = target.resolve(ConversationInfo(
        conversationID: 'sdk-real-conversation',
        conversationType: 1,
        userID: '@sender_exact'));
    expect(resolved?.conversationID, 'sdk-real-conversation');
    expect(resolved?.sessionKey, 'captured-session');
  });

  for (final type in [2, 3]) {
    test('OpenIM group type $type uses groupID rather than sender', () {
      final target = apnsNotificationTarget(actual(type: type),
          accountID: account, sessionKey: 'session')!;
      expect(target.sourceID, '@group_exact');
      expect(target.sessionType, type);
      expect(
          target.resolve(ConversationInfo(
              conversationID: 'sdk-group',
              conversationType: type,
              groupID: '@group_exact')),
          isNotNull);
    });
  }

  test('SDK destination must match actual type/source and contain a real ID',
      () {
    final target = apnsNotificationTarget(actual(),
        accountID: account, sessionKey: 'session')!;
    for (final conversation in [
      ConversationInfo(
          conversationID: '', conversationType: 1, userID: '@sender_exact'),
      ConversationInfo(
          conversationID: 'sdk', conversationType: 1, userID: 'different'),
      ConversationInfo(
          conversationID: 'sdk', conversationType: 3, groupID: '@sender_exact'),
      ConversationInfo(
          conversationID: 'sdk',
          conversationType: 1,
          userID: '@sender_exact',
          groupID: 'unexpected-group'),
    ]) {
      expect(target.resolve(conversation), isNull);
    }
  });

  test('actual account is top-level; ex identities cannot authorize a tap', () {
    for (final owner in [null, '', 'other']) {
      final body = actual()..['accountID'] = owner;
      final ex = jsonDecode(body['ex'] as String) as Map<String, dynamic>;
      body['ex'] =
          jsonEncode({...ex, 'accountID': account, 'recipientUserID': account});
      body['recipientUserID'] = account;
      expect(
          apnsNotificationTarget(body,
              accountID: account, sessionKey: 'session'),
          isNull);
      expect(
          apnsNotificationBelongsToAccount(body, accountID: account), isFalse);
    }
  });

  test('fallback recipient check works without a route but rejects old account',
      () {
    expect(
        apnsNotificationBelongsToAccount(actual()..remove('ex'),
            accountID: account),
        isTrue);
    expect(
        apnsNotificationBelongsToAccount({...actual(), 'ex': '{invalid'},
            accountID: account),
        isTrue);
    expect(
        apnsNotificationBelongsToAccount({...actual(), 'accountID': 'other'},
            accountID: account),
        isFalse);
    expect(
        apnsNotificationBelongsToAccount({'ex': '{invalid'},
            accountID: account),
        isFalse);
  });

  test('missing ex without a canonical destination leaves app landing intact',
      () {
    for (final body in [
      actual()..remove('ex'),
      {'openimAPNS': true, 'accountID': account, 'clientMsgID': 'old-msg'},
    ]) {
      expect(
          apnsNotificationTarget(body,
              accountID: account, sessionKey: 'session'),
          isNull);
    }
  });

  test('unsupported/malformed ex never falls back to canonical fields', () {
    for (final ex in [null, '', '{invalid', '[]', 'null', {}, true]) {
      expect(
          apnsNotificationTarget({...payload, 'ex': ex},
              accountID: account, sessionKey: 'session'),
          isNull);
    }
    final base = jsonDecode(actual()['ex'] as String) as Map<String, dynamic>;
    for (final change in [
      {'version': 2},
      {'version': 1.0},
      {'version': '1'},
      {'type': 'call'},
      {'type': null},
      {'sessionType': '1'},
      {'sessionType': 1.0},
      {'sessionType': 4},
      {'sendID': null},
      {'sendID': ''},
      {'sendID': ' sender '},
      {'sendID': account},
      {'groupID': null},
      {'groupID': 'unexpected'},
    ]) {
      expect(
          apnsNotificationTarget({
            ...actual(),
            'ex': jsonEncode({...base, ...change})
          }, accountID: account, sessionKey: 'session'),
          isNull);
    }
  });

  test('group ex requires exact group and sender IDs', () {
    final base =
        jsonDecode(actual(type: 3)['ex'] as String) as Map<String, dynamic>;
    for (final change in [
      {'groupID': ''},
      {'groupID': ' group '},
      {'groupID': 4},
      {'sendID': null},
      {'sendID': ''},
    ]) {
      expect(
          apnsNotificationTarget({
            ...actual(type: 3),
            'ex': jsonEncode({...base, ...change})
          }, accountID: account, sessionKey: 'session'),
          isNull);
    }
  });

  test('actual client message ID and captured session are strict', () {
    for (final message in [null, '', ' message ', 1]) {
      expect(
          apnsNotificationTarget({...actual(), 'clientMsgID': message},
              accountID: account, sessionKey: 'session'),
          isNull);
    }
    for (final session in ['', ' session ']) {
      expect(
          apnsNotificationTarget(actual(),
              accountID: account, sessionKey: session),
          isNull);
    }
  });
  test('valid recipient borrows only the currently captured session', () {
    final target = apnsNotificationTarget(payload,
        accountID: account, sessionKey: 'opaque-current-session');
    expect(target?.conversationID, 'sg_@group');
    expect(target?.sessionKey, 'opaque-current-session');
    expect(target?.messageID, 'msg-1');
  });
  test('absent or another recipient cannot navigate in the current account',
      () {
    for (final owner in [null, '', 'im_other']) {
      expect(
          apnsNotificationTarget({...payload, 'accountID': owner},
              accountID: account, sessionKey: 'session'),
          isNull);
    }
  });
  test('group recvID is not treated as an account identity', () {
    expect(
        apnsNotificationTarget(
            {...payload}
              ..remove('accountID')
              ..['recvID'] = '@group',
            accountID: account,
            sessionKey: 'session'),
        isNull);
  });
  test('map and JSON data wrappers preserve recipient checks', () {
    for (final wrapper in [payload, jsonEncode(payload)]) {
      expect(
          apnsNotificationTarget({'data': wrapper},
                  accountID: account, sessionKey: 'session')
              ?.sourceID,
          '@group');
    }
    expect(
        apnsNotificationTarget({'data': '{invalid'},
            accountID: account, sessionKey: 'session'),
        isNull);
  });
  test('malformed types and destinations are rejected', () {
    for (final change in [
      {'sessionType': '3'},
      {'sessionType': 4},
      {'sourceID': ''},
      {'conversationID': ''},
      {'clientMsgID': 1},
    ]) {
      expect(
          apnsNotificationTarget({...payload, ...change},
              accountID: account, sessionKey: 'session'),
          isNull);
    }
  });
}
