/// SDK versions expose seconds or milliseconds. Render in the device timezone.
String requestHistoryTime(int? timestamp,
    {bool group = false, bool english = false, DateTime? now}) {
  if (timestamp == null || timestamp <= 0) return '';
  final milliseconds = timestamp < 100000000000 ? timestamp * 1000 : timestamp;
  if (milliseconds > 8640000000000000) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final today = (now ?? DateTime.now()).toLocal();
  final day = DateTime(date.year, date.month, date.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  String pad(int value) => value.toString().padLeft(2, '0');
  if (day == todayDay) return '${pad(date.hour)}:${pad(date.minute)}';
  if (!group || date.year != today.year) {
    return '${date.year}-${pad(date.month)}-${pad(date.day)}';
  }
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return english ? 'Yesterday' : '昨天';
  }
  final days = todayDay.difference(day).inDays;
  if (days > 0 && days < 7) {
    return (english
        ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'])[date.weekday - 1];
  }
  return english ? '${date.month}/${date.day}' : '${date.month}月${date.day}日';
}
