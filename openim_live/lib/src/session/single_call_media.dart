import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:openim_common/openim_common.dart' hide Participant;

import '../models/call_errors.dart';
import '../models/call_types.dart';
import 'call_media_operations.dart';
import 'single_call_session.dart';

/// Media can run while there is no mounted Flutter call surface.
abstract class SingleCallMedia extends ChangeNotifier {
  VoidCallback? onDisconnected, onReconnecting;
  Room? get room => null;
  bool get ready;
  bool get peerPresent;
  Future<void> connect(SignalingCertificate certificate, CallAttempt attempt);
  Future<void> publish(CallAttempt attempt);
  Future<void> setMicrophone(bool enabled);
  Future<void> setSpeaker(bool enabled);
  Future<void> setCamera(bool enabled);
  Future<void> switchCamera();
  Future<void> setBackgroundCamera(bool enabled);
  Future<void> release();
}

class LiveKitSingleCallMedia extends SingleCallMedia {
  LiveKitSingleCallMedia({
    required this.peerUserID,
    required this.callType,
    required this.systemAudio,
  });

  final String peerUserID;
  final CallType callType;
  final bool systemAudio;
  final _operations = CallMediaOperations();
  final _tracks =
      CallMediaResources<LocalTrack>(disposeResource: (track) async {
    try {
      await track.stop();
    } finally {
      await track.dispose();
    }
  });
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  Future<void>? _connecting, _publishing, _releasing;
  bool _ready = false, _restoreCamera = false;
  bool _microphone = true;
  late bool _speaker = callType == CallType.video;
  bool? _previousAutomaticAudio;
  bool _disposed = false;

  @override
  Room? get room => _room;
  @override
  bool get ready => _ready;
  @override
  bool get peerPresent =>
      _room?.remoteParticipants.values.any((p) => p.identity == peerUserID) ==
      true;

  bool _current([CallAttempt? attempt]) =>
      !_operations.closed && (attempt?.isCurrent ?? true);

  @override
  Future<void> connect(
      SignalingCertificate certificate, CallAttempt attempt) async {
    if (!attempt.isCurrent) return;
    if (certificate.busyLineUserIDList?.isNotEmpty == true) {
      throw const CallBusy();
    }
    final url = certificate.liveURL, token = certificate.token;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      throw const InvalidCallCertificate();
    }
    if (systemAudio) {
      _previousAutomaticAudio ??=
          Hardware.instance.isAutomaticConfigurationEnabled;
      Hardware.instance.setAutomaticConfigurationEnabled(enable: false);
    }
    final connectedRoom = _room = Room(
      roomOptions: const RoomOptions(
        dynacast: true,
        adaptiveStream: true,
        defaultCameraCaptureOptions:
            CameraCaptureOptions(params: VideoParametersPresets.h720_169),
        defaultVideoPublishOptions: VideoPublishOptions(
          simulcast: true,
          videoCodec: 'VP9',
          videoEncoding:
              VideoEncoding(maxBitrate: 5 * 1000 * 1000, maxFramerate: 15),
        ),
      ),
    );
    _listener = connectedRoom.createListener()
      ..on<RoomDisconnectedEvent>((_) => onDisconnected?.call())
      ..on<RoomReconnectingEvent>((_) => onReconnecting?.call())
      ..on<RoomReconnectedEvent>((_) => _changed())
      ..on<ParticipantConnectedEvent>((event) {
        if (event.participant.identity == peerUserID) _changed();
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        if (event.participant.identity == peerUserID) onDisconnected?.call();
      });
    connectedRoom.addListener(_changed);
    _connecting = connectedRoom.connect(url, token);
    await _connecting;
  }

  @override
  Future<void> publish(CallAttempt attempt) async {
    final connectedRoom = _room;
    if (connectedRoom == null || !_current(attempt)) return;
    _publishing = _operations.run(() async {
      await _setSource(
          connectedRoom, TrackSource.microphone, _microphone, attempt);
      if (!_current(attempt)) return;
      await _setSource(connectedRoom, TrackSource.camera,
          callType == CallType.video, attempt);
      if (!_current(attempt)) return;
      await Hardware.instance.setSpeakerphoneOn(_speaker);
    }).then((_) {});
    await _publishing;
    if (!_current(attempt)) return;
    _ready = true;
    _changed();
  }

  Future<void> _setSource(Room connectedRoom, TrackSource source, bool enabled,
      [CallAttempt? attempt]) async {
    if (!_current(attempt)) return;
    final participant = connectedRoom.localParticipant;
    if (participant == null) return;
    final publication = participant.getTrackPublicationBySource(source);
    if (publication != null) {
      if (enabled) {
        await publication.unmute();
      } else {
        await publication.mute();
      }
      return;
    }
    if (!enabled) return;
    await _tracks.captureAndPublish(
      capture: () => source == TrackSource.microphone
          ? LocalAudioTrack.create(
              connectedRoom.roomOptions.defaultAudioCaptureOptions)
          : LocalVideoTrack.createCameraTrack(
              connectedRoom.roomOptions.defaultCameraCaptureOptions),
      publish: (track) async {
        if (track is LocalAudioTrack) {
          await participant.publishAudioTrack(track);
        } else if (track is LocalVideoTrack) {
          await participant.publishVideoTrack(track);
        }
      },
      isCurrent: () => _current(attempt),
    );
  }

  @override
  Future<void> setMicrophone(bool enabled) async {
    _microphone = enabled;
    await _operations.run(() async {
      final connectedRoom = _room;
      if (connectedRoom != null && _ready) {
        await _setSource(connectedRoom, TrackSource.microphone, enabled);
      }
    });
  }

  @override
  Future<void> setSpeaker(bool enabled) async {
    _speaker = enabled;
    await _operations.run(() async {
      if (_current() && _ready) {
        await Hardware.instance.setSpeakerphoneOn(enabled);
      }
    });
  }

  @override
  Future<void> setCamera(bool enabled) async => _operations.run(() async {
        final connectedRoom = _room;
        if (connectedRoom != null && _ready) {
          await _setSource(connectedRoom, TrackSource.camera, enabled);
        }
      }).then((_) {});

  @override
  Future<void> switchCamera() async {
    await _operations.run(() async {
      if (!_current()) return;
      final track = _room?.localParticipant
          ?.getTrackPublicationBySource(TrackSource.camera)
          ?.track;
      if (track != null) await rtc.Helper.switchCamera(track.mediaStreamTrack);
    });
  }

  @override
  Future<void> setBackgroundCamera(bool enabled) async {
    await _operations.run(() async {
      final connectedRoom = _room;
      final participant = connectedRoom?.localParticipant;
      if (!_current() || participant == null || connectedRoom == null) return;
      if (!enabled) {
        _restoreCamera = participant.isCameraEnabled();
      } else if (!_restoreCamera) {
        return;
      }
      await _setSource(connectedRoom, TrackSource.camera, enabled);
    });
  }

  void _changed() {
    if (!_disposed && !_operations.closed) notifyListeners();
  }

  Future<void> _cleanup(Future<dynamic> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      Logger.print('Call media cleanup: ${error.runtimeType}');
    }
  }

  @override
  Future<void> release() => _releasing ??= _release();

  Future<void> _release() async {
    final drained = _operations.close();
    final connectedRoom = _room;
    _ready = false;
    connectedRoom?.removeListener(_changed);
    await _cleanup(() async => _listener?.dispose());
    if (connectedRoom != null) await _cleanup(connectedRoom.disconnect);
    await _cleanup(() async => _connecting);
    await _cleanup(() async => _publishing);
    await drained;
    await _cleanup(_tracks.release);
    if (connectedRoom != null) await _cleanup(connectedRoom.dispose);
    _room = null;
    final automatic = _previousAutomaticAudio;
    if (automatic != null) {
      Hardware.instance.setAutomaticConfigurationEnabled(enable: automatic);
      _previousAutomaticAudio = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
