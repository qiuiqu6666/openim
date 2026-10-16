import 'package:openim_common/openim_common.dart' show InvitationInfo;

import '../models/call_types.dart';
import '../session/single_call_session.dart';

/// Identity and the verified original invitation of one system call.
class SystemCallDescriptor {
  const SystemCallDescriptor({
    required this.accountID,
    required this.roomID,
    required this.peerUserID,
    required this.callType,
    required this.incoming,
    required this.invitation,
    this.deadline,
    this.peerName,
  });

  final String accountID, roomID, peerUserID;
  final CallType callType;
  final bool incoming;
  final InvitationInfo invitation;
  final DateTime? deadline;
  final String? peerName;
}

/// The application owns native CallKit and push verification. The call package
/// owns the same signaling, cancellable session and RTC room for UI and native
/// actions. Audio starts only after the native provider activates its session.
abstract interface class SystemCallAdapter {
  Future<void> reportIncoming(SystemCallDescriptor call);
  Future<void> startOutgoing(SystemCallDescriptor call);
  Future<bool> requestAnswer(SystemCallDescriptor call);
  Future<void> transportConnected(SystemCallDescriptor call);
  Future<void> waitForAudio(SystemCallDescriptor call);
  Future<void> peerConnected(SystemCallDescriptor call);
  Future<void> microphoneChanged(SystemCallDescriptor call, bool enabled);
  Future<void> speakerChanged(SystemCallDescriptor call, bool enabled);
  Future<void> callEnded(SystemCallDescriptor call, CallTermination result);
}

/// Chooses the owner once per incoming call, before media or ringing starts.
/// Existing native calls must retain their system answer/audio lifecycle.
abstract interface class IncomingSystemCallPolicy {
  Future<bool> usesSystemIncomingCall(String roomID);
}
