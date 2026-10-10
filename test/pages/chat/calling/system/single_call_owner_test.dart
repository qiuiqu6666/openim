import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';
import 'package:openim_live/src/session/single_call_media.dart';
import 'package:rxdart/rxdart.dart';

Future<void> _drain() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _Media extends SingleCallMedia {
  _Media(this.log);
  final List<String> log;
  Completer<void>? joinBarrier, releaseBarrier;
  Future<void>? _joining, _releasing;
  bool present = false, published = false, released = false;
  int joins = 0, publications = 0, releases = 0;

  @override
  bool get ready => published;
  @override
  bool get peerPresent => present;

  void peerArrives() {
    present = true;
    notifyListeners();
  }

  @override
  Future<void> connect(SignalingCertificate credentials, dynamic attempt) {
    joins++;
    log.add('join');
    return _joining = () async {
      await joinBarrier?.future;
      log.add('joined');
    }();
  }

  @override
  Future<void> publish(dynamic attempt) async {
    publications++;
    log.add('publish');
    published = true;
    notifyListeners();
  }

  @override
  Future<void> setMicrophone(bool enabled) async => log.add('mic:$enabled');
  @override
  Future<void> setSpeaker(bool enabled) async => log.add('speaker:$enabled');
  @override
  Future<void> setCamera(bool enabled) async {}
  @override
  Future<void> switchCamera() async {}
  @override
  Future<void> setBackgroundCamera(bool enabled) async {}

  @override
  Future<void> release() => _releasing ??= () async {
        releases++;
        log.add('release');
        await _joining;
        await releaseBarrier?.future;
        released = true;
        published = false;
        log.add('released');
      }();
}

class _System implements SystemCallAdapter {
  _System(this.log, this.media);
  final List<String> log;
  final _Media media;
  final audio = Completer<void>();
  int answerRequests = 0, connected = 0, endings = 0;
  bool requestAllowed = true;
  Object? requestError;
  SystemCallDescriptor? reported;

  @override
  Future<void> reportIncoming(SystemCallDescriptor call) async {
    reported = call;
    log.add('incoming');
  }

  @override
  Future<void> startOutgoing(SystemCallDescriptor call) async {
    reported = call;
    log.add('outgoing');
  }

  @override
  Future<bool> requestAnswer(SystemCallDescriptor call) async {
    answerRequests++;
    log.add('request-answer');
    if (requestError != null) throw requestError!;
    return requestAllowed;
  }

  @override
  Future<void> transportConnected(SystemCallDescriptor call) async {
    expect(media.joins, 1);
    expect(media.publications, 0);
    log.add('fulfill');
  }

  @override
  Future<void> waitForAudio(SystemCallDescriptor call) async {
    log.add('wait-audio');
    await audio.future;
    log.add('audio-active');
  }

  @override
  Future<void> peerConnected(SystemCallDescriptor call) async {
    connected++;
    log.add('peer-connected');
  }

  @override
  Future<void> microphoneChanged(
      SystemCallDescriptor call, bool enabled) async {
    log.add('system-mic:$enabled');
  }

  @override
  Future<void> speakerChanged(SystemCallDescriptor call, bool enabled) async {
    log.add('system-speaker:$enabled');
  }

  @override
  Future<void> callEnded(
      SystemCallDescriptor call, CallTermination result) async {
    expect(media.released, isTrue);
    endings++;
    log.add('system-ended');
    if (!audio.isCompleted) audio.complete();
  }
}

class _Fixture {
  _Fixture({bool incoming = true, bool system = true}) {
    media = _Media(log);
    adapter = _System(log, media);
    invitation = InvitationInfo(
      roomID: 'verified-call-room',
      inviterUserID: incoming ? 'peer' : 'owner',
      inviteeUserIDList: [incoming ? 'owner' : 'peer'],
      mediaType: 'audio',
      sessionType: 1,
      initiateTime: DateTime.now().millisecondsSinceEpoch,
      timeout: 30,
    );
    owner = SingleCallOwner(
      call: SystemCallDescriptor(
        accountID: 'owner',
        roomID: invitation.roomID!,
        peerUserID: 'peer',
        incoming: incoming,
        callType: CallType.audio,
        invitation: invitation,
        deadline: DateTime.now().add(const Duration(seconds: 30)),
      ),
      initialState: incoming ? CallState.beCalled : CallState.call,
      events: events,
      media: media,
      systemCalls: system ? adapter : null,
      isCurrentAccount: () => current,
      permissions: (_) async {
        log.add('permissions');
        if (!permissionAllowed) throw const CallPermissionDenied('microphone');
      },
      certificate: (outgoing) async {
        log.add(outgoing ? 'dial-certificate' : 'accept-certificate');
        await certificateBarrier?.future;
        if (certificateError != null) throw certificateError!;
        return SignalingCertificate(
          roomID: invitation.roomID,
          token: 'rtc-test-token',
          liveURL: 'wss://rtc.example.test',
        );
      },
      onTerminated: (result) async {
        outcomes.add(result);
        log.add('signal-ended');
      },
      onClosed: () => closes++,
    );
  }

  final log = <String>[];
  final outcomes = <CallTermination>[];
  final events = PublishSubject<CallEvent>();
  late final InvitationInfo invitation;
  late final _Media media;
  late final _System adapter;
  late final SingleCallOwner owner;
  Completer<void>? certificateBarrier;
  Object? certificateError;
  bool current = true, permissionAllowed = true;
  int closes = 0;

  Future<void> dispose() async {
    for (final barrier in [
      certificateBarrier,
      media.joinBarrier,
      media.releaseBarrier,
      adapter.audio,
    ]) {
      if (barrier != null && !barrier.isCompleted) barrier.complete();
    }
    await owner.end(notifyPeer: false);
    owner.dispose();
    await events.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('incoming owner exists and accepts without any Widget or frame',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.owner.start();
    expect(fixture.adapter.reported?.invitation, same(fixture.invitation));
    final accepting = fixture.owner.acceptFromSystem();
    await _drain();

    expect(fixture.log, [
      'incoming',
      'permissions',
      'accept-certificate',
      'join',
      'joined',
      'fulfill',
      'wait-audio',
    ]);
    expect(fixture.media.publications, 0);
    fixture.adapter.audio.complete();
    expect(await accepting, isTrue);
    expect(fixture.media.publications, 1);
    expect(fixture.owner.session.connected, isFalse);

    fixture.media.peerArrives();
    fixture.media.peerArrives();
    await _drain();
    expect(fixture.owner.session.state, CallState.calling);
    expect(fixture.adapter.connected, 1);
  });

  test(
      'UI answer requests the native action and does not create another RTC join',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.owner.start();
    await fixture.owner.acceptFromUI();
    await fixture.owner.acceptFromUI();
    expect(fixture.adapter.answerRequests, 1);
    expect(fixture.media.joins, 0);

    fixture.adapter.audio.complete();
    expect(await fixture.owner.acceptFromSystem(), isTrue);
    expect(fixture.media.joins, 1);
    expect(fixture.media.publications, 1);
  });

  test('duplicate system answers share the same actual session and room',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.owner.start();
    final first = fixture.owner.acceptFromSystem();
    final duplicate = fixture.owner.acceptFromSystem();
    await _drain();
    fixture.adapter.audio.complete();
    expect(await first, isTrue);
    expect(await duplicate, isTrue);
    expect(fixture.media.joins, 1);
    expect(fixture.media.publications, 1);
  });

  test('system answer request failure ends the invitation without joining',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.adapter.requestError = StateError('Native answer unavailable');
    await fixture.owner.start();
    await fixture.owner.acceptFromUI();
    expect(fixture.owner.session.active, isFalse);
    expect(fixture.outcomes.single.state, CallState.networkError);
    expect(fixture.adapter.endings, 1);
    expect(fixture.media.joins, 0);
  });

  test('no system adapter preserves direct in-app acceptance', () async {
    final fixture = _Fixture(system: false);
    addTearDown(fixture.dispose);
    await fixture.owner.start();
    await fixture.owner.acceptFromUI();
    expect(fixture.log, [
      'permissions',
      'accept-certificate',
      'join',
      'joined',
      'publish',
    ]);
    expect(fixture.adapter.answerRequests, 0);
  });

  test('outgoing call fulfills transport before audio and reports actual peer',
      () async {
    final fixture = _Fixture(incoming: false);
    addTearDown(fixture.dispose);
    final dialing = fixture.owner.start();
    await _drain();
    expect(fixture.log.first, 'outgoing');
    expect(fixture.log, contains('dial-certificate'));
    expect(fixture.media.publications, 0);
    fixture.media.peerArrives();
    expect(fixture.adapter.connected, 0);
    fixture.adapter.audio.complete();
    await dialing;
    await _drain();
    expect(fixture.media.publications, 1);
    expect(fixture.adapter.connected, 1);
  });

  test('permission failure does not fetch credentials, join, or fulfill',
      () async {
    final fixture = _Fixture()..permissionAllowed = false;
    addTearDown(fixture.dispose);
    await fixture.owner.start();
    expect(await fixture.owner.acceptFromSystem(), isFalse);
    expect(fixture.media.joins, 0);
    expect(fixture.log, isNot(contains('accept-certificate')));
    expect(fixture.log, isNot(contains('fulfill')));
    expect(fixture.outcomes.single.state, CallState.networkError);
    expect(fixture.adapter.endings, 1);
  });

  test('credential failure cannot fulfill a successful system answer',
      () async {
    final fixture = _Fixture()
      ..certificateError = StateError('RTC unavailable');
    addTearDown(fixture.dispose);
    await fixture.owner.start();
    expect(await fixture.owner.acceptFromSystem(), isFalse);
    expect(fixture.media.joins, 0);
    expect(fixture.log, isNot(contains('fulfill')));
    expect(fixture.adapter.endings, 1);
  });

  test('account change during credential lookup cannot connect the old call',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.certificateBarrier = Completer<void>();
    await fixture.owner.start();
    final accepting = fixture.owner.acceptFromSystem();
    await _drain();
    fixture.current = false;
    fixture.certificateBarrier!.complete();

    expect(await accepting, isFalse);
    expect(fixture.media.joins, 0);
    expect(fixture.log, isNot(contains('fulfill')));
  });

  test(
      'hangup during join invalidates late completion and releases before native',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.media.joinBarrier = Completer<void>();
    await fixture.owner.start();
    final accepting = fixture.owner.acceptFromSystem();
    await _drain();
    final ending = fixture.owner.end();
    await _drain();
    expect(fixture.owner.session.active, isFalse);
    expect(fixture.adapter.endings, 0);
    fixture.media.joinBarrier!.complete();
    await ending;
    expect(await accepting, isFalse);
    expect(fixture.media.publications, 0);
    expect(fixture.log, isNot(contains('fulfill')));
    expect(fixture.log.indexOf('released'),
        lessThan(fixture.log.indexOf('system-ended')));
  });

  test('remote cancellation while awaiting audio does not publish or revive',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.owner.start();
    final accepting = fixture.owner.acceptFromSystem();
    await _drain();
    fixture.events.add(CallEvent(
      CallState.beCanceled,
      SignalingInfo(userID: 'peer', invitation: fixture.invitation),
    ));
    await _drain();
    expect(await accepting, isFalse);
    expect(fixture.media.publications, 0);
    expect(fixture.outcomes.single.notifyPeer, isFalse);
    expect(fixture.adapter.endings, 1);
  });

  test(
      'termination waits for all old media before returning and restoring native',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.owner.start();
    fixture.adapter.audio.complete();
    await fixture.owner.acceptFromSystem();
    fixture.media.releaseBarrier = Completer<void>();
    var finished = false;
    final ending = fixture.owner.end().then((_) => finished = true);
    await _drain();
    expect(finished, isFalse);
    expect(fixture.log, contains('signal-ended'));
    expect(fixture.adapter.endings, 0);
    fixture.media.releaseBarrier!.complete();
    await ending;
    expect(finished, isTrue);
    expect(fixture.media.releases, 1);
    expect(fixture.adapter.endings, 1);
    expect(fixture.closes, 1);
  });

  test('native mute uses the same media owner and cannot run after termination',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.owner.start();
    expect(await fixture.owner.setMicrophone(false), isTrue);
    expect(fixture.owner.microphoneEnabled, isFalse);
    expect(fixture.log, contains('mic:false'));
    expect(fixture.log, contains('system-mic:false'));
    final muteOperations = fixture.log.length;
    expect(await fixture.owner.setMicrophone(false), isTrue);
    expect(fixture.log.length, muteOperations);
    await fixture.owner.end();
    expect(await fixture.owner.setMicrophone(true), isFalse);
    expect(fixture.log, isNot(contains('mic:true')));
  });

  test('speaker routing shares owner state and forwards to system audio',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.owner.start();
    expect(fixture.owner.speakerEnabled, isFalse);
    expect(await fixture.owner.setSpeaker(true), isTrue);
    expect(fixture.owner.speakerEnabled, isTrue);
    expect(fixture.log, contains('speaker:true'));
    expect(fixture.log, contains('system-speaker:true'));
    final operations = fixture.log.length;
    expect(await fixture.owner.setSpeaker(true), isTrue);
    expect(fixture.log.length, operations);
    await fixture.owner.end();
    expect(await fixture.owner.setSpeaker(false), isFalse);
    expect(fixture.log, isNot(contains('system-speaker:false')));
  });
}
