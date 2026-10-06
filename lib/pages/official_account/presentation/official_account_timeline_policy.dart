import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Matches reference-99chat's TimeDividerConfig and attachTimeDividers:
/// compare adjacent visible messages, cross local calendar days, and use a
/// strict 300-second threshold rather than time since the last shown divider.
class OfficialAccountTimelinePolicy {
  OfficialAccountTimelinePolicy._();

  static const intervalSeconds = 300;

  static void markTimes(List<Message> messages) {
    int? previousTimestamp;
    for (final message in messages) {
      message.exMap = Map<String, dynamic>.of(message.exMap)
        ..remove('showTime');
      if (message.contentType == MessageType.typing ||
          message.contentType == MessageType.friendAddedNotification) {
        continue;
      }
      final timestamp = message.sendTime;
      if (timestamp == null) continue;
      if (previousTimestamp == null ||
          _differentDay(previousTimestamp, timestamp) ||
          // Tencent timestamps have whole-second precision.
          timestamp ~/ 1000 - previousTimestamp ~/ 1000 > intervalSeconds) {
        message.exMap['showTime'] = true;
      }
      previousTimestamp = timestamp;
    }
  }

  static bool _differentDay(int previous, int current) {
    final first = DateTime.fromMillisecondsSinceEpoch(previous);
    final second = DateTime.fromMillisecondsSinceEpoch(current);
    return first.year != second.year ||
        first.month != second.month ||
        first.day != second.day;
  }
}
