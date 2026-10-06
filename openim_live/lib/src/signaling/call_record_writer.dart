import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import 'call_record_snapshot.dart';

typedef CallRecordCallback = Future<void> Function(
    CallRecords record, String accountID);

/// Adapts a claimed terminal result to the existing SDK chat history and the
/// account-scoped recent-calls store. The controller owns the terminal claim.
Future<Message?> writeCallRecord({
  required SignalingInfo signaling,
  required String accountID,
  required String state,
  required int duration,
  required bool connected,
  required bool Function() isCurrentAccount,
  DateTime? endedAt,
  UserInfo? peerInfo,
  CallRecordCallback? onRecord,
}) async {
  final invitation = signaling.invitation!;
  final record = buildCallRecord(
      signaling: signaling,
      accountID: accountID,
      state: state,
      duration: duration,
      connected: connected,
      endedAt: endedAt ?? DateTime.now(),
      peerInfo: peerInfo);
  final seconds = record.duration;
  if (!isCurrentAccount()) return null;
  // Store failure must not suppress a valid chat-history entry, or vice versa.
  try {
    await onRecord?.call(
      record,
      accountID,
    );
  } catch (error) {
    Logger.print('Recent-call record unavailable: ${error.runtimeType}');
  }
  if (!isCurrentAccount()) return null;
  try {
    final message = await OpenIM.iMManager.messageManager.createCustomMessage(
      data: jsonEncode({
        'customType': CustomMessageType.call,
        'data': {
          'roomID': invitation.roomID,
          'duration': seconds,
          'state': record.state,
          'type': invitation.mediaType,
        },
      }),
      extension: '',
      description: '',
    );
    if (!isCurrentAccount()) return null;
    return await OpenIM.iMManager.messageManager
        .insertSingleMessageToLocalStorage(
      receiverID: invitation.inviteeUserIDList!.first,
      senderID: invitation.inviterUserID!,
      message: message
        ..status = 2
        ..isRead = true,
    );
  } catch (error) {
    Logger.print('Call chat-history record unavailable: ${error.runtimeType}');
    return null;
  }
}
