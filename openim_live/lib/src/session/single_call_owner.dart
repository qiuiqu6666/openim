import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

import '../models/call_errors.dart';
import '../models/call_types.dart';
import '../platform/system_call_adapter.dart';
import 'single_call_media.dart';
import 'single_call_session.dart';

/// The single session and RTC owner, independent of Widget/frame admission.
class SingleCallOwner extends ChangeNotifier {
  SingleCallOwner({
    required this.call,
    required this.initialState,
    required this.events,
    required this.isCurrentAccount,
    required this.certificate,
    required this.onTerminated,
    required this.onClosed,
    this.systemCalls,
    this.onWaitingAccept,
    this.onStartCalling,
    this.onIncomingWaitingEnded,
    SingleCallMedia? media,
    Future<void> Function(CallType)? permissions,
  })  : media = media ??
            LiveKitSingleCallMedia(
              peerUserID: call.peerUserID,
              callType: call.callType,
              systemAudio: systemCalls != null,
            ),
        _permissions = permissions ?? _requestPermissions {
    session = SingleCallSession(
      initialState: initialState,
      connect: _connect,
      release: _release,
      onTerminated: _terminated,
      onClosed: onClosed,
      ringingTimeout: call.deadline == null
          ? const Duration(seconds: 30)
          : call.deadline!.difference(DateTime.now()),
    )..addListener(_sessionChanged);
    this.media.onDisconnected = () => unawaited(session.end(
          session.connected ? CallState.beHangup : CallState.networkError,
          notifyPeer: false,
        ));
    this.media.onReconnecting = session.reconnecting;
    this.media.addListener(_mediaChanged);
    _signals = events
        .where((event) => event.data.invitation?.roomID == call.roomID)
        .listen(_onSignal);
  }

  final SystemCallDescriptor call;
  final CallState initialState;
  final PublishSubject<CallEvent> events;
  final bool Function() isCurrentAccount;
  final Future<SignalingCertificate> Function(bool outgoing) certificate;
  final Future<void> Function(CallTermination) onTerminated;
  final VoidCallback onClosed;
  final VoidCallback? onWaitingAccept, onStartCalling, onIncomingWaitingEnded;
  final SystemCallAdapter? systemCalls;
  final SingleCallMedia media;
  final Future<void> Function(CallType) _permissions;
  late final SingleCallSession session;
  StreamSubscription<CallEvent>? _signals;
  bool _started = false, _disposed = false, _connectedReported = false;
  Future<bool>? _answer;
  bool _waitingStopped = false;
  bool _uiAnswerRequested = false;
  bool microphoneEnabled = true;
  late bool speakerEnabled = call.callType == CallType.video;
  final _releaseHooks = <Future<void> Function()>[];

  bool get current => !_disposed && session.active && isCurrentAccount();

  static Future<void> _requestPermissions(CallType type) async {
    final required = [
      Permission.microphone,
      if (type == CallType.video) Permission.camera,
    ];
    final granted = await Permissions.request(required);
    for (final permission in required) {
      if (granted[permission] != PermissionStatus.granted) {
        throw CallPermissionDenied(permission == Permission.camera
            ? StrRes.camera
            : StrRes.microphone);
      }
    }
  }

  Future<void> start({bool autoPickup = false}) async {
    if (_started || !current) return;
    _started = true;
    session.armDeadline();
    try {
      if (systemCalls != null) {
        if (call.incoming) {
          await systemCalls!.reportIncoming(call);
        } else {
          await systemCalls!.startOutgoing(call);
        }
      }
      if (!current) return;
      if (!call.incoming) {
        await session.dial();
      } else if (autoPickup) {
        await acceptFromUI();
      }
    } catch (error, stack) {
      if (current) {
        await session.end(CallState.networkError,
            error: error, stackTrace: stack);
      }
    }
  }

  Future<void> _connect(CallAttempt attempt, bool outgoing) async {
    _ensure(attempt);
    await _permissions(call.callType);
    _ensure(attempt);
    final credentials = await certificate(outgoing);
    _ensure(attempt);
    if (credentials.roomID != call.roomID) {
      throw const InvalidCallCertificate();
    }
    await media.connect(credentials, attempt);
    _ensure(attempt);
    if (systemCalls != null) {
      // Native fulfills its validated Answer/Start action here. Waiting for
      // audio before this callback would deadlock CallKit's activation.
      await systemCalls!.transportConnected(call);
      _ensure(attempt);
      await systemCalls!.waitForAudio(call);
      _ensure(attempt);
    }
    await media.publish(attempt);
    _ensure(attempt);
    if (!session.connected) onWaitingAccept?.call();
  }

  void _ensure(CallAttempt attempt) {
    if (!attempt.isCurrent || !current) throw const CallRequestCancelled();
  }

  Future<bool> acceptFromSystem() {
    if (!current || !call.incoming) return Future.value(false);
    return _answer ??= () async {
      await session.accept();
      return current;
    }();
  }

  Future<void> acceptFromUI() async {
    if (!current || !call.incoming) return;
    if (systemCalls == null) {
      await session.accept();
    } else {
      if (_uiAnswerRequested) return;
      _uiAnswerRequested = true;
      try {
        final requested = await systemCalls!.requestAnswer(call);
        if (!requested && current) {
          await session.end(CallState.networkError,
              error: StateError('System answer unavailable'));
        }
      } catch (error, stack) {
        if (current) {
          await session.end(CallState.networkError,
              error: error, stackTrace: stack);
        }
      }
    }
  }

  Future<void> end({bool notifyPeer = true, String? reason}) => session.end(
        session.connected
            ? CallState.hangup
            : call.incoming
                ? CallState.reject
                : CallState.cancel,
        notifyPeer: notifyPeer,
      );

  Future<bool> setMicrophone(bool enabled) async {
    if (!current) return false;
    if (microphoneEnabled == enabled) return current;
    microphoneEnabled = enabled;
    await media.setMicrophone(enabled);
    if (current) {
      notifyListeners();
      await systemCalls?.microphoneChanged(call, enabled);
    }
    return current;
  }

  Future<bool> setSpeaker(bool enabled) async {
    if (!current) return false;
    if (speakerEnabled == enabled) return current;
    await media.setSpeaker(enabled);
    if (current) {
      await systemCalls?.speakerChanged(call, enabled);
      if (current) {
        speakerEnabled = enabled;
        notifyListeners();
      }
    }
    return current;
  }

  void addReleaseHook(Future<void> Function() hook) => _releaseHooks.add(hook);
  void removeReleaseHook(Future<void> Function() hook) =>
      _releaseHooks.remove(hook);

  Future<void> _release() => Future.wait([
        media.release(),
        for (final hook in _releaseHooks.toList()) Future<void>.sync(hook),
      ]).then((_) {});

  void _onSignal(CallEvent event) {
    if (!current) return;
    switch (event.state) {
      case CallState.beAccepted:
        session.peerAccepted();
        break;
      case CallState.beRejected:
      case CallState.beCanceled:
      case CallState.beHangup:
      case CallState.otherAccepted:
      case CallState.otherReject:
      case CallState.timeout:
        unawaited(session.end(event.state, notifyPeer: false));
        break;
      default:
        break;
    }
  }

  void _mediaChanged() {
    if (!current) return;
    if (media.ready && media.peerPresent) session.peerConnected();
    notifyListeners();
  }

  void _sessionChanged() {
    if (_disposed) return;
    if (call.incoming &&
        session.state != CallState.beCalled &&
        !_waitingStopped) {
      _waitingStopped = true;
      onIncomingWaitingEnded?.call();
    }
    if (session.connected && !_connectedReported) {
      _connectedReported = true;
      onStartCalling?.call();
      if (systemCalls != null) unawaited(_reportConnected());
    }
    notifyListeners();
  }

  Future<void> _reportConnected() async {
    try {
      await systemCalls!.peerConnected(call);
    } catch (error) {
      Logger.print('System call status: ${error.runtimeType}');
    }
  }

  Future<void> _terminated(CallTermination result) async {
    await Future.wait([
      onTerminated(result),
      if (systemCalls != null) _endSystemCall(result),
    ]);
  }

  Future<void> _endSystemCall(CallTermination result) async {
    // Signaling ends immediately above; restoring the shared native audio
    // session must wait until this owner's old RTC tracks/room are released.
    await media.release();
    await systemCalls!.callEnded(call, result);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _signals?.cancel();
    media.removeListener(_mediaChanged);
    session.removeListener(_sessionChanged);
    session.dispose();
    media.dispose();
    super.dispose();
  }
}
