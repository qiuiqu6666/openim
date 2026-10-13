import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';

/// Only authenticated /calling responses may become authoritative snapshots.
class CallStateSnapshot {
  CallStateSnapshot._(this.raw, this.invitation, this.revision, this.state);
  final Map<String, dynamic> raw;
  final InvitationInfo invitation;
  final int revision;
  final String state;
  String get room => invitation.roomID!;
  String? get reason => raw['reason'] is String ? raw['reason'] as String : null;
  String? get callerName => raw['callerName'] is String ? raw['callerName'] as String : null;
  String? get callerDevice => raw['callerDeviceID'] as String?;
  String? get answeredDevice => raw['answeredDeviceID'] as String?;
  bool get terminal => const ['rejected', 'cancelled', 'ended', 'expired']
      .contains(state);
  bool get ringing => state == 'ringing';
  bool incoming(String account) => invitation.inviterUserID != account;
  bool participant(String account, String device) =>
      (incoming(account) ? answeredDevice : callerDevice) == device;
  bool answeredElsewhere(String account, String device) =>
      state == 'accepted' && incoming(account) && answeredDevice != device;
  bool get expiredInvitation {
    if (!ringing) return false;
    final expires = raw['expiresAt'];
    return expires is int && expires <= DateTime.now().millisecondsSinceEpoch;
  }

  static CallStateSnapshot decode(Map<String, dynamic> raw, String account,
      {String? room}) {
    final data = raw['invitation'];
    final version = raw['revision'] ?? 0;
    final state = raw['state'];
    if (data is! Map ||
        version is! int || version < 0 ||
        !const ['ringing', 'accepted', 'rejected', 'cancelled', 'ended', 'expired']
            .contains(state) ||
        (raw['callerDeviceID'] != null && raw['callerDeviceID'] is! String) ||
        (raw['answeredDeviceID'] != null && raw['answeredDeviceID'] is! String)) {
      throw const FormatException('Invalid call snapshot');
    }
    final invitation = InvitationInfo.fromJson(Map<String, dynamic>.from(data));
    if (!validCallInvitation(invitation) ||
        !validCallID(invitation.roomID) ||
        invitation.sessionType != 1 ||
        (room != null && invitation.roomID != room) ||
        (invitation.inviterUserID != account &&
            !invitation.inviteeUserIDList!.contains(account)) ||
        (state == 'accepted' &&
            (raw['answeredDeviceID'] is! String ||
                (raw['answeredDeviceID'] as String).isEmpty))) {
      throw const FormatException('Call snapshot identity mismatch');
    }
    return CallStateSnapshot._(Map.unmodifiable(raw), invitation, version,
        state as String);
  }
}
