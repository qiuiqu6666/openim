import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/calling/ios/ios_call_invitation.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  const account = '@callee_sdk_id';
  const caller = '@caller_sdk_id';
  const start = 1791676800000;
  final now = DateTime.fromMillisecondsSinceEpoch(start + 1000);

  Map<String, dynamic> canonical() => {
        'recipientUserID': account,
        'callerName': '来电好友',
        'invitation': InvitationInfo(
          roomID: 'room-shared_2026',
          inviterUserID: caller,
          inviteeUserIDList: [account],
          mediaType: 'audio',
          sessionType: ConversationType.single,
          initiateTime: start,
          timeout: 30,
          platformID: 1,
        ).toJson(),
      };

  Map<String, dynamic> native() => {
        'callerId': caller,
        'calleeId': account,
        'roomId': 'room-shared_2026',
        'callId': 'different-call-id',
        'callerName': '来电好友',
        'mediaType': 'video',
        'initiateTime': start,
        'timeoutSec': 30,
      };

  IOSCallInvitation? decode(Object? raw, {DateTime? clock}) =>
      IOSCallInvitation.decode(raw, accountID: account, now: clock ?? now);

  test('canonical SDK invitation retains exact account, room and call fields',
      () {
    final model = decode(canonical())!;
    expect(model.accountID, account);
    expect(model.roomID, 'room-shared_2026');
    expect(model.callerName, '来电好友');
    expect(model.invitation.inviterUserID, caller);
    expect(model.invitation.inviteeUserIDList, [account]);
    expect(model.invitation.sessionType, ConversationType.single);
    expect(model.invitation.mediaType, 'audio');
    expect(model.invitation.initiateTime, start);
    expect(model.invitation.timeout, 30);
    expect(model.invitation.platformID, 1);
    expect(model.expiresAt.millisecondsSinceEpoch, start + 30000);
  });

  test('accepts JSON payloads and data Map or JSON envelopes', () {
    final body = canonical();
    for (final raw in [
      jsonEncode(body),
      {'data': body},
      {'data': jsonEncode(body)},
      jsonEncode({'data': body}),
      {
        'data': {'data': jsonEncode(body)}
      },
    ]) {
      expect(decode(raw)?.roomID, 'room-shared_2026');
    }
  });

  test('missing or mismatched recipient never inherits the current account',
      () {
    for (final recipient in [
      null,
      '',
      'callee_sdk_id',
      ' $account',
      'other',
      1
    ]) {
      final body = canonical()..['recipientUserID'] = recipient;
      expect(decode(body), isNull);
    }
    expect(decode(canonical()..remove('recipientUserID')), isNull);
    expect(
        IOSCallInvitation.decode(canonical(), accountID: '', now: now), isNull);
    expect(
        IOSCallInvitation.decode(canonical(), accountID: ' $account', now: now),
        isNull);
  });

  test('caller must be a different, explicit SDK account', () {
    for (final invalid in [null, '', account, ' $caller', 2]) {
      final body = canonical();
      (body['invitation'] as Map)['inviterUserID'] = invalid;
      expect(decode(body), isNull);
    }
  });

  test('only a unique single-chat callee matching the recipient is accepted',
      () {
    for (final invalid in [
      null,
      [],
      [caller],
      ['other'],
      [account, account],
      [account, 'other'],
      [1],
      account,
    ]) {
      final body = canonical();
      (body['invitation'] as Map)['inviteeUserIDList'] = invalid;
      expect(decode(body), isNull);
    }
    for (final type in [
      null,
      2, // Legacy group conversation type.
      ConversationType.superGroup
    ]) {
      final body = canonical();
      (body['invitation'] as Map)['sessionType'] = type;
      expect(decode(body), isNull);
    }
    final withGroup = canonical();
    (withGroup['invitation'] as Map)['groupID'] = 'group-1';
    expect(decode(withGroup), isNull);
  });

  test('audio and video are the only accepted media', () {
    for (final media in ['audio', 'video']) {
      final body = canonical();
      (body['invitation'] as Map)['mediaType'] = media;
      expect(decode(body)?.invitation.mediaType, media);
    }
    for (final media in [null, '', 'Audio', 'unknown', true]) {
      final body = canonical();
      (body['invitation'] as Map)['mediaType'] = media;
      expect(decode(body), isNull);
    }
  });

  test('room IDs use the existing server-compatible bounds', () {
    for (final room in [
      null,
      '',
      'short',
      'a' * 65,
      'bad:room-id',
      ' room-valid'
    ]) {
      final body = canonical();
      (body['invitation'] as Map)['roomID'] = room;
      expect(decode(body), isNull);
    }
    for (final room in ['12345678', 'a' * 64]) {
      final body = canonical();
      (body['invitation'] as Map)['roomID'] = room;
      expect(decode(body)?.roomID, room);
    }
  });

  test('native caller/callee fields require the original invitation clock', () {
    final model = decode(native())!;
    expect(model.accountID, account);
    expect(model.roomID, 'room-shared_2026');
    expect(model.invitation.inviterUserID, caller);
    expect(model.invitation.inviteeUserIDList, [account]);
    expect(model.invitation.mediaType, 'video');
    expect(model.invitation.initiateTime, start);
    expect(model.invitation.timeout, 30);
    final callOnly = native()..remove('roomId');
    expect(decode(callOnly)?.roomID, 'different-call-id');
    final sentAt = native()
      ..remove('initiateTime')
      ..['sentAtMs'] = start;
    expect(
        decode({'data': jsonEncode(sentAt)})?.invitation.initiateTime, start);
  });

  test('receipt time cannot replace missing native start or timeout', () {
    final body = native()..remove('initiateTime');
    body['_receivedAtMs'] = now.millisecondsSinceEpoch;
    expect(decode(body), isNull);
    expect(decode(native()..remove('timeoutSec')), isNull);
    expect(decode(native()..remove('calleeId')), isNull);
    expect(decode(native()..['calleeId'] = 'other'), isNull);
    expect(decode(native()..['callerId'] = account), isNull);
  });

  test('real epoch seconds normalize without extending the original deadline',
      () {
    final body = canonical();
    (body['invitation'] as Map)['initiateTime'] = start ~/ 1000;
    final model = decode(body)!;
    expect(model.invitation.initiateTime, start);
    expect(model.expiresAt.millisecondsSinceEpoch, start + 30000);
    expect(
        model.isExpired(
            now: DateTime.fromMillisecondsSinceEpoch(start + 29999)),
        isFalse);
    expect(
        model.isExpired(
            now: DateTime.fromMillisecondsSinceEpoch(start + 30000)),
        isTrue);
    expect(
        decode(body, clock: DateTime.fromMillisecondsSinceEpoch(start + 30000)),
        isNull);
    expect(
        decode(body, clock: DateTime.fromMillisecondsSinceEpoch(start + 31000)),
        isNull);
  });

  test('missing and invalid clocks are rejected without inventing now', () {
    for (final time in [null, 0, -1, '1791676800000', true, 1.5]) {
      final body = canonical();
      (body['invitation'] as Map)['initiateTime'] = time;
      expect(decode(body), isNull);
    }
  });

  test('future invitation clocks have a bounded five-second allowance', () {
    final boundary = now.millisecondsSinceEpoch +
        IOSCallInvitation.maxFutureSkew.inMilliseconds;
    final accepted = canonical();
    (accepted['invitation'] as Map)['initiateTime'] = boundary;
    expect(decode(accepted)?.invitation.initiateTime, boundary);
    final rejected = canonical();
    (rejected['invitation'] as Map)['initiateTime'] = boundary + 1;
    expect(decode(rejected), isNull);
  });

  test('timeout must be explicitly within one to 120 seconds', () {
    for (final timeout in [null, 0, -1, 121, '30', true, 30.5]) {
      final body = canonical();
      (body['invitation'] as Map)['timeout'] = timeout;
      expect(decode(body), isNull);
    }
    for (final timeout in [1, 120]) {
      final body = canonical();
      (body['invitation'] as Map)['timeout'] = timeout;
      expect(
          decode(body, clock: DateTime.fromMillisecondsSinceEpoch(start))
              ?.invitation
              .timeout,
          timeout);
    }
  });

  test('terminal pushes cannot reopen an invitation', () {
    for (final action in [
      'cancel',
      'reject',
      'hangup',
      'answered_elsewhere',
      ''
    ]) {
      expect(decode(canonical()..['action'] = action), isNull);
    }
    expect(decode(canonical()..['call_end'] = 1), isNull);
    expect(decode(canonical()..['call_end'] = true), isNull);
    expect(decode(canonical()..['action'] = 'invite'), isNotNull);
  });

  test('invalid payloads and malformed envelopes return null', () {
    for (final body in [
      null,
      '{}',
      '{',
      '[]',
      'null',
      [],
      {1: 'invalid-key'},
      {'data': null},
      {'data': '{'},
      {'data': []},
      canonical()..['invitation'] = [],
    ]) {
      expect(decode(body), isNull);
    }
    final recursive = <String, dynamic>{};
    recursive['data'] = recursive;
    expect(decode(recursive), isNull);
  });

  test('parsed invitation never aliases or mutates the source payload', () {
    final body = canonical();
    final serialized = jsonEncode(body);
    final model = decode(body)!;
    expect(jsonEncode(body), serialized);
    final wire = body['invitation'] as Map;
    (wire['inviteeUserIDList'] as List)[0] = 'other';
    wire['timeout'] = 120;
    expect(model.invitation.inviteeUserIDList, [account]);
    expect(model.invitation.timeout, 30);
    model.invitation.timeout = 120;
    expect(model.expiresAt.millisecondsSinceEpoch, start + 30000);
  });

  test('absent or non-text display name falls back to the verified caller', () {
    for (final name in [null, '', '   ', 2, {}]) {
      expect(decode(canonical()..['callerName'] = name)?.callerName, caller);
    }
  });
}
