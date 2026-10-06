import 'package:openim_common/openim_common.dart';

enum CallType { audio, video }

enum CallObj { single, group }

enum CallState {
  call,
  beCalled,
  reject,
  beRejected,
  calling,
  beAccepted,
  hangup,
  beHangup,
  connecting,
  otherAccepted,
  otherReject,
  cancel,
  beCanceled,
  timeout,
  join,
  networkError,
}

class CallEvent {
  CallEvent(this.state, this.data, {this.fields});
  final CallState state;
  final SignalingInfo data;
  final dynamic fields;
}
