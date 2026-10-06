import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import 'call_signaling_protocol.dart';

/// Builds the account's view of the same invitation before asynchronous cleanup.
/// The invitation's room ID and start time are shared by both participants.
CallRecords buildCallRecord({
  required SignalingInfo signaling,
  required String accountID,
  required String state,
  required int duration,
  required bool connected,
  required DateTime endedAt,
  UserInfo? peerInfo,
}) {
  final invitation = signaling.invitation!;
  final incoming = invitation.inviterUserID != accountID;
  final peer = incoming
      ? invitation.inviterUserID!
      : invitation.inviteeUserIDList!.first;
  final end = endedAt.millisecondsSinceEpoch;
  final start = callTimestampMilliseconds(invitation.initiateTime) ?? end;
  final single = invitation.sessionType == ConversationType.single;
  return CallRecords(
    userID: peer,
    nickname: peerInfo?.remark?.trim().isNotEmpty == true
        ? peerInfo!.remark!
        : peerInfo?.nickname ?? '',
    faceURL: peerInfo?.faceURL,
    type: invitation.mediaType!,
    success: connected,
    incomingCall: incoming,
    date: start > end ? end : start,
    duration: connected && duration > 0 ? duration : 0,
    roomID: invitation.roomID,
    state: callTerminalRecordState(signaling, state),
    roomType: single ? 'single' : 'group',
    groupID: single ? '' : invitation.groupID ?? '',
    participantUserIDs: {
      invitation.inviterUserID!,
      ...invitation.inviteeUserIDList!,
    }.toList(growable: false),
    endedAt: end,
  );
}
