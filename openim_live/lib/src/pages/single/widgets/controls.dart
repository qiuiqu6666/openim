import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:synchronized/synchronized.dart';

import '../../../models/call_types.dart';
import '../../../widgets/live_button.dart';
import '../../../widgets/call_surface/call_full_screen_surface.dart';
import '../../../widgets/loading_view.dart';

class ControlsView extends StatefulWidget {
  const ControlsView(
      {super.key,
      this.initState = CallState.call,
      this.callType = CallType.video,
      required this.callStateStream,
      required this.roomDidUpdateStream,
      this.userInfo,
      this.onMinimize,
      this.onEnabledMicrophone,
      this.onEnabledSpeaker,
      this.onCancel,
      this.onHangUp,
      this.onPickUp,
      this.onReject,
      this.onPictureInPicture,
      this.onSetMicrophone,
      this.onSetSpeaker,
      this.onSetCamera,
      this.onSwitchCamera,
      this.duration = 0,
      this.active = true,
      this.connected = false});
  final Stream<Room> roomDidUpdateStream;
  final Stream<CallState> callStateStream;
  final CallState initState;
  final CallType callType;
  final UserInfo? userInfo;
  final int duration;
  final bool active, connected;
  final VoidCallback? onMinimize, onPictureInPicture;
  final void Function(bool enabled)? onEnabledMicrophone, onEnabledSpeaker;
  final Future<void> Function(bool)? onSetMicrophone, onSetSpeaker, onSetCamera;
  final Future<void> Function()? onSwitchCamera;
  final VoidCallback? onPickUp, onCancel, onReject;
  final void Function(bool positive)? onHangUp;
  @override
  State<ControlsView> createState() => _ControlsViewState();
}

class _ControlsViewState extends State<ControlsView> {
  late CallState _state;
  bool _microphone = true, _speaker = true, _changingCamera = false;
  LocalParticipant? _participant;
  StreamSubscription<CallState>? _stateSub;
  StreamSubscription<Room>? _roomSub;
  final _audioLock = Lock(), _speakerLock = Lock();

  @override
  void initState() {
    super.initState();
    _state = widget.initState;
    _speaker = widget.callType == CallType.video;
    _stateSub = widget.callStateStream.listen((state) {
      if (mounted) setState(() => _state = state);
    });
    _roomSub = widget.roomDidUpdateStream.listen((room) {
      if (!mounted) return;
      if (!identical(_participant, room.localParticipant)) {
        _participant?.removeListener(_changed);
        _participant = room.localParticipant;
        _participant?.addListener(_changed);
      }
      _changed();
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _operable => mounted && widget.active;

  Future<void> _toggleAudio() => _audioLock.synchronized(() async {
        if (!_operable) return;
        final enabled = !_microphone;
        try {
          await widget.onSetMicrophone?.call(enabled);
          if (!_operable) return;
          setState(() => _microphone = enabled);
          widget.onEnabledMicrophone?.call(enabled);
        } catch (_) {
          if (_operable) IMViews.showToast(StrRes.callFail);
        }
      });

  Future<void> _toggleSpeaker() => _speakerLock.synchronized(() async {
        if (!_operable) return;
        final enabled = !_speaker;
        try {
          await widget.onSetSpeaker?.call(enabled);
          if (!_operable) return;
          setState(() => _speaker = enabled);
          widget.onEnabledSpeaker?.call(enabled);
        } catch (_) {
          if (_operable) IMViews.showToast(StrRes.callFail);
        }
      });

  Future<void> _camera({bool flip = false}) async {
    if (!_operable || _participant == null || _changingCamera) return;
    setState(() => _changingCamera = true);
    try {
      if (flip) {
        await widget.onSwitchCamera?.call();
      } else {
        final statuses = await Permissions.request([Permission.camera]);
        if (!_operable) return;
        if (statuses.values.any((status) => !status.isGranted)) {
          IMViews.showToast(StrRes.permissionDeniedTitle);
          return;
        }
        await widget.onSetCamera?.call(!_participant!.isCameraEnabled());
      }
    } catch (_) {
      if (_operable) IMViews.showToast(StrRes.callFail);
    } finally {
      if (mounted) setState(() => _changingCamera = false);
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _roomSub?.cancel();
    _participant?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.callType == CallType.video && widget.connected;
    const foreground = CallSurfaceTokens.foreground;
    final secondary = CallSurfaceTokens.secondary;
    final nickname = IMUtils.emptyStrToNull(widget.userInfo?.remark) ??
        widget.userInfo?.nickname ??
        '';
    final connecting = _state == CallState.connecting;
    final status = !widget.active
        ? StrRes.hangUp
        : connecting
            ? StrRes.connecting
            : _state == CallState.call
                ? (widget.callType == CallType.video
                    ? StrRes.waitingVideoCallHint
                    : StrRes.waitingVoiceCallHint)
                : _state == CallState.beCalled
                    ? (widget.callType == CallType.video
                        ? StrRes.invitedVideoCallHint
                        : StrRes.invitedVoiceCallHint)
                    : IMUtils.seconds2HMS(widget.duration);
    return SafeArea(
        child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          IconButton(
              onPressed: widget.active ? widget.onMinimize : null,
              tooltip: Localizations.localeOf(context).languageCode == 'zh'
                  ? '最小化'
                  : 'Minimize',
              color: foreground,
              icon: const Icon(Icons.keyboard_arrow_down_rounded)),
          const Spacer(),
          if (widget.connected)
            IconButton(
                onPressed: widget.active ? widget.onPictureInPicture : null,
                tooltip: Localizations.localeOf(context).languageCode == 'zh'
                    ? '桌面画中画'
                    : 'Picture in Picture',
                color: foreground,
                icon: const Icon(Icons.picture_in_picture_alt_rounded)),
          if (video)
            IconButton(
                onPressed: _changingCamera || !widget.active
                    ? null
                    : () => unawaited(_camera(flip: true)),
                tooltip: StrRes.camera,
                color: foreground,
                icon: const Icon(Icons.flip_camera_ios_outlined)),
        ]),
        Expanded(
            child: Center(
                child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!video) ...[
              AvatarView(
                  width: 80,
                  height: 80,
                  text: nickname.isEmpty ? widget.userInfo?.userID : nickname,
                  url: widget.userInfo?.faceURL),
              const SizedBox(height: 16),
              Text(nickname,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: foreground, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Text(status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: secondary)),
              if (connecting) const SizedBox(height: 16),
              if (connecting)
                const SizedBox(width: 40, height: 40, child: LiveLoadingView()),
            ],
          ]),
        ))),
        if (video)
          Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(status,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: foreground, shadows: [
                    Shadow(color: CallSurfaceTokens.background, blurRadius: 4)
                  ]))),
        if (video && widget.active && _participant != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: IconButton(
                  onPressed:
                      _changingCamera ? null : () => unawaited(_camera()),
                  tooltip: StrRes.camera,
                  color: foreground,
                  icon: Icon(_participant!.isCameraEnabled()
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded))),
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _buttons(foreground)
                .map((button) => Flexible(child: button))
                .toList()),
        const SizedBox(height: 16),
      ]),
    ));
  }

  List<Widget> _buttons(Color foreground) {
    final enabled = widget.active;
    if (!widget.connected && widget.initState == CallState.beCalled) {
      return [
        LiveButton.reject(
            foreground: foreground, onTap: enabled ? widget.onReject : null),
        LiveButton.pickUp(
            foreground: foreground,
            onTap: enabled && _state == CallState.beCalled
                ? widget.onPickUp
                : null),
      ];
    }
    return [
      LiveButton.microphone(
          on: _microphone,
          foreground: foreground,
          onTap: enabled ? () => unawaited(_toggleAudio()) : null),
      widget.connected
          ? LiveButton.hungUp(
              foreground: foreground,
              onTap: enabled ? () => widget.onHangUp?.call(true) : null)
          : LiveButton.cancel(
              foreground: foreground, onTap: enabled ? widget.onCancel : null),
      LiveButton.speaker(
          on: _speaker,
          foreground: foreground,
          onTap: enabled ? () => unawaited(_toggleSpeaker()) : null),
    ];
  }
}
