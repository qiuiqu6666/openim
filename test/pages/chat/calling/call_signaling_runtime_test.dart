import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';

class _Live extends Object with OpenIMLive {}

SignalingInfo _signal(String room,
        {String inviter = 'alice',
        String invitee = 'bob',
        int sessionType = 1,
        String? actor}) =>
    SignalingInfo(
        userID: actor ?? inviter,
        invitation: InvitationInfo(
            roomID: room,
            inviterUserID: inviter,
            inviteeUserIDList: [invitee],
            mediaType: 'audio',
            sessionType: sessionType,
            timeout: 30,
            initiateTime: DateTime.now().millisecondsSinceEpoch));

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late _Live live;
  late List<MethodCall> native;
  late List<(CallRecords, String)> records;
  late List<CallEvent> received;
  late StreamSubscription<CallEvent> subscription;
  Completer<String>? createGate;
  Completer<String>? sendGate;
  var serial = 0;

  String messageFor(Map args) => jsonEncode({
        'clientMsgID': 'call-${++serial}',
        'sendID': 'bob',
        'contentType': 110,
        'customElem': {
          'data': args['data'],
          'extension': '',
          'description': ''
        },
      });

  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'bob';
    live = _Live();
    native = [];
    records = [];
    received = [];
    createGate = null;
    sendGate = null;
    // Keep this a transport test: observe signals without opening a real room
    // or loading the ringtone. All native message calls are local mocks.
    subscription = live.signalingSubject.listen(received.add);
    live.onCallRecord = (record, account) async {
      records.add((record, account));
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      native.add(call);
      final args = Map<String, dynamic>.from(call.arguments as Map);
      if (call.method == 'createCustomMessage') {
        return createGate?.future ?? messageFor(args);
      }
      if (call.method == 'sendMessage') {
        return sendGate?.future ?? jsonEncode(args['message']);
      }
      if (call.method == 'insertSingleMessageToLocalStorage') {
        return jsonEncode(args['message']);
      }
      throw StateError('Unexpected native operation ${call.method}');
    });
  });

  tearDown(() async {
    await subscription.cancel();
    await live.onCloseLive();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    OpenIM.iMManager.userID = '';
    Get.reset();
  });

  List<MethodCall> sends() =>
      native.where((call) => call.method == 'sendMessage').toList();
  int typeOf(MethodCall call) {
    final args = call.arguments as Map;
    return (jsonDecode((args['message'] as Map)['customElem']['data'] as String)
        as Map)['customType'] as int;
  }

  test('current room accepts only its peer and ignores stale terminal signals',
      () async {
    live.receiveNewInvitation(_signal('active'));
    live.receiveNewInvitation(_signal('active'));
    live.invitationCancelled(_signal('old'));
    live.invitationCancelled(_signal('active', actor: 'mallory'));
    live.invitationCancelled(_signal('active'));
    await _flush();
    expect(received.map((event) => event.state),
        [CallState.beCalled, CallState.beCanceled]);
    expect(sends(), isEmpty);
  });

  test('busy invitation sends one reject without replacing the active room',
      () async {
    live.receiveNewInvitation(_signal('active'));
    live.receiveNewInvitation(_signal('busy', inviter: 'charlie'));
    live.receiveNewInvitation(_signal('busy', inviter: 'charlie'));
    await _flush();
    expect(sends(), hasLength(1));
    expect(typeOf(sends().single), CustomMessageType.callingReject);
    expect((sends().single.arguments as Map)['userID'], 'charlie');
    expect((sends().single.arguments as Map)['isOnlineOnly'], isTrue);
    expect(records, hasLength(1));
    expect(records.single.$1.roomID, 'busy');
    live.invitationCancelled(_signal('active'));
    await _flush();
    expect(received.last.state, CallState.beCanceled);
  });

  test('terminal double taps await one send and write one final record',
      () async {
    final signal = _signal('active');
    live.receiveNewInvitation(signal);
    sendGate = Completer<String>();
    final first = live.onTapReject(signal);
    final duplicate = live.onTapReject(signal);
    final timeout = live.onTimeoutCancelled(signal);
    await _flush();
    expect(sends(), hasLength(1));
    expect(records, isEmpty);
    sendGate!
        .complete(jsonEncode((sends().single.arguments as Map)['message']));
    await Future.wait([first, duplicate, timeout]);
    expect(records, hasLength(1));
    expect(records.single.$1.state, 'reject');
    expect(records.single.$2, 'bob');
    expect(
        native.where(
            (call) => call.method == 'insertSingleMessageToLocalStorage'),
        hasLength(1));
  });

  test('callee timeout rejects to inviter using 202', () async {
    final signal = _signal('active');
    live.receiveNewInvitation(signal);
    await live.onTimeoutCancelled(signal);
    expect(typeOf(sends().single), 202);
    expect((sends().single.arguments as Map)['userID'], 'alice');
    expect(records.single.$1.state, 'timeout');
    expect(records.single.$1.incomingCall, isTrue);
  });

  test('caller timeout cancels to invitee using 203', () async {
    OpenIM.iMManager.userID = 'alice';
    // There is intentionally no mounted overlay, so no RTC or HTTP starts.
    await live.call(
        callObj: CallObj.single,
        callType: CallType.audio,
        roomID: 'outgoing',
        inviteeUserIDList: ['bob']);
    await live.onTimeoutCancelled(_signal('outgoing'), requireActive: false);
    expect(typeOf(sends().single), 203);
    expect((sends().single.arguments as Map)['userID'], 'bob');
    expect(records.single.$1.incomingCall, isFalse);
  });

  test('unsupported group invitation rejects safely without fake group history',
      () async {
    live.receiveNewInvitation(_signal('group', sessionType: 3));
    await _flush();
    expect(typeOf(sends().single), 202);
    expect(received, isEmpty);
    expect(records, isEmpty);
    expect(live.isBusy, isFalse);
  });

  test(
      'account change during message creation suppresses send and local history',
      () async {
    final signal = _signal('old-account');
    live.receiveNewInvitation(signal);
    createGate = Completer<String>();
    final ending = live.onTapReject(signal);
    await _flush();
    OpenIM.iMManager.userID = 'charlie';
    final create = native.single;
    createGate!.complete(messageFor(create.arguments as Map));
    await ending;
    expect(sends(), isEmpty);
    expect(records, isEmpty);
    expect(
        native.where(
            (call) => call.method == 'insertSingleMessageToLocalStorage'),
        isEmpty);
  });

  test(
      'session logout invalidates old sends even before native account changes',
      () async {
    final signal = _signal('old-session');
    live.receiveNewInvitation(signal);
    createGate = Completer<String>();
    final ending = live.onTapReject(signal);
    await _flush();
    final create = native.single;
    await live.endLiveSession(notifyPeer: false);
    createGate!.complete(messageFor(create.arguments as Map));
    await ending;
    expect(sends(), isEmpty);
    expect(records, isEmpty);
    expect(live.isBusy, isFalse);
  });

  test('close releases every subject and rejects later invitations', () async {
    await subscription.cancel();
    await live.onCloseLive();
    expect(live.signalingSubject.isClosed, isTrue);
    expect(live.backgroundSubject.isClosed, isTrue);
    expect(live.insertSignalingMessageSubject.isClosed, isTrue);
    expect(live.roomParticipantDisconnectedSubject.isClosed, isTrue);
    expect(live.roomParticipantConnectedSubject.isClosed, isTrue);
    live.receiveNewInvitation(_signal('late'));
    expect(live.isBusy, isFalse);
    expect(sends(), isEmpty);
  });
}
