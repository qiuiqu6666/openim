/// OpenIM deadlines are Unix milliseconds. Earlier local optimistic updates
/// used Unix seconds; accept those at this single compatibility boundary.
class GroupMute {
  GroupMute._();

  static int milliseconds(int? deadline) {
    final value = deadline ?? 0;
    if (value <= 0) return 0;
    return value < 100000000000 ? value * 1000 : value;
  }

  static bool active(int? deadline, {required int nowMilliseconds}) =>
      milliseconds(deadline) > nowMilliseconds;

  static int afterSeconds(int seconds, {required int nowMilliseconds}) =>
      seconds <= 0 ? 0 : nowMilliseconds + seconds * 1000;

  static Duration? remaining(int? deadline, {required int nowMilliseconds}) {
    final remaining = milliseconds(deadline) - nowMilliseconds;
    return remaining > 0 ? Duration(milliseconds: remaining) : null;
  }
}
