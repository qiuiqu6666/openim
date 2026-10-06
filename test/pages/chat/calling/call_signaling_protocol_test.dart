import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/src/signaling/call_record_snapshot.dart';
import 'package:openim_live/src/signaling/call_signaling_protocol.dart';

void main() {
  const start = 1791158400123;
  final end = DateTime.fromMillisecondsSinceEpoch(start + 30000);

  InvitationInfo invitation({int? time = start}) => InvitationInfo(
        inviterUserID: 'caller',
        inviteeUserIDList: ['callee'],
        roomID: 'shared-call_2026',
        mediaType: 'audio',
        sessionType: ConversationType.single,
        timeout: 30,
        initiateTime: time,
      );

  Message signal(int type,
          {String? reason, int? time = start, String? sender, int? sendTime}) =>
      Message(
        sendID: sender ??
            (type == CustomMessageType.callingReject ? 'callee' : 'caller'),
        sendTime: sendTime,
        customElem: CustomElem(
            data: encodeCallSignal(type, invitation(time: time),
                terminalState: reason)),
      );

  test('malformed or forged online signals never enter the call runtime', () {
    for (final raw in ['{', '[]', 'null', '{"customType":200,"data":[]}']) {
      expect(
          decodeCallSignal(
              Message(sendID: 'caller', customElem: CustomElem(data: raw))),
          isNull);
    }
    for (final invalid in [
      invitation()..mediaType = 'unknown',
      invitation()..roomID = '',
      invitation()..inviteeUserIDList = ['caller'],
      invitation()..inviteeUserIDList = ['callee', 'third'],
    ]) {
      expect(
          decodeCallSignal(Message(
              sendID: 'caller',
              customElem: CustomElem(
                  data: encodeCallSignal(
                      CustomMessageType.callingInvite, invalid)))),
          isNull);
    }
    expect(
        decodeCallSignal(
            signal(CustomMessageType.callingAccept, sender: 'caller')),
        isNull);
    expect(
        decodeCallSignal(
            signal(CustomMessageType.callingCancel, sender: 'callee')),
        isNull);
    expect(
        decodeCallSignal(
            signal(CustomMessageType.callingHungup, sender: 'stranger')),
        isNull);
    expect(
        decodeCallSignal(
            signal(CustomMessageType.callingAccept, sender: 'callee')),
        isNotNull);
  });

  test('room tombstones reject duplicates until the account changes', () {
    final guard = CallSignalGuard();
    expect(guard.begin('room-123456', 'caller'), true);
    expect(guard.begin('room-987654', 'caller'), false);
    expect(guard.matches('stale-room', 'caller'), false);
    expect(guard.finish('room-123456', 'caller'), true);
    expect(guard.finish('room-123456', 'caller'), false);
    guard.release('room-123456');
    expect(guard.begin('room-123456', 'caller'), false);
    expect(guard.begin('room-123456', 'other-account'), true);
    expect(guard.matches('room-123456', 'caller'), false);
  });

  test(
      'caller and callee share call ID, start and participants through SDK signal',
      () {
    final decoded = decodeCallSignal(
        signal(CustomMessageType.callingInvite, sendTime: start + 700));
    expect(decoded, isNotNull);
    final views = ['caller', 'callee']
        .map((owner) => buildCallRecord(
            signaling: decoded!.info,
            accountID: owner,
            state: 'hangup',
            duration: 20,
            connected: true,
            endedAt: end))
        .toList();
    expect(views.map((record) => record.callID),
        ['shared-call_2026', 'shared-call_2026']);
    expect(views.map((record) => record.startedAt), [start, start]);
    expect(
        views.map((record) => record.endedAt), [start + 30000, start + 30000]);
    expect(views.map((record) => record.incomingCall), [false, true]);
    expect(views.map((record) => record.userID), ['callee', 'caller']);
    for (final record in views) {
      expect(record.participantUserIDs, ['caller', 'callee']);
      expect(record.status, 'completed');
    }
  });

  test(
      'legacy second timestamps normalize and missing start uses original send time',
      () {
    final seconds = start ~/ 1000;
    final legacy = decodeCallSignal(signal(CustomMessageType.callingInvite,
        time: seconds, sendTime: seconds + 2))!;
    expect(legacy.info.invitation!.initiateTime, seconds * 1000);
    final absent = decodeCallSignal(signal(CustomMessageType.callingInvite,
        time: null, sendTime: seconds))!;
    expect(absent.info.invitation!.initiateTime, seconds * 1000);
    expect(callInviteDeadline(absent.info.invitation)!.millisecondsSinceEpoch,
        seconds * 1000 + 30000);
  });

  test(
      'callee timeout reports missed while ordinary reject keeps legacy direction',
      () {
    final timeout = decodeCallSignal(
        signal(CustomMessageType.callingReject, reason: 'timeout'))!;
    final record = buildCallRecord(
        signaling: timeout.info,
        accountID: 'caller',
        state: 'beRejected',
        duration: 0,
        connected: false,
        endedAt: end);
    expect(record.state, 'timeout');
    expect(record.status, 'missed');
    final rejected = decodeCallSignal(
        signal(CustomMessageType.callingReject, reason: 'reject'))!;
    expect(callTerminalRecordState(rejected.info, 'beRejected'), 'beRejected');
    final cancelled = decodeCallSignal(
        signal(CustomMessageType.callingCancel, reason: 'cancel'))!;
    final incoming = buildCallRecord(
        signaling: cancelled.info,
        accountID: 'callee',
        state: 'beCanceled',
        duration: 0,
        connected: false,
        endedAt: end);
    expect(incoming.isMissed, isTrue);
  });

  test(
      'invalid or incompatible terminal reasons cannot override a valid signal',
      () {
    for (final value in [
      'completed',
      'hangup',
      '',
      3,
      {'state': 'timeout'}
    ]) {
      final message = signal(CustomMessageType.callingReject);
      final data =
          jsonDecode(message.customElem!.data!) as Map<String, dynamic>;
      (data['data'] as Map<String, dynamic>)['terminalState'] = value;
      message.customElem!.data = jsonEncode(data);
      final decoded = decodeCallSignal(message)!;
      expect(callTerminalRecordState(decoded.info, 'beRejected'), 'beRejected');
    }
    final invite = signal(CustomMessageType.callingInvite, reason: 'timeout');
    final wire = jsonDecode(invite.customElem!.data!) as Map<String, dynamic>;
    expect((wire['data'] as Map).containsKey('terminalState'), isFalse);
    expect(
        decodeCallSignal(signal(CustomMessageType.callingReject,
            reason: 'timeout', sender: 'stranger')),
        isNull);
  });

  test('new call IDs meet server bounds while decoder retains legacy room IDs',
      () {
    for (final id in ['12345678', 'shared-call_2026', 'a' * 64]) {
      expect(validCallID(id), isTrue);
    }
    for (final id in [null, '', '1234567', 'a' * 65, 'room:bad', ' room-01']) {
      expect(validCallID(id), isFalse);
    }
    final old = invitation()..roomID = 'legacy';
    expect(validCallInvitation(old), isTrue);
  });

  test(
      'group snapshot carries group ID and unique participants without enabling RTC',
      () {
    final group = invitation()
      ..sessionType = ConversationType.group
      ..groupID = 'group-1'
      ..inviteeUserIDList = ['callee', 'third', 'callee'];
    final record = buildCallRecord(
        signaling: SignalingInfo(invitation: group),
        accountID: 'caller',
        state: 'cancel',
        duration: 99,
        connected: false,
        endedAt: end);
    expect(record.roomType, 'group');
    expect(record.groupID, 'group-1');
    expect(record.participantUserIDs, ['caller', 'callee', 'third']);
    expect(record.duration, 0);
    expect(record.status, 'cancelled');
  });

  test(
      'connected network loss retains talk duration and zero-second answer is completed',
      () {
    for (final duration in [0, 20]) {
      final record = buildCallRecord(
          signaling: SignalingInfo(invitation: invitation()),
          accountID: 'caller',
          state: 'networkError',
          duration: duration,
          connected: true,
          endedAt: end);
      expect(record.duration, duration);
      expect(record.success, isTrue);
      expect(record.status, 'completed');
    }
  });
}
