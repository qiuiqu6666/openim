import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:openim_common/openim_common.dart' hide Participant;

import '../../models/call_errors.dart';
import '../../session/call_media_operations.dart';
import '../../session/single_call_session.dart';
import '../../live_client.dart';
import 'widgets/call_state.dart';
import 'widgets/participant.dart';

class SingleRoomView extends SignalView {
  const SingleRoomView(
      {super.key,
      required super.callType,
      required super.initState,
      required super.userID,
      required super.callEventSubject,
      required super.autoPickup,
      super.incomingCallPreferences,
      super.onIncomingWaitingEnded,
      super.roomID,
      super.onClose,
      super.onBindRoomID,
      super.onBindEnd,
      super.onBusyLine,
      super.onDial,
      super.onStartCalling,
      super.onTapCancel,
      super.onTapHangup,
      super.onTapPickup,
      super.onTapReject,
      super.onTimeout,
      super.onWaitingAccept,
      super.onSyncUserInfo,
      super.onError,
      super.onRoomDisconnected,
      super.ringingTimeout});

  @override
  SignalState<SingleRoomView> createState() => _SingleRoomViewState();
}

class _SingleRoomViewState extends SignalState<SingleRoomView> {
  EventsListener<RoomEvent>? _listener;
  Room? _room;
  Future<void>? _connecting, _publishing, _releasing;
  bool _mediaReady = false, _restoreCamera = false;
  final _media = CallMediaOperations();
  final _tracks =
      CallMediaResources<LocalTrack>(disposeResource: (track) async {
    try {
      await track.stop();
    } finally {
      await track.dispose();
    }
  });

  bool _isCurrent([CallAttempt? attempt]) =>
      session.active && !_media.closed && (attempt?.isCurrent ?? true);

  @override
  Future<void> connect(CallAttempt attempt) async {
    if (!attempt.isCurrent) return;
    if (certificate.busyLineUserIDList?.isNotEmpty == true) {
      throw const CallBusy();
    }
    final url = certificate.liveURL, token = certificate.token;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      throw const InvalidCallCertificate();
    }
    final room = _room = Room(
        roomOptions: const RoomOptions(
      dynacast: true,
      adaptiveStream: true,
      defaultCameraCaptureOptions:
          CameraCaptureOptions(params: VideoParametersPresets.h720_169),
      defaultVideoPublishOptions: VideoPublishOptions(
          simulcast: true,
          videoCodec: 'VP9',
          videoEncoding:
              VideoEncoding(maxBitrate: 5 * 1000 * 1000, maxFramerate: 15)),
    ));
    _listener = room.createListener()
      ..on<RoomDisconnectedEvent>((_) {
        if (session.active) unawaited(endDisconnected());
      })
      ..on<RoomReconnectingEvent>((_) => session.reconnecting())
      ..on<RoomReconnectedEvent>((_) => _sortParticipants())
      ..on<ParticipantConnectedEvent>((event) {
        if (event.participant.identity == widget.userID) _sortParticipants();
      })
      ..on<ParticipantDisconnectedEvent>((event) {
        if (event.participant.identity == widget.userID && session.active) {
          unawaited(onTapHangup(false));
        }
      });
    room.addListener(_onRoomDidUpdate);
    _connecting = room.connect(url, token);
    await _connecting;
    if (!attempt.isCurrent) return;
    _publishing = _media.run(() async {
      await _setSource(
          room, TrackSource.microphone, enabledMicrophone, attempt);
      if (!_isCurrent(attempt)) return;
      await _setSource(
          room, TrackSource.camera, widget.callType == CallType.video, attempt);
      if (!_isCurrent(attempt)) return;
      await Hardware.instance.setSpeakerphoneOn(enabledSpeaker);
    }).then((_) {});
    await _publishing;
    if (!attempt.isCurrent) return;
    _mediaReady = true;
    if (!roomDidUpdateSubject.isClosed) roomDidUpdateSubject.add(room);
    _sortParticipants();
    if (!session.connected) widget.onWaitingAccept?.call();
  }

  Future<void> _setSource(Room room, TrackSource source, bool enabled,
      [CallAttempt? attempt]) async {
    if (!_isCurrent(attempt)) return;
    final participant = room.localParticipant;
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
    // The SDK convenience setters don't own a new capture if publication fails.
    // Hold it immediately after capture, including cancellation during creation.
    await _tracks.captureAndPublish(
      capture: () => source == TrackSource.microphone
          ? LocalAudioTrack.create(room.roomOptions.defaultAudioCaptureOptions)
          : LocalVideoTrack.createCameraTrack(
              room.roomOptions.defaultCameraCaptureOptions),
      publish: (track) async {
        if (track is LocalAudioTrack) {
          await participant.publishAudioTrack(track);
        } else if (track is LocalVideoTrack) {
          await participant.publishVideoTrack(track);
        }
      },
      isCurrent: () => _isCurrent(attempt),
    );
  }

  @override
  Future<void> setMicrophone(bool enabled) async {
    await _media.run(() async {
      final room = _room;
      if (room != null) await _setSource(room, TrackSource.microphone, enabled);
    });
  }

  @override
  Future<void> setSpeaker(bool enabled) async {
    await _media.run(() async {
      if (_isCurrent()) await Hardware.instance.setSpeakerphoneOn(enabled);
    });
  }

  @override
  Future<void> setCamera(bool enabled) async {
    await _media.run(() async {
      final room = _room;
      if (room != null) await _setSource(room, TrackSource.camera, enabled);
    });
  }

  @override
  Future<void> switchCamera() async {
    await _media.run(() async {
      if (!_isCurrent()) return;
      final track = _room?.localParticipant
          ?.getTrackPublicationBySource(TrackSource.camera)
          ?.track;
      if (track != null) await rtc.Helper.switchCamera(track.mediaStreamTrack);
    });
  }

  @override
  Future<void> setBackgroundCamera(bool enabled) async {
    try {
      await _media.run(() async {
        final room = _room;
        final participant = room?.localParticipant;
        if (!_isCurrent() || participant == null || room == null) return;
        if (!enabled) {
          _restoreCamera = participant.isCameraEnabled();
        } else if (!_restoreCamera) {
          return;
        }
        await _setSource(room, TrackSource.camera, enabled);
      });
    } catch (error) {
      Logger.print('Call background camera: ${error.runtimeType}');
    }
  }

  void _onRoomDidUpdate() {
    if (!mounted || !session.active) return;
    _sortParticipants();
    if (_room != null && _mediaReady && !roomDidUpdateSubject.isClosed) {
      roomDidUpdateSubject.add(_room!);
    }
  }

  void _sortParticipants() {
    if (!mounted || !session.active || _room == null) return;
    final local = _room!.localParticipant;
    if (local != null) localParticipantTrack = _track(local);
    final remote = _room!.remoteParticipants.values
        .where((p) => p.identity == widget.userID)
        .firstOrNull;
    remoteParticipantTrack = remote == null ? null : _track(remote);
    if (_mediaReady && remote != null) session.peerConnected();
    syncPictureInPicture();
    setState(() {});
  }

  ParticipantTrack _track(Participant participant) => ParticipantTrack(
        participant: participant,
        videoTrack: participant.videoTrackPublications
            .where((p) => !p.isScreenShare)
            .firstOrNull
            ?.track as VideoTrack?,
        isScreenShare: false,
      );

  @override
  Future<void> releaseMedia() => _releasing ??= _release();

  Future<void> _cleanup(Future<dynamic> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      Logger.print('Call media cleanup: ${error.runtimeType}');
    }
  }

  Future<void> _release() async {
    final drained = _media.close();
    final room = _room;
    _mediaReady = false;
    room?.removeListener(_onRoomDidUpdate);
    await _cleanup(() async => _listener?.dispose());
    // Disconnect aborts pending joins/publications; keep admission closed until
    // every native media operation settles before releasing the Room instance.
    if (room != null) await _cleanup(room.disconnect);
    await _cleanup(() async => _connecting);
    await _cleanup(() async => _publishing);
    await drained;
    await _cleanup(_tracks.release);
    if (room != null) await _cleanup(room.dispose);
    _room = null;
  }

  @override
  bool existParticipants() =>
      _room?.remoteParticipants.values
          .any((p) => p.identity == widget.userID) ==
      true;
}
