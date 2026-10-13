import 'package:openim_common/openim_common.dart';

import 'call_state_runtime.dart';

/// Server commit precedes every 200..204 send; failures cannot grant admission.
Future<void> persistCallSignal(int type, InvitationInfo invitation) =>
    CallStateRuntime.instance.persist(type, invitation);
