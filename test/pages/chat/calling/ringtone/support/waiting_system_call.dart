import 'dart:async';

import 'package:openim_live/openim_live.dart';

/// Holds native start so controller tests can drive credential/media callbacks
/// without requesting microphone permission or joining a real RTC room.
class WaitingSystemCallProbe implements SystemCallAdapter {
  final _start = Completer<void>();

  @override
  Future<void> startOutgoing(SystemCallDescriptor call) => _start.future;
  @override
  Future<void> reportIncoming(SystemCallDescriptor call) async {}
  @override
  Future<void> callEnded(
      SystemCallDescriptor call, CallTermination result) async {
    if (!_start.isCompleted) _start.complete();
  }

  @override
  Future<bool> requestAnswer(SystemCallDescriptor call) async => true;
  @override
  Future<void> transportConnected(SystemCallDescriptor call) async {}
  @override
  Future<void> waitForAudio(SystemCallDescriptor call) async {}
  @override
  Future<void> peerConnected(SystemCallDescriptor call) async {}
  @override
  Future<void> microphoneChanged(
      SystemCallDescriptor call, bool enabled) async {}
  @override
  Future<void> speakerChanged(SystemCallDescriptor call, bool enabled) async {}
}
