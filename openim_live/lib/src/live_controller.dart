import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import 'live_client.dart';
import 'models/incoming_call_preferences.dart';
import 'signaling/call_error_message.dart';
import 'signaling/call_history_event.dart';
import 'signaling/call_record_writer.dart';
import 'signaling/call_ringtone.dart';
import 'signaling/call_signaling_protocol.dart';
import 'signaling/call_signaling_transport.dart';

export 'signaling/call_signaling_protocol.dart';
export 'signaling/call_history_event.dart';

mixin OpenIMLive {
  final signalingSubject = PublishSubject<CallEvent>();
  final backgroundSubject = PublishSubject<bool>();
  final insertSignalingMessageSubject = PublishSubject<CallEvent>();
  final roomParticipantDisconnectedSubject = PublishSubject<RoomCallingInfo>();
  final roomParticipantConnectedSubject = PublishSubject<RoomCallingInfo>();
  Function(SignalingMessageEvent)? onSignalingMessage;
  CallRecordCallback? onCallRecord;

  final _guard = CallSignalGuard();
  final _ringtone = CallRingtone();
  final _incomingCallPreferences =
      ValueNotifier(const IncomingCallPreferences());
  @protected
  CallRingtone get callRingtone => _ringtone;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _roomAccounts = <String, String>{};
  final _peerProfiles = <String, UserInfo>{};
  SignalingInfo? _activeSignal;
  SignalingInfo? _pendingInvitation;
  Timer? _pendingTimeout;
  DateTime? _connectedAt;
  String? _outgoingWaitingStoppedRoomID;
  String? _incomingWaitingStoppedRoomID;
  Future<SignalingCertificate>? _pickupRequest;
  bool _isRunningBackground = false;
  bool _liveInitialized = false;
  bool _liveClosing = false;
  bool _liveClosed = false;
  int _sessionGeneration = 0;
  Future<void>? _closeLiveRequest;

  bool get isBusy => OpenIMLiveClient().isBusy || _guard.activeRoomID != null;

  /// Applications supply account-local storage through this package boundary.
  @protected
  IncomingCallPreferences preferencesForIncomingCall(String accountID) =>
      const IncomingCallPreferences();

  /// The application may stop an older message alert when this call takes
  /// ownership of attention. The shared call package owns no message player.
  @protected
  void onCallWaitingStarted() {}

  void refreshIncomingCallPreferences() {
    final signal = _activeSignal;
    if (signal == null ||
        _liveClosed ||
        _liveClosing ||
        !_isCurrent(signal) ||
        _connectedAt != null ||
        signal.invitation?.inviterUserID == _owner(signal)) {
      return;
    }
    _incomingCallPreferences.value =
        preferencesForIncomingCall(_owner(signal)!);
    if (_pickupRequest != null ||
        _incomingWaitingStoppedRoomID == signal.invitation?.roomID) {
      return;
    }
    if (_incomingCallPreferences.value.ringtoneEnabled) {
      _run(_playSound(signal));
    } else {
      _run(_stopSound());
    }
  }

  void invitationCancelled(SignalingInfo info) =>
      _receive(CallState.beCanceled, info);
  void inviteeAccepted(SignalingInfo info) =>
      _receive(CallState.beAccepted, info);
  void inviteeRejected(SignalingInfo info) =>
      _receive(CallState.beRejected, info);
  void beHangup(SignalingInfo info) => _receive(CallState.beHangup, info);

  void receiveNewInvitation(SignalingInfo info) {
    if (_liveClosed || _liveClosing || !validCallInvitation(info.invitation)) {
      return;
    }
    final owner = OpenIM.iMManager.userID;
    final invitation = info.invitation!;
    if (owner.isEmpty ||
        !invitation.inviteeUserIDList!.contains(owner) ||
        info.userID != invitation.inviterUserID) {
      return;
    }
    _bindAccount(owner);
    final room = invitation.roomID!;
    if (_guard.isEnded(room) || _guard.activeRoomID == room) {
      return;
    }
    if (invitation.sessionType != ConversationType.single || isBusy) {
      _roomAccounts[room] = owner;
      _run(_declineUnavailable(info));
      return;
    }
    final deadline = callInviteDeadline(invitation);
    if (deadline != null && !deadline.isAfter(DateTime.now())) {
      _roomAccounts[room] = owner;
      _run(onTimeoutCancelled(info, requireActive: false));
      return;
    }
    if (!_guard.begin(room, owner)) {
      return;
    }
    _roomAccounts[room] = owner;
    _activeSignal = info;
    _connectedAt = null;
    _incomingWaitingStoppedRoomID = null;
    _incomingCallPreferences.value = preferencesForIncomingCall(owner);
    onCallWaitingStarted();
    signalingSubject.add(CallEvent(CallState.beCalled, info));
  }

  void _receive(CallState state, SignalingInfo info) {
    if (_liveClosed || _liveClosing || !validCallInvitation(info.invitation))
      return;
    final owner = OpenIM.iMManager.userID;
    final current = _activeSignal?.invitation;
    final invitation = info.invitation!;
    if (!_guard.matches(invitation.roomID, owner) ||
        current == null ||
        current.inviterUserID != invitation.inviterUserID ||
        current.mediaType != invitation.mediaType ||
        current.sessionType != invitation.sessionType ||
        !const ListEquality<String>().equals(
            current.inviteeUserIDList, invitation.inviteeUserIDList)) return;
    final actor = info.userID;
    final peer = current.inviterUserID == owner
        ? current.inviteeUserIDList!.first
        : current.inviterUserID;
    if (actor != peer) return;
    if ((state == CallState.beAccepted || state == CallState.beRejected) &&
        actor == current.inviterUserID) return;
    if (state == CallState.beCanceled && actor != current.inviterUserID) return;
    // Capture the peer response before the async stream. A certificate or room
    // join completing in the same turn must never restart waiting audio.
    if (current.inviterUserID == owner) {
      _outgoingWaitingStoppedRoomID = invitation.roomID;
      _run(_stopSound());
    } else {
      _stopIncomingWaiting(info);
    }
    signalingSubject.add(CallEvent(state, info));
  }

  void onInitLive() {
    if (_liveInitialized || _liveClosed) return;
    _liveInitialized = true;
    _subscriptions
        .add(signalingSubject.listen((event) => _run(_onSignal(event))));
    _subscriptions.add(insertSignalingMessageSubject.listen((event) => _run(
        _recordFinal(event.data, event.state,
            duration: event.fields is int ? event.fields as int : 0))));
    _subscriptions.add(backgroundSubject.listen((background) {
      _isRunningBackground = background;
      if (!background && _pendingInvitation != null) {
        final invitation = _pendingInvitation!;
        _pendingInvitation = null;
        _pendingTimeout?.cancel();
        _pendingTimeout = null;
        _run(_openIncoming(invitation));
      }
    }));
    _subscriptions.add(roomParticipantDisconnectedSubject.listen((info) {
      final room = info.invitation?.roomID ?? info.roomID;
      if (room == OpenIMLiveClient().currentRoomID &&
          (info.participant == null || info.participant!.length <= 1)) {
        _run(OpenIMLiveClient()
            .endActiveCall(notifyPeer: false, reason: 'remoteDisconnected'));
      }
    }));
  }

  Future<void> _onSignal(CallEvent event) async {
    if (_liveClosed) return;
    if (event.state == CallState.beCalled) {
      if (!_isCurrent(event.data)) return;
      _run(_playSound(event.data));
      if (_isRunningBackground) {
        _pendingInvitation = event.data;
        final deadline = callInviteDeadline(event.data.invitation) ??
            DateTime.now().add(const Duration(seconds: 30));
        final remaining = deadline.difference(DateTime.now());
        _pendingTimeout?.cancel();
        _pendingTimeout =
            Timer(remaining.isNegative ? Duration.zero : remaining, () {
          _pendingInvitation = null;
          _run(onTimeoutCancelled(event.data)
              .whenComplete(() => _releaseRoom(event.data)));
        });
      } else {
        await _openIncoming(event.data);
      }
    } else {
      if (_isCurrent(event.data)) {
        _outgoingWaitingStoppedRoomID = event.data.invitation?.roomID;
        await _stopSound();
      }
      if (event.state == CallState.beRejected ||
          event.state == CallState.beCanceled ||
          event.state == CallState.timeout) {
        await _recordFinal(event.data, event.state);
      }
      if (_pendingInvitation?.invitation?.roomID ==
          event.data.invitation?.roomID) {
        if (event.state == CallState.beHangup) {
          await _recordFinal(event.data, CallState.beCanceled);
        }
        if (event.state != CallState.beAccepted) _releaseRoom(event.data);
      }
      // An opened room handles beHangup with its actual connected duration.
    }
  }

  Future<void> _openIncoming(SignalingInfo signal) async {
    if (!_isCurrent(signal)) return;
    final deadline = callInviteDeadline(signal.invitation);
    if (deadline != null && !deadline.isAfter(DateTime.now())) {
      await onTimeoutCancelled(signal);
      _releaseRoom(signal);
      return;
    }
    final owner = _owner(signal)!;
    final context = Get.overlayContext;
    if (context == null) {
      await _declineUnavailable(signal);
      _releaseRoom(signal);
      await _stopSound();
      return;
    }
    final started = OpenIMLiveClient().start(
      context,
      callEventSubject: signalingSubject,
      roomID: signal.invitation!.roomID,
      inviteeUserIDList: signal.invitation!.inviteeUserIDList!,
      inviterUserID: signal.invitation!.inviterUserID!,
      callType: signal.invitation!.mediaType == 'audio'
          ? CallType.audio
          : CallType.video,
      callObj: CallObj.single,
      initState: CallState.beCalled,
      incomingCallPreferences: _incomingCallPreferences,
      onIncomingWaitingEnded: () => _stopIncomingWaiting(signal),
      onSyncUserInfo: onSyncUserInfo,
      onTapPickup: () => onTapPickup(signal),
      onTapReject: () => onTapReject(signal),
      onTapHangup: (duration, positive) =>
          onTapHangup(signal, duration, positive),
      onTimeout: () => onTimeoutCancelled(signal),
      ringingTimeout:
          deadline?.difference(DateTime.now()) ?? const Duration(seconds: 30),
      onStartCalling: () => _markConnected(signal),
      onError: (error, stack) => _onCallError(signal, owner, error, stack),
      onRoomDisconnected: () => onRoomDisconnected(signal),
      onClose: () => _releaseRoom(signal),
    );
    if (!started) {
      await _declineUnavailable(signal);
      _releaseRoom(signal);
      await _stopSound();
    }
  }

  Future<void> call(
      {required CallObj callObj,
      required CallType callType,
      CallState callState = CallState.call,
      String? roomID,
      String? inviterUserID,
      required List<String> inviteeUserIDList,
      String? groupID,
      SignalingCertificate? credentials}) async {
    if (_liveClosed || _liveClosing) return;
    if (callObj != CallObj.single) {
      IMViews.showToast(Get.locale?.languageCode == 'en'
          ? 'Group calls are not supported yet'
          : '暂不支持群聊通话');
      return;
    }
    if (isBusy) {
      onBusyLine();
      return;
    }
    final owner = OpenIM.iMManager.userID;
    if (owner.isEmpty) return;
    final sharedCallID = roomID ?? const Uuid().v4();
    if (!validCallID(sharedCallID)) {
      IMViews.showToast(StrRes.callFail);
      return;
    }
    final signal = SignalingInfo(
        userID: owner,
        invitation: InvitationInfo(
          inviterUserID: owner,
          inviteeUserIDList: inviteeUserIDList,
          roomID: sharedCallID,
          timeout: 30,
          initiateTime: DateTime.now().millisecondsSinceEpoch,
          mediaType: callType == CallType.audio ? 'audio' : 'video',
          sessionType: ConversationType.single,
          platformID: IMUtils.getPlatform(),
        ));
    if (!validCallInvitation(signal.invitation)) {
      IMViews.showToast(StrRes.callFail);
      return;
    }
    _bindAccount(owner);
    if (!_guard.begin(signal.invitation!.roomID!, owner)) return;
    _roomAccounts[signal.invitation!.roomID!] = owner;
    _activeSignal = signal;
    _connectedAt = null;
    _outgoingWaitingStoppedRoomID = null;
    onCallWaitingStarted();
    final context = Get.overlayContext;
    if (context == null) {
      _releaseRoom(signal);
      return;
    }
    final started = OpenIMLiveClient().start(
      context,
      callEventSubject: signalingSubject,
      roomID: signal.invitation!.roomID,
      inviterUserID: owner,
      inviteeUserIDList: inviteeUserIDList,
      callObj: CallObj.single,
      callType: callType,
      initState: callState,
      onDialSingle: () => onDialSingle(signal),
      onTapCancel: () => onTapCancel(signal),
      onTapHangup: (duration, positive) =>
          onTapHangup(signal, duration, positive),
      onSyncUserInfo: onSyncUserInfo,
      onWaitingAccept: () => _run(_playSound(signal, outgoing: true)),
      onBusyLine: onBusyLine,
      onStartCalling: () => _markConnected(signal),
      onTimeout: () => onTimeoutCancelled(signal),
      onError: (error, stack) => _onCallError(signal, owner, error, stack),
      onRoomDisconnected: () => onRoomDisconnected(signal),
      onClose: () => _releaseRoom(signal),
    );
    if (!started) _releaseRoom(signal);
  }

  Future<SignalingCertificate> onDialSingle(SignalingInfo signal) async {
    _ensureCurrent(signal);
    await _sendSignal(CustomMessageType.callingInvite, signal);
    _ensureCurrent(signal);
    final certificate = await requestRtcCertificate(
        signal.invitation!.roomID!, _owner(signal)!);
    _ensureCurrent(signal);
    // Permissions precede onDialSingle; do not ring until invite delivery and
    // credentials succeed. Audio loading must never hold up media connection.
    _run(_playSound(signal, outgoing: true));
    return certificate;
  }

  Future<SignalingCertificate> onTapPickup(SignalingInfo signal) {
    final pending = _pickupRequest;
    if (pending != null) return pending;
    late final Future<SignalingCertificate> request;
    request = _pickup(signal).whenComplete(() {
      if (identical(_pickupRequest, request)) _pickupRequest = null;
    });
    return _pickupRequest = request;
  }

  Future<SignalingCertificate> _pickup(SignalingInfo signal) async {
    _ensureCurrent(signal);
    _incomingWaitingStoppedRoomID = signal.invitation!.roomID;
    _pendingInvitation = null;
    _pendingTimeout?.cancel();
    await _stopSound();
    final certificate = await requestRtcCertificate(
        signal.invitation!.roomID!, _owner(signal)!);
    _ensureCurrent(signal);
    await _sendSignal(CustomMessageType.callingAccept, signal);
    _ensureCurrent(signal);
    return certificate;
  }

  Future<void> onTapReject(SignalingInfo signal) =>
      _endSignal(signal, CallState.reject, CustomMessageType.callingReject);
  Future<void> onTapCancel(SignalingInfo signal) =>
      _endSignal(signal, CallState.cancel, CustomMessageType.callingCancel);
  Future<void> onTapHangup(SignalingInfo signal, int duration, bool positive) =>
      _endSignal(signal, CallState.hangup,
          positive ? CustomMessageType.callingHungup : null,
          duration: duration);
  Future<void> onTimeoutCancelled(SignalingInfo signal,
          {bool requireActive = true}) =>
      _endSignal(
          signal,
          CallState.timeout,
          signal.invitation!.inviterUserID == _owner(signal)
              ? CustomMessageType.callingCancel
              : CustomMessageType.callingReject,
          requireActive: requireActive);

  Future<void> _endSignal(SignalingInfo signal, CallState state, int? type,
      {int duration = 0,
      bool requireActive = true,
      bool showSendError = true}) async {
    final owner = _owner(signal);
    final room = signal.invitation?.roomID;
    final generation = _sessionGeneration;
    if (owner == null || room == null || _guard.isEnded(room)) return;
    if (requireActive && !_guard.matches(room, owner)) return;
    final isActiveRoom = _guard.activeRoomID == room;
    // Claim before an awaited send: double taps/signals cannot send a second
    // terminal signal or write a second final record.
    if (!_guard.finish(room, owner)) return;
    final endedAt = DateTime.now();
    if (isActiveRoom) await _stopSound();
    if (type != null) {
      try {
        await _sendSignal(type, signal,
            requireActive: false, terminalState: state.name);
      } catch (error) {
        if (error is! CallRequestCancelled &&
            showSendError &&
            !_liveClosing &&
            !_liveClosed &&
            owner == OpenIM.iMManager.userID) {
          IMViews.showToast(callErrorMessage(error));
        }
      }
    }
    await _writeFinal(signal, state, owner, duration,
        generation: generation, endedAt: endedAt);
  }

  Future<void> _declineUnavailable(SignalingInfo signal) async {
    final invitation = signal.invitation!;
    if (invitation.sessionType == ConversationType.single) {
      await _endSignal(
          signal, CallState.reject, CustomMessageType.callingReject,
          requireActive: false);
    } else if (_guard.finish(invitation.roomID!, _owner(signal)!)) {
      try {
        await _sendSignal(CustomMessageType.callingReject, signal,
            requireActive: false);
      } catch (error) {
        Logger.print('Unavailable call reject failed: ${error.runtimeType}');
      }
    }
  }

  Future<void> _sendSignal(int type, SignalingInfo signal,
      {bool requireActive = true, String? terminalState}) async {
    final generation = _sessionGeneration;
    final owner = _owner(signal);
    if (owner == null || _liveClosed || owner != OpenIM.iMManager.userID) {
      throw const CallRequestCancelled();
    }
    if (requireActive) _ensureCurrent(signal);
    final invitation = signal.invitation!;
    final receiver = invitation.inviterUserID == owner
        ? invitation.inviteeUserIDList!.first
        : invitation.inviterUserID!;
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
      data: encodeCallSignal(type, invitation, terminalState: terminalState),
      extension: '',
      description: '',
    );
    if (owner != OpenIM.iMManager.userID ||
        _liveClosed ||
        generation != _sessionGeneration) {
      throw const CallRequestCancelled();
    }
    if (requireActive) _ensureCurrent(signal);
    await OpenIM.iMManager.messageManager.sendMessage(
        message: message,
        offlinePushInfo: OfflinePushInfo(),
        userID: receiver,
        isOnlineOnly: true);
  }

  Future<void> _recordFinal(SignalingInfo signal, CallState state,
      {int duration = 0}) async {
    final owner = _owner(signal);
    final room = signal.invitation?.roomID;
    if (owner == null || room == null || !_guard.finish(room, owner)) return;
    await _writeFinal(signal, state, owner, duration);
  }

  Future<void> _writeFinal(
      SignalingInfo signal, CallState state, String owner, int duration,
      {int? generation, DateTime? endedAt}) async {
    final capturedGeneration = generation ?? _sessionGeneration;
    bool currentAccount() =>
        !_liveClosed &&
        capturedGeneration == _sessionGeneration &&
        owner == OpenIM.iMManager.userID &&
        _owner(signal) == owner;
    final invitation = signal.invitation!;
    final peer = invitation.inviterUserID == owner
        ? invitation.inviteeUserIDList!.first
        : invitation.inviterUserID!;
    final connected = _connectedAt != null &&
        _activeSignal?.invitation?.roomID == invitation.roomID;
    final end = endedAt ?? DateTime.now();
    final seconds = connected && duration == 0
        ? end.difference(_connectedAt!).inSeconds
        : duration;
    final original = _activeSignal?.invitation?.roomID == invitation.roomID
        ? _activeSignal!
        : signal;
    final message = await writeCallRecord(
        signaling: original,
        accountID: owner,
        state: callTerminalRecordState(signal, state.name),
        duration: seconds,
        connected: connected,
        endedAt: end,
        peerInfo: _peerProfiles[peer],
        isCurrentAccount: currentAccount,
        onRecord: onCallRecord);
    if (message != null && currentAccount()) {
      onSignalingMessage?.call(
          SignalingMessageEvent(message, ConversationType.single, peer, null));
    }
  }

  Future<void> _onCallError(
      SignalingInfo signal, String owner, Object error, Object? stack) async {
    if (_isCurrent(signal)) await _stopSound();
    if (error is CallRequestCancelled ||
        owner != OpenIM.iMManager.userID ||
        _liveClosed) return;
    Logger.print('Call failed: ${error.runtimeType}');
    final connected = _connectedAt != null;
    final outgoing = signal.invitation!.inviterUserID == owner;
    await _endSignal(
        signal,
        CallState.networkError,
        connected
            ? CustomMessageType.callingHungup
            : outgoing
                ? CustomMessageType.callingCancel
                : CustomMessageType.callingReject,
        showSendError: false);
    if (!_liveClosing) IMViews.showToast(callErrorMessage(error));
  }

  Future<void> onRoomDisconnected(SignalingInfo signal) async {
    if (_isCurrent(signal)) await _stopSound();
    await _recordFinal(signal,
        _connectedAt == null ? CallState.networkError : CallState.hangup,
        duration: _connectedAt == null
            ? 0
            : DateTime.now().difference(_connectedAt!).inSeconds);
  }

  void onBusyLine() => IMViews.showToast(StrRes.busyVideoCallHint);
  void onJoin() {}

  Future<UserInfo?> onSyncUserInfo(String userID) async {
    final generation = _sessionGeneration;
    final list =
        await OpenIM.iMManager.userManager.getUsersInfo(userIDList: [userID]);
    final info = list.firstOrNull?.simpleUserInfo;
    if (!_liveClosed && generation == _sessionGeneration && info != null)
      _peerProfiles[userID] = info;
    return info;
  }

  Future<GroupInfo?> onSyncGroupInfo(String groupID) async =>
      (await OpenIM.iMManager.groupManager
              .getGroupsInfo(groupIDList: [groupID]))
          .firstOrNull;
  Future<List<GroupMembersInfo>> onSyncGroupMemberInfo(
          String groupID, List<String> userIDList) =>
      OpenIM.iMManager.groupManager
          .getGroupMembersInfo(groupID: groupID, userIDList: userIDList);

  void _markConnected(SignalingInfo signal) {
    if (!_isCurrent(signal)) return;
    _connectedAt ??= DateTime.now();
    _run(_stopSound());
  }

  Future<void> _playSound(SignalingInfo signal, {bool outgoing = false}) async {
    if (_liveClosed ||
        _liveClosing ||
        _activeSignal?.invitation?.roomID != signal.invitation?.roomID ||
        !_isCurrent(signal) ||
        _connectedAt != null) {
      return;
    }
    final isCaller = signal.invitation!.inviterUserID == _owner(signal);
    if (outgoing != isCaller ||
        (!outgoing &&
            _incomingWaitingStoppedRoomID == signal.invitation!.roomID) ||
        (!outgoing &&
            !preferencesForIncomingCall(_owner(signal)!).ringtoneEnabled) ||
        (outgoing &&
            _outgoingWaitingStoppedRoomID == signal.invitation!.roomID)) {
      return;
    }
    try {
      await callRingtone.play(
          tone: outgoing ? CallWaitingTone.outgoing : CallWaitingTone.incoming);
    } catch (error) {
      Logger.print('Call ring unavailable: ${error.runtimeType}');
    }
  }

  Future<void> _stopSound() async {
    try {
      await callRingtone.stop();
    } catch (error) {
      Logger.print('Call ring stop unavailable: ${error.runtimeType}');
    }
  }

  void _stopIncomingWaiting(SignalingInfo signal) {
    if (!_isCurrent(signal)) {
      return;
    }
    _incomingWaitingStoppedRoomID = signal.invitation?.roomID;
    _run(_stopSound());
  }

  String? _owner(SignalingInfo signal) =>
      _roomAccounts[signal.invitation?.roomID];
  bool _isCurrent(SignalingInfo signal) =>
      !_liveClosed &&
      _guard.matches(signal.invitation?.roomID, OpenIM.iMManager.userID);
  void _ensureCurrent(SignalingInfo signal) {
    if (!_isCurrent(signal)) throw const CallRequestCancelled();
  }

  void _bindAccount(String owner) {
    if (_guard.accountID == owner) return;
    _run(_stopSound());
    _outgoingWaitingStoppedRoomID = null;
    _incomingWaitingStoppedRoomID = null;
    _sessionGeneration++;
    _guard.reset(owner);
    _roomAccounts.clear();
    _peerProfiles.clear();
  }

  void _releaseRoom(SignalingInfo signal) {
    final room = signal.invitation?.roomID;
    if (room == null) return;
    _guard.release(room);
    if (_activeSignal?.invitation?.roomID != room) return;
    _activeSignal = null;
    _connectedAt = null;
    _outgoingWaitingStoppedRoomID = null;
    _incomingWaitingStoppedRoomID = null;
    _pendingInvitation = null;
    _pendingTimeout?.cancel();
    _pendingTimeout = null;
    _pickupRequest = null;
    _run(_stopSound());
  }

  void _run(Future<void> task) =>
      unawaited(task.catchError((Object error, StackTrace stack) {
        Logger.print('Call background task failed: ${error.runtimeType}');
      }));

  Future<void> endLiveSession({bool notifyPeer = true}) async {
    final wasClosing = _liveClosing;
    _liveClosing = true;
    try {
      await OpenIMLiveClient()
          .endActiveCall(notifyPeer: notifyPeer, reason: 'sessionEnded');
    } catch (error) {
      Logger.print('Call session cleanup failed: ${error.runtimeType}');
    }
    final pending = _pendingInvitation;
    if (pending != null)
      await _endSignal(pending, CallState.reject,
          notifyPeer ? CustomMessageType.callingReject : null);
    await _stopSound();
    _pendingTimeout?.cancel();
    _pendingTimeout = null;
    _pendingInvitation = null;
    _activeSignal = null;
    _connectedAt = null;
    _outgoingWaitingStoppedRoomID = null;
    _incomingWaitingStoppedRoomID = null;
    _pickupRequest = null;
    _sessionGeneration++;
    _guard.reset();
    _roomAccounts.clear();
    _peerProfiles.clear();
    _liveClosing = wasClosing;
  }

  Future<void> onCloseLive() => _closeLiveRequest ??= _disposeLive();
  Future<void> _disposeLive() async {
    _liveClosing = true;
    await endLiveSession();
    _liveClosed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await Future.wait([
      signalingSubject.close(),
      backgroundSubject.close(),
      insertSignalingMessageSubject.close(),
      roomParticipantDisconnectedSubject.close(),
      roomParticipantConnectedSubject.close()
    ]);
    await callRingtone.dispose();
    _incomingCallPreferences.dispose();
    onCallRecord = null;
    onSignalingMessage = null;
  }
}

class CallRequestCancelled implements Exception {
  const CallRequestCancelled();
}
