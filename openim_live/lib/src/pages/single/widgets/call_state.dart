import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show ValueListenable;

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sprintf/sprintf.dart';

import '../../../live_client.dart';
import '../../../models/call_errors.dart';
import '../../../models/incoming_call_preferences.dart';
import '../../../platform/call_picture_in_picture.dart';
import '../../../session/single_call_session.dart';
import '../../../widgets/call_compact_surface.dart';
import '../../../widgets/call_surface/call_full_screen_surface.dart';
import '../../../widgets/incoming_call/incoming_call_quick_answer_sheet.dart';
import 'controls.dart';
import 'participant.dart';

typedef EndCall = Future<void> Function({bool notifyPeer, String? reason});

abstract class SignalView extends StatefulWidget {
  const SignalView(
      {super.key,
      required this.callType,
      required this.initState,
      this.roomID,
      required this.userID,
      required this.callEventSubject,
      this.onDial,
      this.onSyncUserInfo,
      this.onTapCancel,
      this.onTapHangup,
      this.onTapPickup,
      this.onTapReject,
      this.onClose,
      required this.autoPickup,
      this.incomingCallPreferences,
      this.onIncomingWaitingEnded,
      this.onBindRoomID,
      this.onBindEnd,
      this.onWaitingAccept,
      this.onBusyLine,
      this.onStartCalling,
      this.onError,
      this.onRoomDisconnected,
      this.onTimeout,
      this.ringingTimeout = const Duration(seconds: 30)});
  final CallType callType;
  final CallState initState;
  final String? roomID;
  final String userID;
  final PublishSubject<CallEvent> callEventSubject;
  final Future<SignalingCertificate> Function()? onDial, onTapPickup;
  final Future Function()? onTapCancel, onTapReject, onTimeout;
  final Future Function(int duration, bool isPositive)? onTapHangup;
  final VoidCallback? onClose, onWaitingAccept, onBusyLine, onStartCalling;
  final VoidCallback? onRoomDisconnected;
  final bool autoPickup;
  final ValueListenable<IncomingCallPreferences>? incomingCallPreferences;
  final VoidCallback? onIncomingWaitingEnded;
  final Duration ringingTimeout;
  final void Function(String roomID)? onBindRoomID;
  final void Function(EndCall end)? onBindEnd;
  final Function(dynamic error, dynamic stack)? onError;
  final Future<UserInfo?> Function(String userID)? onSyncUserInfo;
}

abstract class SignalState<T extends SignalView> extends State<T>
    with WidgetsBindingObserver {
  late final SingleCallSession session;
  late final CallPictureInPictureController pictureInPicture;
  final callStateSubject = BehaviorSubject<CallState>();
  final roomDidUpdateSubject = PublishSubject<Room>();
  late SignalingCertificate certificate;
  String? roomID;
  UserInfo? userInfo;
  StreamSubscription<CallEvent>? _signalSubscription;
  bool minimize = false, enabledMicrophone = true, enabledSpeaker = true;
  bool _startedCalling = false, _cameraPaused = false;
  bool _backgrounded = false;
  bool _quickAnswerExpanded = false;
  bool _incomingWaitingEnded = false;
  bool _smallScreenRemote = true;
  bool? _pipEnabled;
  String? _pipTrack;
  ParticipantTrack? remoteParticipantTrack, localParticipantTrack;
  Alignment _smallAlignment = const Alignment(.9, -.8);

  CallState get callState => session.state;
  int get duration => session.duration;
  bool get current => mounted && session.active;

  @override
  void initState() {
    super.initState();
    roomID = widget.roomID;
    widget.incomingCallPreferences?.addListener(_onIncomingPreferencesChanged);
    pictureInPicture = CallPictureInPictureController(
      onRestore: onTapMaximize,
      onClosed: () =>
          unawaited(endActive(notifyPeer: true, reason: 'pipClosed')),
    )..addListener(_onPipChanged);
    session = SingleCallSession(
      initialState: widget.initState,
      connect: _connectAttempt,
      release: () async {
        try {
          await pictureInPicture.stop();
        } finally {
          await releaseMedia();
        }
      },
      onTerminated: _onTerminated,
      onClosed: () => widget.onClose?.call(),
      ringingTimeout: widget.ringingTimeout,
    )..addListener(_onSessionChanged);
    callStateSubject.add(callState);
    enabledSpeaker = widget.callType == CallType.video;
    widget.onBindEnd?.call(endActive);
    _signalSubscription = widget.callEventSubject.stream
        .where((event) => event.data.invitation?.roomID == roomID)
        .listen(_onSignal);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_syncUser());
    session.armDeadline();
    if (widget.initState == CallState.call) unawaited(session.dial());
    if (widget.autoPickup) unawaited(session.accept());
  }

  Future<void> _syncUser() async {
    try {
      final info = await widget.onSyncUserInfo?.call(widget.userID);
      if (current) setState(() => userInfo = info);
    } catch (e) {
      Logger.print('Call profile unavailable: ${e.runtimeType}');
    }
  }

  void _onIncomingPreferencesChanged() {
    if (current) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.incomingCallPreferences != widget.incomingCallPreferences) {
      oldWidget.incomingCallPreferences
          ?.removeListener(_onIncomingPreferencesChanged);
      widget.incomingCallPreferences
          ?.addListener(_onIncomingPreferencesChanged);
    }
  }

  Future<void> _connectAttempt(CallAttempt attempt, bool outgoing) async {
    final required = [
      Permission.microphone,
      if (widget.callType == CallType.video) Permission.camera
    ];
    final permissions = await Permissions.request(required);
    if (!attempt.isCurrent) return;
    for (final permission in required) {
      if (permissions[permission] != PermissionStatus.granted) {
        throw CallPermissionDenied(permission == Permission.camera
            ? StrRes.camera
            : StrRes.microphone);
      }
    }
    certificate = await (outgoing ? widget.onDial! : widget.onTapPickup!)();
    if (!attempt.isCurrent) return;
    if (certificate.roomID == null || certificate.roomID != roomID) {
      throw const InvalidCallCertificate();
    }
    widget.onBindRoomID?.call(roomID!);
    await connect(attempt);
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (widget.initState == CallState.beCalled &&
        callState != CallState.beCalled &&
        !_incomingWaitingEnded) {
      _incomingWaitingEnded = true;
      widget.onIncomingWaitingEnded?.call();
    }
    if (!callStateSubject.isClosed) callStateSubject.add(callState);
    if (session.connected && !_startedCalling) {
      _startedCalling = true;
      widget.onStartCalling?.call();
    }
    syncPictureInPicture();
    _updateBackgroundCamera();
    setState(() {});
  }

  void _onSignal(CallEvent event) {
    if (!current) return;
    switch (event.state) {
      case CallState.beRejected:
      case CallState.beCanceled:
      case CallState.otherAccepted:
      case CallState.otherReject:
        unawaited(session.end(event.state, notifyPeer: false));
        break;
      case CallState.beHangup:
        unawaited(session.end(CallState.beHangup, notifyPeer: false));
        break;
      case CallState.beAccepted:
        session.peerAccepted();
        break;
      case CallState.timeout:
        unawaited(session.end(CallState.timeout, notifyPeer: false));
        break;
      default:
        break;
    }
  }

  Future<void> _onTerminated(CallTermination result) async {
    switch (result.state) {
      case CallState.networkError:
        await widget.onError?.call(
            result.error ?? StateError('Call disconnected'), result.stackTrace);
        break;
      case CallState.timeout:
        await widget.onTimeout?.call();
        break;
      case CallState.cancel:
        if (result.notifyPeer) await widget.onTapCancel?.call();
        break;
      case CallState.reject:
        if (result.notifyPeer) await widget.onTapReject?.call();
        break;
      case CallState.hangup:
      case CallState.beHangup:
        await widget.onTapHangup?.call(result.duration, result.notifyPeer);
        break;
      case CallState.otherAccepted:
      case CallState.otherReject:
        IMViews.showToast(sprintf(StrRes.otherCallHandle, [
          result.state == CallState.otherReject
              ? StrRes.rejectCall
              : StrRes.accept
        ]));
        break;
      default:
        break;
    }
  }

  Future<void> endActive({bool notifyPeer = true, String? reason}) =>
      session.end(
          session.connected
              ? CallState.hangup
              : widget.initState == CallState.call
                  ? CallState.cancel
                  : CallState.reject,
          notifyPeer: notifyPeer);
  Future<void> onTapPickup() => session.accept();
  Future<void> onTapCancel() => session.end(CallState.cancel);
  Future<void> onTapReject() => session.end(CallState.reject);
  Future<void> onTapHangup(bool positive) =>
      session.end(CallState.hangup, notifyPeer: positive);
  Future<void> endDisconnected() => session.end(
      session.connected ? CallState.beHangup : CallState.networkError,
      notifyPeer: false);

  Future<void> connect(CallAttempt attempt);
  Future<void> releaseMedia();
  Future<void> setBackgroundCamera(bool enabled) async {}
  Future<void> setMicrophone(bool enabled) async {}
  Future<void> setSpeaker(bool enabled) async {}
  Future<void> setCamera(bool enabled) async {}
  Future<void> switchCamera() async {}
  bool existParticipants();

  void onTapMinimize() {
    if (current) setState(() => minimize = true);
  }

  void onTapMaximize() {
    if (current) setState(() => minimize = false);
  }

  void _onPipChanged() {
    if (mounted) {
      _updateBackgroundCamera();
      setState(() {});
    }
  }

  void _updateBackgroundCamera() {
    if (!session.active ||
        !session.connected ||
        widget.callType != CallType.video) {
      return;
    }
    final pause = _backgrounded &&
        !(pictureInPicture.backgroundCameraSupported &&
            (pictureInPicture.active || pictureInPicture.entering));
    if (pause == _cameraPaused) return;
    _cameraPaused = pause;
    unawaited(setBackgroundCamera(!pause));
  }

  void syncPictureInPicture() {
    final enabled = session.active && session.connected;
    final track = remoteParticipantTrack?.videoTrack?.mediaStreamTrack.id;
    if (_pipEnabled == enabled && _pipTrack == track) return;
    _pipEnabled = enabled;
    _pipTrack = track;
    unawaited(pictureInPicture.configure(
      enabled: enabled,
      remoteVideoTrackId: track,
      aspectWidth: widget.callType == CallType.video ? 9 : 1,
      aspectHeight: widget.callType == CallType.video ? 16 : 1,
    ));
  }

  Future<void> _enterPip() async {
    final entered = await pictureInPicture.enter();
    if (!mounted || !session.active) return;
    if (!entered) {
      IMViews.showToast(Localizations.localeOf(context).languageCode == 'zh'
          ? '当前设备暂不支持画中画'
          : 'Picture in Picture is unavailable');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!session.active) return;
    if (state == AppLifecycleState.detached) {
      unawaited(endActive(reason: 'detached'));
    } else {
      if (session.connected &&
          state == AppLifecycleState.inactive &&
          Platform.isIOS) {
        unawaited(pictureInPicture.enter());
      }
      if (state == AppLifecycleState.paused) {
        _backgrounded = true;
        _updateBackgroundCamera();
      } else if (state == AppLifecycleState.resumed) {
        _backgrounded = false;
        _updateBackgroundCamera();
      }
    }
  }

  @override
  void dispose() {
    widget.incomingCallPreferences
        ?.removeListener(_onIncomingPreferencesChanged);
    WidgetsBinding.instance.removeObserver(this);
    _signalSubscription?.cancel();
    session.removeListener(_onSessionChanged);
    // Session disposal stops PiP synchronously; detach before that stop can
    // notify a full-screen element which is already being unmounted.
    pictureInPicture.removeListener(_onPipChanged);
    session.dispose();
    pictureInPicture.dispose();
    callStateSubject.close();
    roomDidUpdateSubject.close();
    super.dispose();
  }

  Widget? _video(ParticipantTrack? track) =>
      track?.videoTrack == null ? null : ParticipantWidget.widgetFor(track!);

  @override
  Widget build(BuildContext context) {
    // Ending invalidates the session before signaling/native cleanup settles.
    // Remove every call surface and its PopScope immediately, while keeping
    // the owner mounted until cleanup closes the call and releases admission.
    if (!session.active) return const SizedBox.shrink();
    if (!minimize &&
        !_quickAnswerExpanded &&
        widget.initState == CallState.beCalled &&
        callState == CallState.beCalled &&
        widget.incomingCallPreferences?.value.quickAnswerPopup == true) {
      return Stack(children: [
        Positioned.fill(
          child: IncomingCallQuickAnswerSheet(
            key: const ValueKey('incoming-call-quick-answer'),
            userID: widget.userID,
            userInfo: userInfo,
            callType: widget.callType,
            onAccept: () => unawaited(onTapPickup()),
            onReject: () => unawaited(onTapReject()),
            onExpand: () => setState(() => _quickAnswerExpanded = true),
          ),
        ),
      ]);
    }
    final remote = _video(remoteParticipantTrack);
    final local = _video(localParticipantTrack);
    final mainVideo = _smallScreenRemote ? remote : local;
    final preview = _smallScreenRemote ? local : remote;
    final compact = CallCompactSurface(
      userInfo: userInfo,
      state: callState,
      duration: duration,
      video: widget.callType == CallType.video ? remote ?? local : null,
      systemPip: pictureInPicture.active || pictureInPicture.entering,
    );
    if (pictureInPicture.active || pictureInPicture.entering) {
      return Positioned.fill(child: compact);
    }
    return Stack(children: [
      if (!minimize)
        Positioned.fill(
            child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) onTapMinimize();
          },
          child: CallFullScreenSurface(
            child: Stack(children: [
              if (widget.callType == CallType.video && mainVideo != null)
                Positioned.fill(
                    key: const ValueKey('call-main-video'), child: mainVideo),
              ControlsView(
                callStateStream: callStateSubject.stream,
                roomDidUpdateStream: roomDidUpdateSubject.stream,
                initState: widget.initState,
                callType: widget.callType,
                userInfo: userInfo,
                duration: duration,
                active: session.active,
                connected: session.connected,
                onMinimize: onTapMinimize,
                onPictureInPicture: session.connected ? _enterPip : null,
                onEnabledMicrophone: (enabled) => enabledMicrophone = enabled,
                onEnabledSpeaker: (enabled) => enabledSpeaker = enabled,
                onSetMicrophone: setMicrophone,
                onSetSpeaker: setSpeaker,
                onSetCamera: setCamera,
                onSwitchCamera: switchCamera,
                onHangUp: (positive) => unawaited(onTapHangup(positive)),
                onPickUp: () => unawaited(onTapPickup()),
                onReject: () => unawaited(onTapReject()),
                onCancel: () => unawaited(onTapCancel()),
              ),
              if (widget.callType == CallType.video &&
                  (local != null || remote != null))
                Positioned(
                  key: const ValueKey('call-video-preview'),
                  top: MediaQuery.paddingOf(context).top + 64,
                  right: 16,
                  width: 96,
                  height: 144,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: current
                          ? () => setState(
                              () => _smallScreenRemote = !_smallScreenRemote)
                          : null,
                      // The preview owns switching, including before the peer
                      // publishes video. Camera focus/zoom cannot consume taps.
                      child: IgnorePointer(
                        child: preview ??
                            ColoredBox(
                              color: CallSurfaceTokens.background,
                              child: Center(
                                child: AvatarView(
                                  url: _smallScreenRemote
                                      ? null
                                      : userInfo?.faceURL,
                                  text: _smallScreenRemote
                                      ? StrRes.you
                                      : userInfo?.remark ??
                                          userInfo?.nickname ??
                                          widget.userID,
                                ),
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        )),
      if (minimize)
        Align(
            alignment: _smallAlignment,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapMaximize,
              onPanUpdate: (details) {
                final size = MediaQuery.sizeOf(context);
                setState(() => _smallAlignment = Alignment(
                    (_smallAlignment.x +
                            details.delta.dx *
                                2 /
                                (size.width - 110).clamp(1, double.infinity))
                        .clamp(-1, 1),
                    (_smallAlignment.y +
                            details.delta.dy *
                                2 /
                                (size.height - 196).clamp(1, double.infinity))
                        .clamp(-1, 1)));
              },
              child: SizedBox(
                  width: widget.callType == CallType.video ? 110 : 84,
                  height: widget.callType == CallType.video ? 196 : 96,
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(12), child: compact)),
            )),
    ]);
  }
}
