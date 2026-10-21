// Exercise the real pinned SDK engine; no network or native media is used.
// ignore_for_file: depend_on_referenced_packages, implementation_imports, invalid_use_of_internal_member
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekit_client/src/core/engine.dart';
import 'package:livekit_client/src/core/signal_client.dart';
import 'package:livekit_client/src/internal/events.dart';
import 'package:livekit_client/src/proto/livekit_rtc.pb.dart' as proto;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

const _options = ConnectOptions(
  timeouts: Timeouts(
    connection: Duration(milliseconds: 40),
    debounce: Duration(milliseconds: 1),
    publish: Duration(milliseconds: 40),
    peerConnection: Duration(milliseconds: 40),
    iceRestart: Duration(milliseconds: 40),
  ),
);

class _Signal extends SignalClient {
  _Signal(this.onConnect)
      : super((uri, [options]) async => throw UnimplementedError());
  final Future<void> Function() onConnect;

  @override
  Future<void> connect(String uriString, String token,
          {required ConnectOptions connectOptions,
          required RoomOptions roomOptions,
          bool reconnect = false}) =>
      onConnect();
}

void main() {
  for (final earlyJoin in [true, false]) {
    test('connect retains early ${earlyJoin ? 'join' : 'primary ready'} event',
        () async {
      late Engine engine;
      final signal = _Signal(() async {
        if (earlyJoin) {
          engine.events
              .emit(EngineJoinResponseEvent(response: proto.JoinResponse()));
        }
        engine.events.emit(const EngineSubscriberPeerStateUpdatedEvent(
          state: rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected,
          isPrimary: true,
        ));
        // Drain the broadcast stream before SignalClient.connect completes.
        await Future<void>.delayed(Duration.zero);
        if (!earlyJoin) {
          Timer.run(() => engine.events
              .emit(EngineJoinResponseEvent(response: proto.JoinResponse())));
        }
      });
      engine = Engine(roomOptions: const RoomOptions(), signalClient: signal);
      try {
        await engine.connect('wss://unused.test', 'unused',
            connectOptions: _options);
      } finally {
        await engine.dispose();
      }
    });
  }

  test('missing primary connection still fails within the connection deadline',
      () async {
    late Engine engine;
    engine = Engine(
      roomOptions: const RoomOptions(),
      signalClient: _Signal(() async {
        Timer.run(() => engine.events
            .emit(EngineJoinResponseEvent(response: proto.JoinResponse())));
      }),
    );
    try {
      await expectLater(
        engine.connect('wss://unused.test', 'unused', connectOptions: _options),
        throwsA(isA<MediaConnectException>()),
      );
    } finally {
      await engine.dispose();
    }
  });
  for (final primary in [true, false]) {
    test(
        primary
            ? 'stale early connected event does not admit a disconnected peer'
            : 'secondary transport cannot satisfy primary readiness', () async {
      late Engine engine;
      engine = Engine(
        roomOptions: const RoomOptions(),
        signalClient: _Signal(() async {
          engine.events.emit(EngineSubscriberPeerStateUpdatedEvent(
            state: rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected,
            isPrimary: primary,
          ));
          if (primary) {
            engine.events.emit(const EngineSubscriberPeerStateUpdatedEvent(
              state:
                  rtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
              isPrimary: true,
            ));
          }
          await Future<void>.delayed(Duration.zero);
          Timer.run(() => engine.events
              .emit(EngineJoinResponseEvent(response: proto.JoinResponse())));
        }),
      );
      try {
        await expectLater(
          engine.connect('wss://unused.test', 'unused',
              connectOptions: _options),
          throwsA(isA<MediaConnectException>()),
        );
      } finally {
        await engine.dispose();
      }
    });
  }

  test('socket failure is preserved without waiting for join or peer',
      () async {
    final failure = StateError('socket failed');
    final engine = Engine(
      roomOptions: const RoomOptions(),
      signalClient: _Signal(() async => throw failure),
    );
    try {
      await expectLater(
        engine.connect('wss://unused.test', 'unused', connectOptions: _options),
        throwsA(same(failure)),
      );
    } finally {
      await engine.dispose();
    }
  });
}
