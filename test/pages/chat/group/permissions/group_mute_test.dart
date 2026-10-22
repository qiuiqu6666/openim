import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/group/permissions/group_mute.dart';

void main() {
  const now = 1792627200000;
  test('server milliseconds and legacy local seconds share one deadline', () {
    for (final deadline in [now + 60000, (now + 60000) ~/ 1000]) {
      expect(GroupMute.active(deadline, nowMilliseconds: now), isTrue);
      expect(GroupMute.remaining(deadline, nowMilliseconds: now),
          const Duration(minutes: 1));
      expect(GroupMute.active(deadline, nowMilliseconds: now + 60000), isFalse);
      expect(
          GroupMute.remaining(deadline, nowMilliseconds: now + 60001), isNull);
    }
  });
  test('new local results use milliseconds and zero is explicitly unmuted', () {
    expect(GroupMute.afterSeconds(60, nowMilliseconds: now), now + 60000);
    expect(GroupMute.afterSeconds(0, nowMilliseconds: now), 0);
    for (final deadline in [null, 0, -1, now - 1]) {
      expect(GroupMute.active(deadline, nowMilliseconds: now), isFalse);
      expect(GroupMute.remaining(deadline, nowMilliseconds: now), isNull);
    }
  });
}
