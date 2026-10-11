import 'package:openim_common/openim_common.dart';

import 'call_backend_api.dart';
import 'call_state_heartbeat.dart';

/// Persists transitions before the existing OpenIM 200..204 signal is sent.
/// A missing record on a received legacy invitation keeps online compatibility.
Future<void> persistCallSignal(int type, InvitationInfo invitation) async {
  if (type >= CustomMessageType.callingReject) {
    CallStateHeartbeat.stop(invitation.roomID!);
  }
  final api = await CallBackendApi.current();
  var retained = false;
  try {
    if (type == CustomMessageType.callingInvite) {
      final state = await api.invite(invitation);
      if (state['state'] != 'ringing') throw const CallBackendException(409);
      CallStateHeartbeat.start(invitation.roomID!, api);
      retained = true;
    } else {
      final action = switch (type) {
        CustomMessageType.callingAccept => 'accept',
        CustomMessageType.callingReject => 'reject',
        CustomMessageType.callingCancel => 'cancel',
        CustomMessageType.callingHungup => 'hangup',
        _ => throw const CallBackendException(400),
      };
      try {
        await api.request('action', {
          'callID': invitation.roomID,
          'deviceID': api.deviceID,
          'action': action,
          'invitation': invitation.toJson(),
        });
        if (type == CustomMessageType.callingAccept) {
          CallStateHeartbeat.start(invitation.roomID!, api);
          retained = true;
        }
      } on CallBackendException catch (error) {
        if (error.code != 404) rethrow;
      }
    }
  } finally {
    if (!retained) api.close();
  }
}
