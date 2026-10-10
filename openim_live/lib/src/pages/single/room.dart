import 'package:collection/collection.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../session/single_call_session.dart';
import 'widgets/call_state.dart';
import 'widgets/participant.dart';

/// A view of the one session/RTC owner created before any Flutter frame.
class SingleRoomView extends SignalView {
  const SingleRoomView({
    super.key,
    required super.owner,
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
    super.ringingTimeout,
  });

  @override
  SignalState<SingleRoomView> createState() => _SingleRoomViewState();
}

class _SingleRoomViewState extends SignalState<SingleRoomView> {
  @override
  void initState() {
    super.initState();
    widget.owner!.addListener(_ownerChanged);
    _readTracks();
  }

  void _ownerChanged() {
    if (!mounted || !session.active) return;
    _readTracks();
    final room = widget.owner!.media.room;
    if (room != null &&
        widget.owner!.media.ready &&
        !roomDidUpdateSubject.isClosed) {
      roomDidUpdateSubject.add(room);
    }
    syncPictureInPicture();
    setState(() {});
  }

  void _readTracks() {
    enabledMicrophone = widget.owner!.microphoneEnabled;
    enabledSpeaker = widget.owner!.speakerEnabled;
    final room = widget.owner!.media.room;
    final local = room?.localParticipant;
    localParticipantTrack = local == null ? null : _track(local);
    final remote = room?.remoteParticipants.values
        .where((p) => p.identity == widget.userID)
        .firstOrNull;
    remoteParticipantTrack = remote == null ? null : _track(remote);
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
  Future<void> connect(CallAttempt attempt) async {}
  @override
  Future<void> releaseMedia() async {}
  @override
  Future<void> setMicrophone(bool enabled) =>
      widget.owner!.setMicrophone(enabled).then((_) {});
  @override
  Future<void> setSpeaker(bool enabled) =>
      widget.owner!.setSpeaker(enabled).then((_) {});
  @override
  Future<void> setCamera(bool enabled) =>
      widget.owner!.media.setCamera(enabled);
  @override
  Future<void> switchCamera() => widget.owner!.media.switchCamera();
  @override
  Future<void> setBackgroundCamera(bool enabled) =>
      widget.owner!.media.setBackgroundCamera(enabled);
  @override
  bool existParticipants() => widget.owner!.media.peerPresent;

  @override
  void dispose() {
    widget.owner!.removeListener(_ownerChanged);
    super.dispose();
  }
}
