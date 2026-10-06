import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/official_account/presentation/official_account_timeline_policy.dart';

Message _message(int? milliseconds, {int type = MessageType.text}) => Message(
    sendTime: milliseconds,
    contentType: type,
    exMap: {'showTime': true, 'kept': 'metadata'});

List<bool> _marked(List<Message> messages) {
  OfficialAccountTimelinePolicy.markTimes(messages);
  return messages.map((message) => message.exMap['showTime'] == true).toList();
}

void main() {
  final midday = DateTime(2026, 10, 5, 12).millisecondsSinceEpoch;

  test('300 seconds is strict and compares each adjacent visible message', () {
    expect(
        _marked([
          _message(midday),
          _message(midday + 240000),
          _message(midday + 480000),
          _message(midday + 780000),
          _message(midday + 1081000),
        ]),
        [true, false, false, false, true]);
  });

  test('whole-second comparison matches reference SDK timestamp precision', () {
    expect(
        _marked([_message(midday), _message(midday + 300999)]), [true, false]);
    expect(
        _marked([_message(midday), _message(midday + 301000)]), [true, true]);
  });

  test('calendar-day changes show a divider even with a one-second gap', () {
    for (final midnight in [
      DateTime(2026, 10, 6),
      DateTime(2026, 11, 1),
      DateTime(2027, 1, 1),
    ]) {
      final timestamp = midnight.millisecondsSinceEpoch;
      expect(_marked([_message(timestamp - 1000), _message(timestamp)]),
          [true, true]);
    }
  });

  test('hidden SDK rows never show dates or replace a visible message anchor',
      () {
    expect(
        _marked([
          _message(midday, type: MessageType.friendAddedNotification),
          _message(midday + 1000),
          _message(midday + 301000, type: MessageType.typing),
          _message(midday + 302000),
        ]),
        [false, true, false, true]);
  });

  test('missing timestamps are safe and other extension metadata is retained',
      () {
    final messages = [_message(null), _message(midday), _message(null)];
    expect(_marked(messages), [false, true, false]);
    for (final message in messages) {
      expect(message.exMap['kept'], 'metadata');
    }
  });

  test('recalculating after older history arrives replaces stale date flags',
      () {
    final latest = _message(midday + 1000);
    expect(_marked([latest]), [true]);
    final oldest = _message(midday);
    expect(_marked([oldest, latest]), [true, false]);
  });
}
