import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/request_history/presentation/request_history_time.dart';

void main() {
  final now = DateTime(2026, 10, 11, 15);
  test('seconds and milliseconds display the same local time', () {
    final time = DateTime(2026, 10, 11, 8, 7).millisecondsSinceEpoch;
    expect(requestHistoryTime(time, now: now), '08:07');
    expect(requestHistoryTime(time ~/ 1000, now: now), '08:07');
    expect(
        requestHistoryTime(
            DateTime.utc(2026, 10, 11, 0, 7).millisecondsSinceEpoch,
            now: now),
        requestHistoryTime(
            DateTime.utc(2026, 10, 11, 0, 7).toLocal().millisecondsSinceEpoch,
            now: now));
  });
  test('friend dates and group relative dates follow reference formats', () {
    final yesterday = DateTime(2026, 10, 10, 23).millisecondsSinceEpoch;
    expect(requestHistoryTime(yesterday, now: now), '2026-10-10');
    expect(requestHistoryTime(yesterday, now: now, group: true), '昨天');
    expect(requestHistoryTime(yesterday, now: now, group: true, english: true),
        'Yesterday');
    expect(
        requestHistoryTime(DateTime(2026, 10, 9).millisecondsSinceEpoch,
            now: now, group: true),
        '周五');
    expect(
        requestHistoryTime(DateTime(2026, 9, 1).millisecondsSinceEpoch,
            now: now, group: true),
        '9月1日');
  });
  test('unknown and malformed times do not display an epoch date', () {
    for (final value in [null, 0, -1, 8640000000000001]) {
      expect(requestHistoryTime(value, now: now), isEmpty);
    }
  });
}
