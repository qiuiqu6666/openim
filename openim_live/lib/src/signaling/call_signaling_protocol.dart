import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// The existing online-only 200..204 wire protocol. Invalid payloads never
/// escape into the SDK message listener or open a room.
class DecodedCallSignal {
  const DecodedCallSignal(this.customType, this.info);

  final int customType;
  final SignalingInfo info;
}

class _TerminalCallSignal extends SignalingInfo {
  _TerminalCallSignal(
      String userID, InvitationInfo invitation, this.terminalState)
      : super(userID: userID, invitation: invitation);

  final String? terminalState;
}

/// New callers use one server-compatible ID for signaling, RTC and reports.
bool validCallID(String? id) =>
    id != null && RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(id);

String encodeCallSignal(int type, InvitationInfo invitation,
        {String? terminalState}) =>
    jsonEncode({
      'customType': type,
      'data': {
        ...invitation.toJson(),
        if (_terminalReason(type, terminalState) != null)
          'terminalState': terminalState,
      },
    });

String? _terminalReason(int type, Object? value) {
  if (value is! String) return null;
  final allowed = switch (type) {
    CustomMessageType.callingReject => const {
        'reject',
        'timeout',
        'networkError'
      },
    CustomMessageType.callingCancel => const {
        'cancel',
        'timeout',
        'networkError'
      },
    CustomMessageType.callingHungup => const {'hangup', 'networkError'},
    _ => const <String>{},
  };
  return allowed.contains(value) ? value : null;
}

/// Preserve the local/remote direction labels used by existing chat bubbles.
/// Only reasons that the legacy reject/cancel wire types could not express
/// replace them; absent or invalid reasons retain the legacy behavior.
String callTerminalRecordState(SignalingInfo info, String fallback) {
  final reason = info is _TerminalCallSignal ? info.terminalState : null;
  return reason == 'timeout' || reason == 'networkError' ? reason! : fallback;
}

DecodedCallSignal? decodeCallSignal(Message message) {
  try {
    final raw = message.customElem?.data;
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final type = decoded['customType'];
    if (type is! int ||
        type < CustomMessageType.callingInvite ||
        type > CustomMessageType.callingHungup) return null;
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) return null;
    final invitation = InvitationInfo.fromJson(data);
    if (!validCallInvitation(invitation)) return null;
    final sender = message.sendID;
    if (sender == null || sender.isEmpty) return null;
    final isInviter = sender == invitation.inviterUserID;
    final isInvitee = invitation.inviteeUserIDList!.contains(sender);
    if (!isInviter && !isInvitee) return null;
    if ((type == CustomMessageType.callingInvite ||
            type == CustomMessageType.callingCancel) &&
        !isInviter) return null;
    if ((type == CustomMessageType.callingAccept ||
            type == CustomMessageType.callingReject) &&
        !isInvitee) return null;
    // SDK sendTime is the message timestamp; use it for legacy invites that
    // omitted initiateTime without extending their lifetime on delivery.
    if (type == CustomMessageType.callingInvite) {
      invitation.initiateTime =
          callTimestampMilliseconds(invitation.initiateTime) ??
              callTimestampMilliseconds(message.sendTime) ??
              DateTime.now().millisecondsSinceEpoch;
    }
    return DecodedCallSignal(
        type,
        _TerminalCallSignal(
            sender, invitation, _terminalReason(type, data['terminalState'])));
  } catch (_) {
    return null;
  }
}

bool validCallInvitation(InvitationInfo? invitation) {
  if (invitation == null ||
      invitation.roomID?.trim().isNotEmpty != true ||
      invitation.inviterUserID?.trim().isNotEmpty != true ||
      !const ['audio', 'video'].contains(invitation.mediaType)) return false;
  final invitees = invitation.inviteeUserIDList;
  if (invitees == null ||
      invitees.isEmpty ||
      invitees
          .any((id) => id.trim().isEmpty || id == invitation.inviterUserID)) {
    return false;
  }
  return invitation.sessionType == ConversationType.single
      ? invitees.length == 1
      : invitation.sessionType == ConversationType.group ||
          invitation.sessionType == ConversationType.superGroup;
}

int? callTimestampMilliseconds(int? timestamp) {
  if (timestamp == null || timestamp <= 0) return null;
  return timestamp < 100000000000 ? timestamp * 1000 : timestamp;
}

DateTime? callInviteDeadline(InvitationInfo? invitation) {
  final start = callTimestampMilliseconds(invitation?.initiateTime);
  if (start == null) return null;
  final seconds = (invitation?.timeout ?? 30).clamp(1, 120).toInt();
  return DateTime.fromMillisecondsSinceEpoch(start)
      .add(Duration(seconds: seconds));
}

/// One active room per account, with bounded tombstones for delayed duplicate
/// invitations/terminal signals. A completed room cannot reopen itself.
class CallSignalGuard {
  String? activeRoomID;
  String? accountID;
  final Set<String> _endedRooms = {};

  bool isEnded(String roomID) => _endedRooms.contains(roomID);

  bool begin(String roomID, String owner) {
    if (accountID != owner) reset(owner);
    if (isEnded(roomID) || activeRoomID != null) return false;
    activeRoomID = roomID;
    return true;
  }

  bool matches(String? roomID, String owner) =>
      roomID != null &&
      accountID == owner &&
      activeRoomID == roomID &&
      !isEnded(roomID);

  bool finish(String roomID, String owner) {
    if (accountID != owner || !_endedRooms.add(roomID)) return false;
    if (_endedRooms.length > 256) _endedRooms.remove(_endedRooms.first);
    return true;
  }

  void release(String roomID) {
    if (activeRoomID == roomID) activeRoomID = null;
  }

  void reset([String? owner]) {
    activeRoomID = null;
    accountID = owner;
    _endedRooms.clear();
  }
}
