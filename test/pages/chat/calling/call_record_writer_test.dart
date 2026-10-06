import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';
import 'package:openim_live/src/signaling/call_record_writer.dart';

class _LiveHarness with OpenIMLive {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> nativeCalls;
  Completer<String>? createGate;
  Completer<String>? sendGate;
  Completer<void>? sendReached;
  bool failCreate = false;

  SignalingInfo invitation() => SignalingInfo(
      userID: 'caller',
      invitation: InvitationInfo(
          inviterUserID: 'caller',
          inviteeUserIDList: ['callee'],
          roomID: 'shared-call_2026',
          mediaType: 'audio',
          sessionType: ConversationType.single,
          initiateTime: DateTime.now().millisecondsSinceEpoch - 10000));

  Map<String, dynamic> args(MethodCall call) =>
      Map<String, dynamic>.from(call.arguments as Map);

  String customResult(MethodCall call) => jsonEncode(Message(
          clientMsgID: 'native-${nativeCalls.length}',
          contentType: MessageType.custom,
          customElem: CustomElem(
              data: args(call)['data'],
              extension: args(call)['extension'],
              description: args(call)['description']))
      .toJson());

  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'callee';
    nativeCalls = [];
    createGate = null;
    sendGate = null;
    sendReached = null;
    failCreate = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      if (call.method == 'createCustomMessage') {
        if (failCreate) throw PlatformException(code: 'STORAGE');
        return createGate?.future ?? customResult(call);
      }
      if (call.method == 'sendMessage') {
        sendReached?.complete();
        return sendGate?.future ?? jsonEncode(args(call)['message']);
      }
      if (call.method == 'insertSingleMessageToLocalStorage') {
        return jsonEncode(args(call)['message']);
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    Get.reset();
  });

  test(
      'report failure leaves SDK local call message and existing direction intact',
      () async {
    final ended = DateTime.now();
    CallRecords? reported;
    final message = await writeCallRecord(
        signaling: invitation(),
        accountID: 'callee',
        state: 'hangup',
        duration: 8,
        connected: true,
        endedAt: ended,
        isCurrentAccount: () => true,
        onRecord: (record, owner) async {
          expect(owner, 'callee');
          reported = record;
          throw StateError('report unavailable');
        });
    expect(reported!.callID, 'shared-call_2026');
    expect(reported!.endedAt, ended.millisecondsSinceEpoch);
    expect(reported!.participantUserIDs, ['caller', 'callee']);
    expect(message, isNotNull);
    final inserted = args(nativeCalls.last);
    expect(inserted['receiverID'], 'callee');
    expect(inserted['senderID'], 'caller');
    final local = inserted['message'] as Map;
    expect(local['status'], 2);
    expect(local['isRead'], isTrue);
    final data = jsonDecode((local['customElem'] as Map)['data']) as Map;
    expect(data['customType'], CustomMessageType.call);
    expect(data['data'], {
      'roomID': 'shared-call_2026',
      'duration': 8,
      'state': 'hangup',
      'type': 'audio'
    });
  });

  test('SDK history failure still preserves the record callback', () async {
    failCreate = true;
    final records = <CallRecords>[];
    final result = await writeCallRecord(
        signaling: invitation(),
        accountID: 'caller',
        state: 'cancel',
        duration: -3,
        connected: false,
        isCurrentAccount: () => true,
        onRecord: (record, _) async => records.add(record));
    expect(result, isNull);
    expect(records.single.duration, 0);
    expect(records.single.incomingCall, isFalse);
    expect(records.single.status, 'cancelled');
  });

  test('account change while storing record prevents later SDK history writes',
      () async {
    final gate = Completer<void>();
    var current = true;
    final pending = writeCallRecord(
        signaling: invitation(),
        accountID: 'callee',
        state: 'reject',
        duration: 0,
        connected: false,
        isCurrentAccount: () => current,
        onRecord: (_, __) => gate.future);
    current = false;
    gate.complete();
    expect(await pending, isNull);
    expect(nativeCalls, isEmpty);
  });

  test('account change while SDK message is prepared prevents insertion',
      () async {
    createGate = Completer<String>();
    var current = true;
    final pending = writeCallRecord(
        signaling: invitation(),
        accountID: 'callee',
        state: 'reject',
        duration: 0,
        connected: false,
        isCurrentAccount: () => current);
    await Future<void>.delayed(Duration.zero);
    current = false;
    createGate!.complete(customResult(nativeCalls.single));
    expect(await pending, isNull);
    expect(nativeCalls.map((call) => call.method), ['createCustomMessage']);
  });

  test(
      'duplicate timeout and reject share one final record and one wire terminal',
      () async {
    final live = _LiveHarness();
    final records = <CallRecords>[];
    final signal = invitation();
    live.onCallRecord = (record, _) async => records.add(record);
    live.receiveNewInvitation(signal);
    sendGate = Completer<String>();
    sendReached = Completer<void>();
    final first = live.onTimeoutCancelled(signal);
    await live.onTapReject(signal);
    await sendReached!.future;
    final beforeResponse = DateTime.now().millisecondsSinceEpoch;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final sent =
        nativeCalls.singleWhere((call) => call.method == 'sendMessage');
    sendGate!.complete(jsonEncode(args(sent)['message']));
    await first;
    expect(records, hasLength(1));
    expect(records.single.endedAt, lessThanOrEqualTo(beforeResponse));
    expect(records.single.state, 'timeout');
    final sentMessage = args(sent)['message'] as Map;
    final wire = jsonDecode((sentMessage['customElem'] as Map)['data']) as Map;
    expect(wire['customType'], CustomMessageType.callingReject);
    expect((wire['data'] as Map)['terminalState'], 'timeout');
    expect((wire['data'] as Map)['roomID'], records.single.callID);
    expect(args(sent)['isOnlineOnly'], isTrue);
    expect(
        nativeCalls.where(
            (call) => call.method == 'insertSingleMessageToLocalStorage'),
        hasLength(1));
    await live.onCloseLive();
  });

  test(
      'session closing invalidates a terminal send before it can report or insert',
      () async {
    final live = _LiveHarness();
    final records = <CallRecords>[];
    final signal = invitation();
    live.onCallRecord = (record, _) async => records.add(record);
    live.receiveNewInvitation(signal);
    createGate = Completer<String>();
    final pending = live.onTapReject(signal);
    await Future<void>.delayed(Duration.zero);
    final created = nativeCalls.single;
    await live.onCloseLive();
    createGate!.complete(customResult(created));
    await pending;
    expect(records, isEmpty);
    expect(nativeCalls.map((call) => call.method), ['createCustomMessage']);
  });
}
