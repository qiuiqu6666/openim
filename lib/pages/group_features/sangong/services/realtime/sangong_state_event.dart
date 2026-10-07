import '../../models/sangong_admin_realtime_state.dart';

/// Accept only a persisted message from the bot identified by an authenticated
/// HTTP snapshot. An event may update display state, never private permissions.
SangongAdminRealtimeState? readSangongStateEvent(
  Map<String, dynamic> envelope, {
  required String groupID,
  required String botUserID,
  required int currentVersion,
}) {
  if (botUserID.isEmpty ||
      envelope['key'] != 'sangongStateMessage' ||
      envelope['groupID'] != groupID ||
      envelope['senderID'] != botUserID ||
      envelope['serverMsgID'] is! String ||
      (envelope['serverMsgID'] as String).isEmpty ||
      envelope['seq'] is! int ||
      (envelope['seq'] as int) <= 0) {
    return null;
  }
  final event = envelope['data'];
  if (event is! Map ||
      event['type'] != 'sangong.event' ||
      event['schemaVersion'] != 2 ||
      event['groupId'] != groupID ||
      event['version'] is! int ||
      (event['version'] as int) <= currentVersion ||
      event['eventId'] is! String ||
      (event['eventId'] as String).isEmpty) {
    return null;
  }
  final state = event['state'];
  if (state is! Map ||
      state['groupId'] != groupID ||
      state['botUserId'] != botUserID ||
      state['version'] != event['version']) {
    return null;
  }
  try {
    return SangongAdminRealtimeState.fromRequiredJson(
        Map<String, dynamic>.from(state));
  } on FormatException {
    return null;
  }
}
