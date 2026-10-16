import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/calling/ios/ios_callkit_platform.dart';
import 'package:openim/core/calling/ios/ios_callkit_runtime.dart';
import 'package:openim/core/push/apns/apns_platform.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';

class FakePlatform implements IOSCallKitPlatform {
  final eventStream =
      StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final tokenStream = StreamController<APNsDeviceToken>.broadcast();
  final operations = <(String, Map<String, dynamic>?)>[];
  bool failPause = false;
  bool? systemIncoming;
  @override
  Stream<Map<String, dynamic>> get events => eventStream.stream;
  @override
  Stream<APNsDeviceToken> get tokens => tokenStream.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<T?> invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    operations.add((method, arguments));
    if (method == 'pauseSession' && failPause) {
      throw StateError('offline native');
    }
    final Object? value = switch (method) {
      'usesSystemIncomingCall' => systemIncoming,
      'getState' => {'audioActive': false},
      'getCachedTokens' => null,
      'drainPendingEvents' => <Object?>[],
      'requestMute' ||
      'setSpeakerphone' ||
      'completeAction' ||
      'setAudioEnabled' ||
      'requestAnswer' ||
      'releaseAudioSession' =>
        true,
      _ => null,
    };
    return value as T?;
  }

  void send(String type,
      {String account = 'me',
      String key = 'key',
      String room = 'room_1234',
      String? action,
      bool? muted}) {
    eventStream.add({
      'type': type,
      'accountID': account,
      'sessionKey': key,
      'roomID': room,
      if (action != null) 'actionID': action,
      if (muted != null) 'muted': muted
    });
  }

  @override
  Future<void> dispose() async {
    await eventStream.close();
    await tokenStream.close();
  }
}

SystemCallDescriptor invitation() => SystemCallDescriptor(
    accountID: 'me',
    roomID: 'room_1234',
    peerUserID: 'peer',
    callType: CallType.audio,
    incoming: true,
    invitation: InvitationInfo(
        roomID: 'room_1234',
        inviterUserID: 'peer',
        inviteeUserIDList: ['me'],
        mediaType: 'audio',
        sessionType: 1,
        initiateTime: DateTime.now().millisecondsSinceEpoch,
        timeout: 30));

Future<void> flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakePlatform platform;
  late IOSCallKitRuntime runtime;
  late IOSCallKitSession? identity;
  late SystemCallDescriptor call;
  late int accepted, ended, cleanups;
  late List<bool> microphone;
  late Future<bool> Function(String) accept;
  late Future<void> Function() cleanup;
  setUp(() async {
    platform = FakePlatform();
    identity = (accountID: 'me', sessionKey: 'key');
    call = invitation();
    accepted = ended = cleanups = 0;
    microphone = [];
    accept = (_) async {
      accepted++;
      return true;
    };
    cleanup = () async {
      cleanups++;
    };
    runtime = IOSCallKitRuntime(
      platform: platform,
      currentSession: () => identity,
      supported: true,
      sessionReady: () => true,
      reportStatus: (_) {},
      invitationWait: const Duration(milliseconds: 15),
      audioTimeout: const Duration(milliseconds: 100),
      acceptCall: (room) => accept(room),
      endCall: (_) async {
        ended++;
      },
      setMicrophone: (_, enabled) async {
        microphone.add(enabled);
        return true;
      },
      endLiveSession: () => cleanup(),
    );
    await runtime.onSessionReady(authenticated: true);
  });
  tearDown(() async {
    await runtime.dispose();
  });

  test('foreground incoming selects in-app ownership without reporting CallKit', () async {
    platform.systemIncoming = false;
    expect(await runtime.usesSystemIncomingCall(call.roomID), isFalse);
    expect(platform.operations.last.$1, 'usesSystemIncomingCall');
    expect(platform.operations.last.$2,
        {'accountID': 'me', 'sessionKey': 'key', 'roomID': call.roomID});
    expect(platform.operations.any((op) => op.$1 == 'reportIncomingCall'), isFalse);
  });

  test('background or existing PushKit calls retain system ownership', () async {
    platform.systemIncoming = true;
    expect(await runtime.usesSystemIncomingCall(call.roomID), isTrue);
  });

  test('older native bridge retains system ownership', () async {
    expect(await runtime.usesSystemIncomingCall(call.roomID), isTrue);
  });

  test('local-only cleanup still waits for media and releases old audio', () async {
    final media = Completer<void>();
    cleanup = () => media.future;
    var completed = false;
    final ending = runtime.endSession(waitForRemote: false)
        .then((_) => completed = true);
    await flush();
    expect(completed, isFalse);
    media.complete();
    await ending;
    expect(platform.operations.any((operation) =>
        operation.$1 == 'releaseAudioSession' &&
        operation.$2?['accountID'] == 'me'), isTrue);
  });

  test('installs handler readiness again after authenticating native owner',
      () {
    final methods =
        platform.operations.map((operation) => operation.$1).toList();
    expect(methods.indexOf('setSession'),
        lessThan(methods.indexOf('setEventHandlerReady')));
    expect(methods.indexOf('setEventHandlerReady'),
        lessThan(methods.indexOf('drainPendingEvents')));
  });

  test('unverified push answer fails without accepting SDK call', () async {
    platform.send('incoming');
    platform.send('answer', action: 'unverified');
    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(accepted, 0);
    expect(
        platform.operations
            .where((op) => op.$1 == 'completeAction')
            .single
            .$2?['succeeded'],
        false);
  });

  test('old account and credential events cannot answer current invitation',
      () async {
    await runtime.reportIncoming(call);
    platform.send('answer', account: 'old', action: 'wrong-account');
    platform.send('answer', key: 'old-key', action: 'wrong-key');
    await flush();
    expect(accepted, 0);
  });

  test('native answer shares one owner and duplicate action is ignored',
      () async {
    await runtime.reportIncoming(call);
    platform.send('answer', action: 'answer');
    platform.send('answer', action: 'answer');
    await flush();
    expect(accepted, 1);
  });

  test(
      'fulfills real answer before audio gate and publishes only after activation',
      () async {
    await runtime.reportIncoming(call);
    var published = false;
    accept = (_) async {
      await runtime.transportConnected(call);
      await runtime.waitForAudio(call);
      published = true;
      return true;
    };
    platform.send('answer', action: 'answer');
    await flush();
    expect(
        platform.operations
            .where((op) => op.$1 == 'completeAction')
            .single
            .$2?['succeeded'],
        true);
    expect(published, false);
    platform.send('audioActivated');
    await flush();
    expect(published, true);
    expect(
        platform.operations
            .where((op) => op.$1 == 'setAudioEnabled')
            .single
            .$2?['enabled'],
        true);
  });

  test('call ending cancels waiting audio before tracks can publish', () async {
    await runtime.reportIncoming(call);
    final waiting = runtime.waitForAudio(call);
    final assertion = expectLater(waiting, throwsStateError);
    await runtime.callEnded(
        call, const CallTermination(CallState.hangup, 0, true));
    platform.send('audioActivated');
    await assertion;
    expect(platform.operations.any((op) => op.$1 == 'setAudioEnabled'), false);
  });

  test('system mute controls real microphone and end controls existing room',
      () async {
    await runtime.reportIncoming(call);
    platform.send('mute', action: 'mute', muted: true);
    platform.send('end', action: 'end');
    await flush();
    expect(microphone, [false]);
    expect(ended, 1);
  });

  test('audio reactivation re-enables only a live previously prepared room',
      () async {
    await runtime.reportIncoming(call);
    platform.send('audioActivated');
    await runtime.waitForAudio(call);
    platform.send('audioDeactivated');
    platform.send('audioActivated');
    await flush();
    expect(platform.operations.where((op) => op.$1 == 'setAudioEnabled').length,
        2);
  });

  test('logout fences answer immediately and release waits for old media',
      () async {
    await runtime.reportIncoming(call);
    final mediaClosed = Completer<void>();
    cleanup = () => mediaClosed.future;
    final retiring = runtime.endSession();
    platform.send('answer', action: 'late');
    await flush();
    expect(accepted, 0);
    expect(
        platform.operations.any((op) => op.$1 == 'releaseAudioSession'), false);
    mediaClosed.complete();
    await retiring;
    expect(platform.operations.last.$1, 'releaseAudioSession');
    final bindings =
        platform.operations.where((op) => op.$1 == 'setSession').length;
    await runtime.onSessionReady();
    expect(platform.operations.where((op) => op.$1 == 'setSession').length,
        bindings);
  });

  test('native cleanup failure still releases actual RTC media', () async {
    platform.failPause = true;
    await runtime.endSession();
    expect(cleanups, 1);
  });

  test('explicit logout during login pause clears persisted native account',
      () async {
    final mediaClosed = Completer<void>();
    cleanup = () => mediaClosed.future;
    final preparing = runtime.endSession(logout: false);
    await flush();
    final logout = runtime.endSession();
    mediaClosed.complete();
    await Future.wait([preparing, logout]);
    expect(
        platform.operations
            .where((op) => op.$1 == 'pauseSession')
            .last
            .$2?['logout'],
        true);
  });

  test('app microphone and speaker request the matching native controls',
      () async {
    await runtime.reportIncoming(call);
    await runtime.microphoneChanged(call, false);
    await runtime.speakerChanged(call, true);
    expect(
        platform.operations
            .where((op) => op.$1 == 'requestMute')
            .single
            .$2?['muted'],
        true);
    expect(
        platform.operations
            .where((op) => op.$1 == 'setSpeakerphone')
            .single
            .$2?['enabled'],
        true);
  });
}
