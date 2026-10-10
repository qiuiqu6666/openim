import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';

/// A timed, single-user invitation addressed to the current SDK account.
/// Receipt time is never used as the invitation's original start time.
class IOSCallInvitation {
  IOSCallInvitation._({
    required this.accountID,
    required this.roomID,
    required this.invitation,
    required this.callerName,
    required this.expiresAt,
  });

  static const maxFutureSkew = Duration(seconds: 5);

  final String accountID;
  final String roomID;
  final InvitationInfo invitation;
  final String callerName;
  final DateTime expiresAt;

  bool isExpired({DateTime? now}) =>
      !(now ?? DateTime.now()).isBefore(expiresAt);

  static IOSCallInvitation? decode(
    Object? raw, {
    required String accountID,
    DateTime? now,
  }) {
    try {
      if (accountID.isEmpty || accountID.trim() != accountID) return null;
      final payload = _payload(raw);
      if (payload == null || _isTerminal(payload)) return null;

      final recipient = payload.containsKey('recipientUserID')
          ? payload['recipientUserID']
          : payload['calleeId'];
      if (recipient is! String || recipient != accountID) return null;

      final Map<String, dynamic>? data;
      if (payload.containsKey('invitation')) {
        data = _map(payload['invitation']);
      } else {
        // Legacy native fields describe a single caller/callee pair. They
        // still need a real start and timeout, rather than a receipt clock.
        data = {
          'roomID': payload['roomId'] ?? payload['callId'],
          'inviterUserID': payload['callerId'],
          'inviteeUserIDList': [payload['calleeId']],
          'mediaType': payload['mediaType'],
          'sessionType': payload['sessionType'] ?? ConversationType.single,
          'initiateTime': payload['initiateTime'] ?? payload['sentAtMs'],
          'timeout': payload['timeout'] ?? payload['timeoutSec'],
          'groupID': payload['groupID'] ?? payload['groupId'],
        };
      }
      if (data == null) return null;
      final room = data['roomID'];
      final caller = data['inviterUserID'];
      final invitees = data['inviteeUserIDList'];
      final media = data['mediaType'];
      final sessionType = _integer(data['sessionType']);
      final timeout = _integer(data['timeout']);
      final start = callTimestampMilliseconds(_integer(data['initiateTime']));
      final group = data['groupID'];
      if (room is! String ||
          !validCallID(room) ||
          caller is! String ||
          caller.isEmpty ||
          caller.trim() != caller ||
          caller == accountID ||
          invitees is! List ||
          invitees.length != 1 ||
          invitees.single != accountID ||
          !const ['audio', 'video'].contains(media) ||
          sessionType != ConversationType.single ||
          timeout == null ||
          timeout < 1 ||
          timeout > 120 ||
          start == null ||
          (group != null && group != '')) {
        return null;
      }

      final clock = now ?? DateTime.now();
      if (start > clock.millisecondsSinceEpoch + maxFutureSkew.inMilliseconds) {
        return null;
      }
      final expiresAt =
          DateTime.fromMillisecondsSinceEpoch(start + timeout * 1000);
      if (!clock.isBefore(expiresAt)) return null;
      final invitation = InvitationInfo(
        roomID: room,
        inviterUserID: caller,
        inviteeUserIDList: [accountID],
        mediaType: media as String,
        sessionType: sessionType,
        initiateTime: start,
        timeout: timeout,
        groupID: group as String?,
        platformID: _integer(data['platformID']),
      );
      if (!validCallInvitation(invitation)) return null;
      final name = payload['callerName'];
      return IOSCallInvitation._(
        accountID: accountID,
        roomID: room,
        invitation: invitation,
        callerName:
            name is String && name.trim().isNotEmpty ? name.trim() : caller,
        expiresAt: expiresAt,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _payload(Object? raw) {
    var result = _map(raw);
    // Bound envelope traversal, including pathological self-referencing maps.
    for (var depth = 0; depth < 4; depth++) {
      if (result == null || !result.containsKey('data')) return result;
      result = _map(result['data']);
    }
    return null;
  }

  static Map<String, dynamic>? _map(Object? raw) {
    if (raw is String) raw = jsonDecode(raw);
    if (raw is! Map || raw.keys.any((key) => key is! String)) return null;
    return Map<String, dynamic>.from(raw);
  }

  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }

  static bool _isTerminal(Map<String, dynamic> payload) {
    if (payload['call_end'] == true || payload['call_end'] == 1) return true;
    final action = payload['action'];
    return action != null && action != 'invite';
  }
}
