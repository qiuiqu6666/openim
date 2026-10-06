// Ported from 99chat agent_rebate_date_range.dart (Apache-2.0).
const int agentRebateMaxInclusiveDays = 93;

/// 中国标准时相对 UTC 的固定偏移（无夏令时）。
const Duration agentRebateChinaOffset = Duration(hours: 8);

/// 业务日起点：中国时间早上 7 点；一天 = [07:00, 次日 07:00)。
const int agentRebateBusinessDayStartHour = 7;

DateTime agentRebateDateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

/// 将绝对时刻拆成中国墙钟日历分量（不含时区标记，仅年月日时分秒）。
DateTime agentRebateChinaWallClock(DateTime instant) {
  final utc = instant.isUtc ? instant : instant.toUtc();
  final china = utc.add(agentRebateChinaOffset);
  return DateTime(
    china.year,
    china.month,
    china.day,
    china.hour,
    china.minute,
    china.second,
    china.millisecond,
    china.microsecond,
  );
}

/// 测试/构造用：中国墙钟 → UTC 绝对时刻。
DateTime agentRebateInstantFromChinaWall(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
  int second = 0,
  int millisecond = 0,
  int microsecond = 0,
]) {
  return DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    millisecond,
    microsecond,
  ).subtract(agentRebateChinaOffset);
}

/// 当前业务日标签：包含 [instant] 的「中国时间 07:00 → 次日 07:00」窗口的起始日历日。
///
/// 例：中国 8/20 06:59 → 业务日 8/19；中国 8/20 07:00 → 业务日 8/20。
DateTime agentRebateBusinessDate([DateTime? instant]) {
  final china = agentRebateChinaWallClock(instant ?? DateTime.now());
  var calendar = DateTime(china.year, china.month, china.day);
  if (china.hour < agentRebateBusinessDayStartHour) {
    calendar = calendar.subtract(const Duration(days: 1));
  }
  return calendar;
}

int _agentRebateInclusiveDayCount(DateTime start, DateTime end) {
  final utcStart = DateTime.utc(start.year, start.month, start.day);
  final utcEnd = DateTime.utc(end.year, end.month, end.day);
  return utcEnd.difference(utcStart).inDays + 1;
}

String formatAgentRebateApiDate(DateTime value) {
  final date = agentRebateDateOnly(value);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$month-$day';
}

/// 绝对时刻按中国墙钟展示（yyyy-MM-dd HH:mm:ss）。
String formatAgentRebateChinaDateTime(DateTime? value) {
  if (value == null) return '';
  final china = agentRebateChinaWallClock(value);
  String two(int number) => number.toString().padLeft(2, '0');
  return '${china.year}-${two(china.month)}-${two(china.day)} '
      '${two(china.hour)}:${two(china.minute)}:${two(china.second)}';
}

enum AgentRebateDateRangeError { endBeforeStart, endAfterToday, exceedsMaximum }

class AgentRebateDateRange {
  AgentRebateDateRange({
    required DateTime start,
    required DateTime end,
    DateTime? today,
  })  : start = agentRebateDateOnly(start),
        end = agentRebateDateOnly(end) {
    final error = validate(
      start: this.start,
      end: this.end,
      today: today ?? agentRebateBusinessDate(),
    );
    if (error != null) {
      throw ArgumentError.value(error, 'range', error.name);
    }
  }

  /// [now] 为绝对时刻；预设按中国时间 07:00 业务日计算。
  factory AgentRebateDateRange.today([DateTime? now]) {
    return AgentRebateDateRange.recentDays(1, now);
  }

  factory AgentRebateDateRange.yesterday([DateTime? now]) {
    final today = agentRebateBusinessDate(now);
    final yesterday = today.subtract(const Duration(days: 1));
    return AgentRebateDateRange(
      start: yesterday,
      end: yesterday,
      today: today,
    );
  }

  factory AgentRebateDateRange.recentDays(int days, [DateTime? now]) {
    if (days < 1 || days > agentRebateMaxInclusiveDays) {
      throw RangeError.range(days, 1, agentRebateMaxInclusiveDays, 'days');
    }
    final today = agentRebateBusinessDate(now);
    return AgentRebateDateRange(
      start: today.subtract(Duration(days: days - 1)),
      end: today,
      today: today,
    );
  }

  final DateTime start;
  final DateTime end;

  int get inclusiveDays => _agentRebateInclusiveDayCount(start, end);

  String get startApiValue => formatAgentRebateApiDate(start);
  String get endApiValue => formatAgentRebateApiDate(end);

  static AgentRebateDateRangeError? validate({
    required DateTime start,
    required DateTime end,
    required DateTime today,
  }) {
    final normalizedStart = agentRebateDateOnly(start);
    final normalizedEnd = agentRebateDateOnly(end);
    final normalizedToday = agentRebateDateOnly(today);
    if (normalizedEnd.isBefore(normalizedStart)) {
      return AgentRebateDateRangeError.endBeforeStart;
    }
    if (normalizedEnd.isAfter(normalizedToday)) {
      return AgentRebateDateRangeError.endAfterToday;
    }
    if (_agentRebateInclusiveDayCount(normalizedStart, normalizedEnd) >
        agentRebateMaxInclusiveDays) {
      return AgentRebateDateRangeError.exceedsMaximum;
    }
    return null;
  }
}
