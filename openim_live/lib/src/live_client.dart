import 'dart:async';
import 'package:flutter/foundation.dart' show ValueListenable;

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'models/call_types.dart';
import 'models/incoming_call_preferences.dart';
import 'pages/single/room.dart';
import 'pages/single/widgets/call_state.dart';

export 'models/call_types.dart';

class OpenIMLiveClient implements RTCBridge {
  OpenIMLiveClient._();
  static final OpenIMLiveClient singleton = OpenIMLiveClient._();
  factory OpenIMLiveClient() {
    PackageBridge.rtcBridge = singleton;
    return singleton;
  }

  @override
  bool get hasConnection => isBusy;
  @override
  void dismiss() => unawaited(endActiveCall(reason: 'dismiss'));

  OverlayEntry? _holder;
  bool isBusy = false;
  String? currentRoomID;
  int _generation = 0;
  EndCall? _end;
  Future<void>? _ending;
  Future<void>? _finishing;
  Future<void>? _enablingWakelock;
  Future Function()? _cancelBeforeMount;
  VoidCallback? _onClose;

  Future<void> quitClose(String roomID) =>
      currentRoomID == roomID ? endActiveCall(reason: 'quit') : Future.value();

  Future<void> closeByRoomID(String roomID) => currentRoomID == roomID
      ? endActiveCall(notifyPeer: false)
      : Future.value();

  Future<void> close() => endActiveCall(notifyPeer: false);

  Future<void> endActiveCall({bool notifyPeer = true, String? reason}) {
    if (_ending != null) return _ending!;
    if (!isBusy) return Future.value();
    final generation = _generation;
    final completion = Completer<void>();
    _ending = completion.future;
    // External exits also work before the room widget binds its end callback.
    // Hide the surface now; _finish still owns the busy/media cleanup barrier.
    _holder?.remove();
    _holder = null;
    unawaited(() async {
      try {
        final end = _end;
        if (end != null) {
          await end(notifyPeer: notifyPeer, reason: reason);
        } else if (notifyPeer) {
          await _cancelBeforeMount?.call();
        }
      } catch (e) {
        Logger.print('Call shutdown: ${e.runtimeType}');
      } finally {
        await _finish(generation);
        if (generation == _generation) _ending = null;
        completion.complete();
      }
    }());
    return completion.future;
  }

  Future<void> _finish(int generation) {
    if (generation != _generation || !isBusy) return Future.value();
    return _finishing ??= _finishResources(generation);
  }

  Future<void> _finishResources(int generation) async {
    if (generation != _generation || !isBusy) return;
    _holder?.remove();
    _holder = null;
    _end = null;
    _cancelBeforeMount = null;
    final onClose = _onClose;
    _onClose = null;
    final enablingWakelock = _enablingWakelock;
    _enablingWakelock = null;
    try {
      onClose?.call();
    } catch (e) {
      Logger.print('Call close callback: ${e.runtimeType}');
    }
    try {
      // A quick cancellation must not disable before a late enable finishes.
      // Admission remains busy until both operations have settled.
      try {
        await enablingWakelock;
      } catch (e) {
        Logger.print('Call wakelock enable cleanup: ${e.runtimeType}');
      }
      await WakelockPlus.disable();
    } catch (e) {
      Logger.print('Call wakelock cleanup: ${e.runtimeType}');
    } finally {
      if (generation == _generation) {
        isBusy = false;
        currentRoomID = null;
      }
    }
  }

  bool start(
    BuildContext ctx, {
    required PublishSubject<CallEvent> callEventSubject,
    String? roomID,
    CallState initState = CallState.call,
    CallType callType = CallType.video,
    CallObj callObj = CallObj.single,
    required String inviterUserID,
    required List<String> inviteeUserIDList,
    String? groupID,
    Future<SignalingCertificate> Function()? onDialSingle,
    Future<SignalingCertificate> Function()? onDialGroup,
    Future<SignalingCertificate> Function()? onJoinGroup,
    Future<SignalingCertificate> Function()? onTapPickup,
    Future Function()? onTapCancel,
    Future Function(int duration, bool isPositive)? onTapHangup,
    Future Function()? onTapReject,
    Future Function()? onTimeout,
    Future<UserInfo?> Function(String userID)? onSyncUserInfo,
    Future<GroupInfo?> Function(String groupID)? onSyncGroupInfo,
    Future<List<GroupMembersInfo>> Function(
            String groupID, List<String> memberIDList)?
        onSyncGroupMemberInfo,
    bool autoPickup = false,
    ValueListenable<IncomingCallPreferences>? incomingCallPreferences,
    VoidCallback? onIncomingWaitingEnded,
    VoidCallback? onWaitingAccept,
    onBusyLine,
    onStartCalling,
    onClose,
    Function(dynamic error, dynamic stack)? onError,
    VoidCallback? onRoomDisconnected,
    Duration ringingTimeout = const Duration(seconds: 30),
  }) {
    if (isBusy || _ending != null) return false;
    if (callObj != CallObj.single ||
        inviteeUserIDList.length != 1 ||
        roomID == null ||
        roomID.isEmpty ||
        inviterUserID.isEmpty) {
      return false;
    }
    // Get 4.x can supply the Navigator's overlay theater context, outside an
    // OverlayEntry. Newer Flutter only resolves Overlay.maybeOf inside an
    // entry marker; use this same context's Navigator, never another window.
    final overlay = Overlay.maybeOf(ctx) ?? Navigator.maybeOf(ctx)?.overlay;
    if (overlay == null) return false;
    final generation = ++_generation;
    _finishing = null;
    isBusy = true;
    currentRoomID = roomID;
    _onClose = onClose;
    _cancelBeforeMount =
        initState == CallState.call ? onTapCancel : onTapReject;
    FocusScope.of(ctx).unfocus();
    _holder = OverlayEntry(
        builder: (_) => SingleRoomView(
              callType: callType,
              initState: initState,
              callEventSubject: callEventSubject,
              roomID: roomID,
              userID: initState == CallState.call
                  ? inviteeUserIDList.first
                  : inviterUserID,
              onDial: onDialSingle,
              onTapCancel: onTapCancel,
              onTapHangup: onTapHangup,
              onTapReject: onTapReject,
              onTapPickup: onTapPickup,
              onTimeout: onTimeout,
              onSyncUserInfo: onSyncUserInfo,
              autoPickup: autoPickup,
              incomingCallPreferences: incomingCallPreferences,
              onIncomingWaitingEnded: onIncomingWaitingEnded,
              ringingTimeout: ringingTimeout,
              onBindRoomID: (id) {
                if (generation == _generation && isBusy) currentRoomID = id;
              },
              onBindEnd: (end) {
                if (generation == _generation && isBusy) {
                  _end = end;
                } else {
                  unawaited(end(notifyPeer: false, reason: 'stale'));
                }
              },
              onWaitingAccept: onWaitingAccept,
              onBusyLine: onBusyLine,
              onStartCalling: onStartCalling,
              onError: onError,
              onRoomDisconnected: onRoomDisconnected,
              onClose: () => unawaited(_finish(generation)),
            ));
    overlay.insert(_holder!);
    _enablingWakelock =
        Future<void>.sync(WakelockPlus.enable).catchError((Object e) {
      Logger.print('Call wakelock: ${e.runtimeType}');
    });
    unawaited(_enablingWakelock!);
    return true;
  }
}
